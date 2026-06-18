# AGENTS.md — Application Reference

This file documents the application for AI agents so they can quickly understand the codebase without re-exploring it each session.

---

## Active Migrations

_None in progress. Chaos engineering → DevCycle feature flags migration completed; see [`docs/chaos-devcycle-migration.md`](docs/chaos-devcycle-migration.md) for the historical plan and gotchas._

## Overview

A full-stack AI chatbot that uses the **NVIDIA NIM API** (via LangChain) to serve responses from `meta/llama-3.1-8b-instruct`. It includes **OpenTelemetry** telemetry exported to **Dynatrace**. Two frontend clients are provided: a React web app and a Flutter mobile/desktop app.

- **Backend**: Python / FastAPI (`backend/`)
- **React Frontend**: React / Vite (`frontend/`)
- **Flutter Frontend**: Flutter (`flutter_frontend/`)
- **Load Generator**: Python / asyncio (`load_gen/`)

---

## Tech Stack

| Layer | Technology |
|---|---|
| LLM | NVIDIA NIM — `meta/llama-3.1-8b-instruct` |
| LLM client | `langchain-nvidia-ai-endpoints`, `langchain` |
| Backend framework | FastAPI + uvicorn |
| Telemetry | Traceloop SDK → Dynatrace OTLP endpoint |
| React frontend | React 19 (Vite, React Router v7, CSS Modules) |
| React-to-backend proxy | Vite dev server `/api` → `localhost:8000` |
| Flutter frontend | Flutter 3.x, `provider` state management, `dynatrace_flutter_plugin` |
| Flutter HTTP | `Dynatrace().createHttpClient()` (instrumented) |

---

## Environment Variables (unified `.env` at repo root)

A single `.env` at the repo root is the source of truth for the backend, the
load generator, and the frontend build. See `.env.example` for full
documentation; summary below.

| Variable | Required | Used by | Description |
|---|---|---|---|
| `NVIDIA_API_KEY` | Yes | backend | NVIDIA NIM API key (`nvapi-...`) |
| `DEVCYCLE_SERVER_SDK_KEY` | No | backend | DevCycle server SDK key. If unset, chaos engineering is disabled (all chaos vars fall back to defaults). |
| `OTLP_ENDPOINT` | No* | backend, load_gen | OTel collector HTTP/protobuf endpoint (e.g. `http://localhost:4318`) |
| `ALLOWED_ORIGINS` | No | backend | Extra CORS origins (default: localhost + VM IP/hostname appended by `setup.sh`) |
| `SELF_HOSTED_NIM_URL` | No | backend | Base URL for a self-hosted NIM instance |
| `VITE_DYNATRACE_RUM_URL` | No | frontend build | Dynatrace RUM JS tag URL, baked into the React build |
| `LOAD_GEN_URL` | No | load_gen | Backend base URL (default `http://localhost:8000`) |
| `LOAD_GEN_CONCURRENCY` | No | load_gen | Worker count (default `10`) |
| `LOAD_GEN_PROVIDER` | No | load_gen | `nim_api` or `self_hosted` |
| `LOAD_GEN_RATE` | No | load_gen | Target req/s; unset = constant-concurrency mode |
| `SERVER_NAME` | No | setup.sh | nginx `server_name` on the VM (default: VM IP) |

*Traceloop / OTel export is skipped with a warning if `OTLP_ENDPOINT` is absent. The services start without it.

On the VM, `deploy/setup.sh` copies the root `.env` to `/opt/chatbot/.env`,
which both systemd units read via `EnvironmentFile=`. systemd silently ignores
vars a given process doesn't consume.

---

## Backend Structure (`backend/`)

```
main.py                  — FastAPI app setup: CORS, Traceloop init (optional), router registration
routers/chat.py          — API route handlers for chat endpoints
routers/chaos.py         — API route handlers for chaos/fault injection
routers/config.py        — API route handlers for app configuration
services/llm.py          — LangChain chain construction and session management
services/chaos.py        — Chaos configuration service with presets and injection helpers
services/app_config.py   — App configuration service (system prompt, provider)
models/schemas.py        — Pydantic request/response models
requirements.txt         — Python dependencies
```

### API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/health` | Liveness check → `{"status": "ok"}` |
| `POST` | `/api/chat` | Send a message, receive assistant reply |
| `POST` | `/api/chat/starters` | Generate starter suggestions for a given system prompt |
| `DELETE` | `/api/chat/{session_id}` | Clear server-side conversation history for a session |
| `GET` | `/api/config` | Get current app configuration (system prompt, provider) |
| `PATCH` | `/api/config` | Update app configuration |
| `GET` | `/api/chaos` | Get current chaos config (read-only; values served by DevCycle) |
| `GET` | `/api/chaos/presets` | List available chaos preset names |
| `GET` | `/api/chaos/status` | Get chaos status: `{active, config, preset, controlled_by: "devcycle"}` |
| `POST` | `/api/config/reset` | Reset app configuration to defaults |

### `POST /api/chat` Request Body (`ChatRequest`)

```json
{
  "session_id": "uuid-string",
  "message": "user text",
  "system_prompt": "You are a helpful assistant.",
  "provider": "nim_api"
}
```

`provider` must be `"nim_api"` (default) or `"self_hosted"`. Returns `{"reply": "assistant text", "suggestions": ["q1", "q2", "q3"]}`.

### `POST /api/chat/starters` Request Body (`StarterRequest`)

```json
{
  "system_prompt": "You are a helpful assistant.",
  "provider": "nim_api"
}
```

Returns `{"suggestions": ["q1", "q2", "q3"]}` — up to 3 conversation-starter questions based on the system prompt.

### Session Management (`services/llm.py`)

- In-memory `dict[session_id → ChatMessageHistory]` — **not** persisted across server restarts.
- A new `RunnableWithMessageHistory` chain is built per request using the session's system prompt.
- After the main reply, `get_suggestions(message, reply)` makes a **stateless** second LLM call and returns up to 3 follow-up question strings (returns `[]` on any failure).
- `get_starter_suggestions(system_prompt, provider)` is stateless and returns up to 3 opening questions.
- `clear_session(session_id)` removes the entry from the dict.

---

## React Frontend Structure (`frontend/src/`)

```
App.jsx                        — React Router shell: / → ChatPage, /config → ConfigPage
main.jsx                       — Entry point; wraps App in BrowserRouter and ConfigProvider
context/ConfigContext.jsx      — Global state for app config + chaos config; polls chaos every 5s
hooks/useChat.js               — Chat state and API logic: messages, session ID, suggestions
pages/ChatPage.jsx             — Chat page: header, chaos banner, message list, chips, input bar
pages/ConfigPage.jsx           — Settings page: system prompt, provider, read-only chaos config (DevCycle-controlled)
components/ChatWindow.jsx      — Scrollable message list, auto-scrolls to bottom
components/MessageBubble.jsx   — Renders a single user or assistant message (markdown for assistant)
components/InputBar.jsx        — Text input + send button
components/SuggestionChips.jsx — Follow-up question pill buttons (shown after each bot reply)
```

### `ConfigContext` (key details)

- Provides `appConfig` (system prompt, provider) and `chaosConfig` (read-only chaos values served by DevCycle) to the entire app.
- Fetches `GET /api/config` and `GET /api/chaos/status` on mount.
- Polls chaos status every 5 seconds and re-fetches on browser tab visibility change.
- Exposes `updateAppConfig()` for the `ConfigPage`. Chaos is read-only — write operations live in DevCycle.

### `useChat` Hook (key details)

- Generates a stable `sessionId` with `crypto.randomUUID()` per browser tab (lost on page reload).
- Maintains `messages` (`[{ role, content }]`), `isStreaming`, and `suggestions` state.
- Reads `appConfig` from `ConfigContext` — does **not** manage system prompt or provider locally.
- `sendMessage(text)`: POSTs to `/api/chat` with `session_id` and `message` only (server uses its own config for system prompt and provider).
- `clearHistory()`: DELETEs `/api/chat/{sessionId}` and resets `messages` to `[]`.
- `suggestions` (`string[]`): 2–3 follow-up question chips from the latest bot reply; cleared immediately when the user sends a new message or calls `clearHistory()`.
- Fetches starter suggestions via `POST /api/chat/starters` (empty body — server uses its own config) when the message list is empty or when `appConfig.system_prompt` changes.

---

## Flutter Frontend Structure (`flutter_frontend/`)

```
lib/
  main.dart                    — App entry point; starts Dynatrace, bootstraps MaterialApp with routing
  config.dart                  — baseUrl compile-time constant (--dart-define=BASE_URL=...)
  models/
    chat_message.dart          — ChatMessage (role, content)
    chat_request.dart          — ChatRequest (toJson)
    chat_response.dart         — ChatResponse (fromJson)
    starter_request.dart       — StarterRequest (toJson)
    starter_response.dart      — StarterResponse (fromJson)
    app_config.dart            — AppConfig model (system prompt, provider)
    chaos_config.dart          — ChaosConfig model + ChaosStatus wrapper (read-only; values from DevCycle)
  providers/
    chat_provider.dart         — ChangeNotifier; messages, session ID, suggestions
    config_provider.dart       — ChangeNotifier; app config + chaos status, polls chaos every 5s
  services/
    api_service.dart           — HTTP client (Dynatrace-instrumented); chat, config, and chaos status endpoints
  screens/
    chat_screen.dart           — Scaffold; chat UI with chaos banner, message list, chips, input bar
    config_screen.dart         — Settings page: system prompt, provider, read-only chaos config (DevCycle-controlled)
  widgets/
    chat_window.dart           — Reversed ListView of MessageBubble
    input_bar.dart             — TextField + send button (Dynatrace UserInteractionWidget)
    message_bubble.dart        — User plain text / assistant MarkdownBody + typing indicator
    suggestion_chips.dart      — Wrap of OutlinedButton chips (Dynatrace UserInteractionWidget)
    system_prompt_panel.dart   — ExpansionTile with TextField; locked when conversation active
    llm_provider_panel.dart    — ExpansionTile with radio group; locked when conversation active
    chaos_banner.dart          — Orange warning banner when chaos is active; tappable to open settings
```

### Flutter key details

- **`baseUrl`** is set at compile time via `--dart-define=BASE_URL=http://...`; defaults to `http://localhost:8000`.
- Use `10.0.2.2` instead of `localhost` when running on Android emulators.
- **`dynatrace.config.yaml`** is gitignored — copy from `dynatrace.config.yaml.example` and populate with your Dynatrace Application ID and beacon URL before building.
- State management: `provider` package with `ChatProvider` and `ConfigProvider` (`ChangeNotifier`).
- `ConfigProvider` fetches app config and chaos status from the backend, polls chaos every 5 seconds, and re-fetches on app resume. Chaos values are read-only and sourced from DevCycle.
- Two routes: `/` (ChatScreen) and `/config` (ConfigScreen).
- Session ID generated once per app launch with `const Uuid().v4()`.
- All HTTP calls go through `Dynatrace().createHttpClient()` for automatic RUM tracing.

---

## Running Locally

```bash
# One-time: create the unified .env at the repo root
cp .env.example .env   # then fill in NVIDIA_API_KEY (everything else optional)

# Backend (terminal 1)
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
# → http://localhost:8000

# React frontend (terminal 2)
cd frontend
npm install
npm run dev
# → http://localhost:5173  (proxies /api to :8000)

# Flutter frontend (terminal 3)
cd flutter_frontend
cp dynatrace.config.yaml.example dynatrace.config.yaml  # fill in credentials
flutter pub get
flutter run --dart-define=BASE_URL=http://localhost:8000

# Load generator (terminal 4, optional) — reads the same root .env
cd load_gen
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python load_gen.py
```

---

## Key Conventions

- Backend modules and `load_gen/load_gen.py` use `python-dotenv` with an **explicit path** to the repo-root `.env` (via `Path(__file__).resolve().parents[N]`), so they work regardless of CWD. On the VM, systemd injects the same vars via `EnvironmentFile=/opt/chatbot/.env`, making `load_dotenv()` a no-op there.
- Frontend CSS uses **CSS Modules** (`.module.css`); no global CSS framework.
- The backend registers three routers: `routers/chat.py` at `/api`, `routers/chaos.py` at `/api/chaos`, and `routers/config.py` at `/api/config`.
- Traceloop SDK is initialised **before** FastAPI is imported in `main.py` so instrumentation wraps everything (skipped gracefully if Dynatrace vars are absent).
- `dynatrace.config.yaml` is gitignored; the `.example` file in the same directory is the template.

---

## Observability

This application is monitored with Dynatrace - an observability platform. Details on monitoring instrumentation can be found in the README files throughout this workspace.

To interact with Dynatrace, you can use either the MCP or dtctl CLI tool.

### DQL Tips
Here are some example queries to show how to filter for this application's telemetry data in Dynatrace.

Before ever running a specific DQL query with a filter, summarize, etc., you MUST run a generic query to understand the structure and available fields that can be used for refining your queries.

For example:
```
fetch spans|logs|events
| limit 10
```

#### Traces/Spans
```
fetch spans
| filter dt.service.name == "nvidia-chatbot"
```

#### Logs
```
fetch logs
| filter service.name == "nvidia-chatbot"
```

#### Real User Monitoring

Flutter Frontend
```
fetch user.events
| filter frontend.name == "AI_Chatbot_Flutter"
```
```
fetch user.sessions 
| filter in(frontend.name, {"AI_Chatbot_Flutter"}) 
| summarize {sessions = count()}, by:{frontend.name}
```


Frontend
```
fetch user.events
| filter frontend.name == "AI_Chatbot"
```
```
fetch user.sessions 
| filter in(frontend.name, {"AI_Chatbot"}) 
| summarize {sessions = count()}, by:{frontend.name}
```

#### Specifying the timeframe
```
fetch logs, from:now() - 30m
| filter service.name == "nvidia-chatbot"
```