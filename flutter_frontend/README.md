# Flutter Frontend

### Disclaimer
This has only been tested using a Mac running an iOS Simulator. For managing Ruby dependencies, I used mise. This file is not comprehensive on the setup of flutter, cocoapods, etc. to get started with mobile app development.

---

Flutter chatbot UI that mirrors the React frontend. Communicates with the backend over REST, manages a per-launch session ID, renders assistant replies as Markdown, and shows context-aware follow-up suggestion chips. Instrumented with the Dynatrace Flutter plugin for RUM tracing.

> **Local use only.** This app is designed for local development and testing against a local or remote backend instance.

---

## Key files

| File | Role |
|---|---|
| `lib/main.dart` | App entry point; starts Dynatrace, bootstraps `MaterialApp` with routing |
| `lib/config.dart` | `baseUrl` compile-time constant set via `--dart-define=BASE_URL=…` |
| `lib/providers/chat_provider.dart` | `ChangeNotifier`; messages, session ID, suggestions |
| `lib/providers/config_provider.dart` | `ChangeNotifier`; app config + chaos config, polls chaos every 5s |
| `lib/services/api_service.dart` | HTTP client (Dynatrace-instrumented); chat, config, and chaos endpoints |
| `lib/screens/chat_screen.dart` | Chat scaffold; chaos banner, message list, chips, input bar |
| `lib/screens/config_screen.dart` | Settings page; system prompt, provider, chaos presets and controls |
| `lib/widgets/chat_window.dart` | Reversed `ListView` of `MessageBubble` widgets |
| `lib/widgets/message_bubble.dart` | User plain text / assistant `MarkdownBody` + typing indicator |
| `lib/widgets/input_bar.dart` | `TextField` + send button |
| `lib/widgets/suggestion_chips.dart` | `Wrap` of `OutlinedButton` chips for follow-up and starter questions |
| `lib/widgets/system_prompt_panel.dart` | `ExpansionTile` with `TextField`; locked when a conversation is active |
| `lib/widgets/llm_provider_panel.dart` | `ExpansionTile` with radio group for `nim_api` / `self_hosted`; locked when a conversation is active |
| `lib/widgets/chaos_banner.dart` | Orange warning banner when chaos is active; tappable to open settings |
| `lib/widgets/chaos_preset_buttons.dart` | Grid of preset buttons (healthy, slow_llm, flaky_network, etc.) |
| `lib/widgets/llm_failures_section.dart` | Sliders and switches for LLM chaos fields |
| `lib/widgets/latency_injection_section.dart` | Controls for fixed, random, and spike delay injection |
| `lib/widgets/http_errors_section.dart` | Sliders for HTTP 500/503 and session error rates |
| `lib/models/chat_message.dart` | ChatMessage model (role, content) |
| `lib/models/chat_request.dart` | ChatRequest model (toJson) |
| `lib/models/chat_response.dart` | ChatResponse model (fromJson) |
| `lib/models/starter_request.dart` | StarterRequest model (toJson) |
| `lib/models/starter_response.dart` | StarterResponse model (fromJson) |
| `lib/models/app_config.dart` | AppConfig model (system prompt, provider) |
| `lib/models/chaos_config.dart` | ChaosConfig model (18 injectable failure fields) |

---

## Configuration

### Backend URL

`baseUrl` defaults to `http://localhost:8000` and is set at compile time via `--dart-define`:

```bash
flutter run --dart-define=BASE_URL=http://localhost:8000
```

When running on an **Android emulator**, use `10.0.2.2` instead of `localhost` to reach the host machine:

```bash
flutter run --dart-define=BASE_URL=http://10.0.2.2:8000
```

### Dynatrace (`dynatrace.config.yaml`)

`dynatrace.config.yaml` is gitignored. Copy the example and populate with your Dynatrace credentials before building:

```bash
cp dynatrace.config.yaml.example dynatrace.config.yaml
```

Edit `dynatrace.config.yaml` and replace:

- `YOUR_DYNATRACE_APPLICATION_ID` — your Dynatrace RUM application ID
- `YOUR_ENVIRONMENT_ID` — your Dynatrace environment ID

If you do not have Dynatrace credentials, the app will still build and run; the plugin simply will not report telemetry.

---

## Running locally

The backend must be running first (see [backend/README.md](../backend/README.md)).

```bash
cd flutter_frontend
flutter pub get
flutter run --dart-define=BASE_URL=http://localhost:8000
```

To target a specific device (list available devices first):

```bash
flutter devices
flutter run -d <device-id> --dart-define=BASE_URL=http://localhost:8000
```

Common targets for local testing:

| Target | Command |
|---|---|
| macOS desktop | `flutter run -d macos --dart-define=BASE_URL=http://localhost:8000` |
| iOS simulator | `flutter run -d <simulator-id> --dart-define=BASE_URL=http://localhost:8000` |
| Android emulator | `flutter run -d <emulator-id> --dart-define=BASE_URL=http://10.0.2.2:8000` |

### NOTE: If running a remote backend...
Run the app with the server's URL instead either using flutter run (e.g. `--dart-define=BASE_URL=http://ec2-77-94-132-15.compute-1.amazonaws.com`) or updating the `defaultValue` in the `config.dart` file.

---

## Key behaviours

### Routing

- Two routes: `/` (ChatScreen) and `/config` (ConfigScreen).
- The chat screen app bar includes a settings icon to navigate to `/config` and a clear button to reset the conversation.

### Session ID

A UUID is generated once per app launch via `const Uuid().v4()` and is stable for the lifetime of the process. Restarting the app creates a new session — previous messages are lost from both the UI and the server.

### System prompt and provider

- The system prompt and LLM provider are managed on the `/config` settings screen via `ConfigProvider`.
- Changes are saved to the backend via `PATCH /api/config` and take effect on the next chat message.
- `ChatProvider` delegates to `ConfigProvider` for system prompt and provider values.

### Chaos engineering

- `ConfigProvider` fetches chaos config on init and polls every 5 seconds to stay in sync.
- When any chaos setting is active, an orange warning banner appears on the chat screen.
- The settings screen (`/config`) provides preset buttons (healthy, slow_llm, flaky_network, rate_limited, degraded) and granular controls for LLM failures, latency injection, and HTTP error rates.

### Starter suggestions

When the conversation is empty (on launch, or after clearing history), the app calls `POST /api/chat/starters` using the current system prompt and displays the results as suggestion chips.

### Follow-up suggestions

After each assistant reply, the backend returns up to 3 follow-up question strings. These appear as chips below the reply. Tapping a chip sends that question as a new message and clears the chips.

### Markdown rendering

Assistant messages are rendered using `flutter_markdown`, supporting code blocks, tables, links, and lists.
