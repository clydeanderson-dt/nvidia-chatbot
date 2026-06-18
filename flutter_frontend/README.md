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
- `YOUR_DYNATRACE_BEACON_URL` — your Dynatrace beacon URL

Run the following to apply the Dynatrace configs:

```bash
dart run dynatrace_flutter_plugin
```

If you do not have Dynatrace credentials, the app will still build and run; the plugin simply will not report telemetry.

#### ⚠️⚠️ NOTE ⚠️⚠️: After running the above command to configure Dynatrace, there will be artifacts (info.plist, build.gradle.kts, etc.) that will be altered and contain sensitive Dynatrace config information. It is essential to ensure this information is not committed.

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

For the full design rationale (routing, session lifecycle, system-prompt
and provider flow, starter/follow-up suggestions, chaos read-only model),
see [`docs/architecture.md`](../docs/architecture.md).

Component-specific notes:

- **Session ID** — generated once per app launch via `const Uuid().v4()`;
  restarting the app creates a new session.
- **Routing** — `/` is the chat screen, `/config` is the settings screen.
- **Markdown** — assistant messages render via `flutter_markdown`.
- **Chaos** — `ConfigProvider` polls `/api/chaos/status` every 5s and on app
  resume; chaos is read-only here (controlled by DevCycle). See
  [`docs/devcycle-openfeature.md`](../docs/devcycle-openfeature.md).
