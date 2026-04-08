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
| `lib/main.dart` | App entry point; starts Dynatrace, bootstraps `MaterialApp` |
| `lib/config.dart` | `baseUrl` compile-time constant set via `--dart-define=BASE_URL=…` |
| `lib/providers/chat_provider.dart` | `ChangeNotifier`; single source of truth for messages, session ID, system prompt, provider, suggestions |
| `lib/services/api_service.dart` | HTTP client (Dynatrace-instrumented); `postChat`, `postStarters`, `deleteSession` |
| `lib/screens/chat_screen.dart` | Root scaffold; composes all widgets |
| `lib/widgets/chat_window.dart` | Reversed `ListView` of `MessageBubble` widgets |
| `lib/widgets/message_bubble.dart` | User plain text / assistant `MarkdownBody` + typing indicator |
| `lib/widgets/input_bar.dart` | `TextField` + send button |
| `lib/widgets/suggestion_chips.dart` | `Wrap` of `OutlinedButton` chips for follow-up and starter questions |
| `lib/widgets/system_prompt_panel.dart` | `ExpansionTile` with `TextField`; locked when a conversation is active |
| `lib/widgets/llm_provider_panel.dart` | `ExpansionTile` with radio group for `nim_api` / `self_hosted`; locked when a conversation is active |

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

---

## Key behaviours

### Session ID

A UUID is generated once per app launch via `const Uuid().v4()` and is stable for the lifetime of the process. Restarting the app creates a new session — previous messages are lost from both the UI and the server.

### System prompt and provider

- The system prompt and LLM provider selector are **locked** while there are messages in the conversation.
- Changes only take effect after clearing the conversation history (tap the clear button in the app bar).
- The system prompt applies to the **next** message sent; it does not alter existing messages retroactively.

### Starter suggestions

When the conversation is empty (on launch, or after clearing history), the app calls `POST /api/chat/starters` using the current system prompt and displays the results as suggestion chips.

### Follow-up suggestions

After each assistant reply, the backend returns up to 3 follow-up question strings. These appear as chips below the reply. Tapping a chip sends that question as a new message and clears the chips.

### Markdown rendering

Assistant messages are rendered using `flutter_markdown`, supporting code blocks, tables, links, and lists.
