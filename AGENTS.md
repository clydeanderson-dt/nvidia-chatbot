# AGENTS.md — Application Reference

This file documents the application for AI agents so they can quickly understand the codebase without re-exploring it each session.

---

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
| React frontend | React 19 (Vite, CSS Modules) |
| React-to-backend proxy | Vite dev server `/api` → `localhost:8000` |
| Flutter frontend | Flutter 3.x, `provider` state management, `dynatrace_flutter_plugin` |
| Flutter HTTP | `Dynatrace().createHttpClient()` (instrumented) |

---

## Environment Variables (`.env` in `backend/`)

| Variable | Required | Description |
|---|---|---|
| `NVIDIA_API_KEY` | Yes | NVIDIA NIM API key (`nvapi-...`) |
| `DYNATRACE_OTLP_ENDPOINT` | No* | `https://{environmentId}.live.dynatrace.com` |
| `DYNATRACE_API_TOKEN` | No* | Dynatrace token with `openTelemetryTrace.ingest`, `metrics.ingest`, `logs.ingest` scopes |
| `ALLOWED_ORIGINS` | No | Comma-separated CORS origins (default: `http://localhost:5173,http://localhost:3000`) |
| `SELF_HOSTED_NIM_URL` | No | Base URL for a self-hosted NIM instance (enables `self_hosted` provider) |

*Traceloop init and telemetry export are skipped with a warning if Dynatrace vars are absent. The server starts without them.

---

## Backend Structure (`backend/`)

```
main.py                  — FastAPI app setup: CORS, Traceloop init (optional), router registration
routers/chat.py          — API route handlers
services/llm.py          — LangChain chain construction and session management
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
App.jsx                        — Root component; composes all sub-components
hooks/useChat.js               — All chat state and API logic (single hook)
components/ChatWindow.jsx      — Scrollable message list, auto-scrolls to bottom
components/MessageBubble.jsx   — Renders a single user or assistant message (markdown for assistant)
components/InputBar.jsx        — Text input + send button
components/SystemPromptPanel.jsx — Collapsible textarea to edit system prompt
components/LLMProviderPanel.jsx  — Collapsible radio group to select LLM provider
components/SuggestionChips.jsx — Follow-up question pill buttons (shown after each bot reply)
```

### `useChat` Hook (key details)

- Generates a stable `sessionId` with `crypto.randomUUID()` per browser tab (lost on page reload).
- Maintains `messages` (`[{ role, content }]`), `isStreaming`, `systemPrompt`, and `llmProvider` state.
- `sendMessage(text)`: POSTs to `/api/chat` with `provider` field, fills in the last (placeholder) assistant message on response.
- `clearHistory()`: DELETEs `/api/chat/{sessionId}` and resets `messages` to `[]`.
- `suggestions` (`string[]`): 2–3 follow-up question chips from the latest bot reply; cleared immediately when the user sends a new message or calls `clearHistory()`.
- Fetches starter suggestions via `POST /api/chat/starters` when the message list is empty.
- The system prompt and provider take effect on the **next** message sent (locked while a conversation is in progress).

---

## Flutter Frontend Structure (`flutter_frontend/`)

```
lib/
  main.dart                    — App entry point; starts Dynatrace, bootstraps MaterialApp
  config.dart                  — baseUrl compile-time constant (--dart-define=BASE_URL=...)
  models/
    chat_message.dart          — ChatMessage (role, content)
    chat_request.dart          — ChatRequest (toJson)
    chat_response.dart         — ChatResponse (fromJson)
    starter_request.dart       — StarterRequest (toJson)
    starter_response.dart      — StarterResponse (fromJson)
  providers/
    chat_provider.dart         — ChangeNotifier; mirrors useChat hook logic
  services/
    api_service.dart           — HTTP client (Dynatrace-instrumented); postChat, postStarters, deleteSession
  screens/
    chat_screen.dart           — Scaffold; composes all widgets
  widgets/
    chat_window.dart           — Reversed ListView of MessageBubble
    input_bar.dart             — TextField + send button (Dynatrace UserInteractionWidget)
    message_bubble.dart        — User plain text / assistant MarkdownBody + typing indicator
    suggestion_chips.dart      — Wrap of OutlinedButton chips (Dynatrace UserInteractionWidget)
    system_prompt_panel.dart   — ExpansionTile with TextField; locked when conversation active
    llm_provider_panel.dart    — ExpansionTile with radio group; locked when conversation active
```

### Flutter key details

- **`baseUrl`** is set at compile time via `--dart-define=BASE_URL=http://...`; defaults to `http://localhost:8000`.
- Use `10.0.2.2` instead of `localhost` when running on Android emulators.
- **`dynatrace.config.yaml`** is gitignored — copy from `dynatrace.config.yaml.example` and populate with your Dynatrace Application ID and beacon URL before building.
- State management: `provider` package with a single `ChatProvider` (`ChangeNotifier`).
- Session ID generated once per app launch with `const Uuid().v4()`.
- All HTTP calls go through `Dynatrace().createHttpClient()` for automatic RUM tracing.

---

## Running Locally

```bash
# Backend (terminal 1)
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then fill in NVIDIA_API_KEY (Dynatrace vars optional)
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

# Load generator (terminal 4, optional)
cd load_gen
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then edit if needed
python load_gen.py
```

---

## Key Conventions

- All backend modules use `python-dotenv` (`load_dotenv()`) — `.env` must be in `backend/`.
- `load_gen/load_gen.py` also calls `load_dotenv()` — `.env` must be in `load_gen/`.
- Frontend CSS uses **CSS Modules** (`.module.css`); no global CSS framework.
- The backend registers a single router with prefix `/api` (`routers/chat.py`).
- Traceloop SDK is initialised **before** FastAPI is imported in `main.py` so instrumentation wraps everything (skipped gracefully if Dynatrace vars are absent).
- `dynatrace.config.yaml` is gitignored; the `.example` file in the same directory is the template.
