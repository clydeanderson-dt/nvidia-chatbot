# NVIDIA Chatbot Architecture

This document explains the end-to-end architecture of the NVIDIA Chatbot
application — what each piece does, how requests flow, and why the boundaries
are drawn where they are.

- **LLM**: [NVIDIA NIM](https://www.nvidia.com/en-us/ai/) serving
  `meta/llama-3.1-8b-instruct` (managed API or self-hosted)
- **Backend**: Python / FastAPI (`backend/`)
- **Frontends**: React/Vite web app (`frontend/`) and Flutter mobile/desktop
  app (`flutter_frontend/`) — both consume the same HTTP API
- **Observability**: OpenTelemetry → Dynatrace (traces, logs, RUM)
- **Feature flags**: DevCycle via OpenFeature — see
  [`devcycle-openfeature.md`](devcycle-openfeature.md)
- **Load**: Async Python generator (`load_gen/`) for demo/benchmark traffic

---

## Why this architecture

| Concern | Choice |
|---|---|
| LLM provider portability | LangChain `ChatNVIDIA` with both managed and self-hosted clients pre-registered |
| Multiple frontends, one API | Stateless HTTP backend; session ID generated client-side |
| Conversation memory without a DB | In-memory `dict[session_id → ChatMessageHistory]` (intentionally ephemeral) |
| Vendor-neutral observability | OpenTelemetry SDK + Traceloop GenAI conventions → OTLP/HTTP to Dynatrace |
| Vendor-neutral chaos control | OpenFeature interface, DevCycle provider (local-bucketing) |
| Optional integrations | Telemetry, feature flags, and self-hosted NIM all start *silently disabled* if env vars are absent — the server still runs |
| Frontend safety for chaos | Frontends are read-only consumers of `/api/chaos/status`; only DevCycle mutates state |

---

## Component map

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  React frontend  │    │ Flutter frontend │    │   load_gen.py    │
│  (Vite, :5173)   │    │ (Dart, all OSes) │    │  (asyncio loop)  │
└────────┬─────────┘    └────────┬─────────┘    └────────┬─────────┘
         │ HTTP /api/*           │ HTTP /api/*           │ HTTP /api/*
         │ Dynatrace RUM ───┐    │ Dynatrace RUM ───┐    │
         └───────────┬──────┼────┴───────────┬──────┼────┘
                     ▼      ▼                ▼      ▼
                ┌──────────────────────────────────────┐
                │   FastAPI backend  (uvicorn :8000)   │
                │  ┌────────────────────────────────┐  │
                │  │  routers/  chat · chaos · cfg  │  │
                │  ├────────────────────────────────┤  │
                │  │  services/                     │  │
                │  │   llm.py  (LangChain chain)    │  │
                │  │   chaos.py (fault injection)   │  │
                │  │   app_config.py                │  │
                │  │   feature_flags.py             │  │
                │  └────────────────────────────────┘  │
                │  OTel SDK + Traceloop instrumentation│
                └─────┬───────────────┬───────────┬────┘
                      │               │           │
                      ▼               ▼           ▼
              ┌──────────────┐ ┌────────────┐ ┌──────────────┐
              │  NVIDIA NIM  │ │  DevCycle  │ │  Dynatrace   │
              │  (LLM API)   │ │ (flag bkd) │ │ (OTLP + RUM) │
              └──────────────┘ └────────────┘ └──────────────┘
```

Backend never calls a database — sessions live in process memory and die
with the process. Frontends never call NVIDIA, DevCycle, or any third party
directly; they go through the backend.

---

## Request flow — `POST /api/chat`

```
client                 backend                       NVIDIA NIM
  │                       │                              │
  │── POST /api/chat ────▶│                              │
  │  {session_id,         │                              │
  │   message,            │                              │
  │   system_prompt?,     │                              │
  │   provider?}          │                              │
  │                       │── _check_http_chaos()        │
  │                       │   (HTTP 500/503/session err) │
  │                       │── chaos.check_pre_llm_chaos()│
  │                       │   (rate-limit, token-limit,  │
  │                       │    llm_error, llm_delay)     │
  │                       │── _build_chain(prompt,prov)  │
  │                       │── chain.ainvoke()  ─────────▶│
  │                       │                              │
  │                       │◀──────────── assistant text ─│
  │                       │── chaos.modify_llm_response  │
  │                       │   (empty / hallucination)    │
  │                       │── get_suggestions()  ───────▶│
  │                       │◀────── ["q1","q2","q3"]  ────│
  │◀── {reply,            │                              │
  │     suggestions} ─────│                              │
```

Every step is wrapped in OTel spans by Traceloop's LangChain instrumentation
plus the FastAPI instrumentor. Chaos decisions add `chaos.*` attributes to
the active span.

---

## Backend layout

```
backend/
  main.py                  — App bootstrap: OTel/Traceloop, FastAPI, CORS,
                             lifespan startup that initialises feature flags,
                             global exception handler for ChaosInjectedError
  routers/
    chat.py                — /api/health, /api/chat, /api/chat/starters,
                             DELETE /api/chat/{id}; HTTP-level chaos check
    chaos.py               — GET /api/chaos, /api/chaos/status, /presets
                             (read-only — DevCycle owns mutations)
    config.py              — GET/PATCH /api/config, POST /api/config/reset
  services/
    llm.py                 — LangChain ChatNVIDIA + session store + chains
    chaos.py               — Reads OpenFeature flags, injects faults
    app_config.py          — In-memory app config (system prompt, provider)
    feature_flags.py       — DevCycle init + OpenFeature provider registration
  models/schemas.py        — Pydantic request/response models
  requirements.txt         — Python deps
```

### Startup sequence (`main.py`)

1. **Load `.env`** from repo root (explicit path so it works regardless of
   `cwd`; systemd uses the same file via `EnvironmentFile=`).
2. **Initialise Traceloop** with the OTLP endpoint — *skipped* with a warning
   if `OTLP_ENDPOINT` is absent.
3. **Set up OTel `LoggerProvider`** sharing the resource (so logs carry
   `service.name`); bridge Python `logging` → OTel via `LoggingInstrumentor`.
4. **Register `_FixGenAiSystemProcessor`** that rewrites Traceloop's
   `gen_ai.system="Langchain"` → `"nvidia"` to match the OTel GenAI spec.
5. **Create FastAPI app** with a lifespan handler that calls
   `initialize_feature_flags()`; instrument with `FastAPIInstrumentor`.
6. **Register exception handler** mapping `ChaosInjectedError` subclasses to
   user-friendly HTTP status codes + messages.
7. **Apply CORS middleware** from `ALLOWED_ORIGINS` (default: localhost dev).
8. **Include three routers** (`chat`, `chaos`, `config`).

### LLM service (`services/llm.py`)

- Two `ChatNVIDIA` clients are constructed lazily at import time and stored
  in `_llms: dict[str, ChatNVIDIA]`:
  - `nim_api` — managed NVIDIA NIM endpoint, requires `NVIDIA_API_KEY`
  - `self_hosted` — points at `SELF_HOSTED_NIM_URL/v1` if set
- Either, both, or neither can be present; a missing provider raises a
  clean `RuntimeError` on use.
- `_build_chain(system_prompt, provider)` constructs a fresh
  `RunnableWithMessageHistory` per request — necessary because the system
  prompt is request-scoped, but the message history is keyed by
  `session_id` and persists across requests via `_get_session_history`.
- `_session_store: dict[str, ChatMessageHistory]` is the entire persistence
  layer. Lost on restart. Acceptable for a demo; would need Redis or a DB
  in production.
- `@workflow(name="chat_response")` and `@task(name="chat_suggestions")`
  from Traceloop make each call a named GenAI span.
- `get_suggestions` and `get_starter_suggestions` are **stateless** second
  LLM calls — they never touch the session store. JSON parse failures
  return `[]` so the chat is never broken by a malformed suggestion call.

### Chat router (`routers/chat.py`)

- `/api/chat` checks HTTP-level chaos *first* (so 500/503 can bypass the LLM
  entirely), then delegates to `services/llm.get_response` and
  `get_suggestions`. The response is `{reply, suggestions}`.
- `request.system_prompt` and `request.provider` are **optional** —
  if absent, the server falls back to `app_config.get_config()`. This lets
  the React/Flutter frontends omit them entirely and rely on backend config.
- `/api/chat/starters` is the same pattern for opening suggestions.
- `DELETE /api/chat/{session_id}` evicts the session from the in-memory store.
- `get_chaos_error_message()` is exported and reused by the global
  exception handler in `main.py`.

### Config service (`services/app_config.py` + `routers/config.py`)

- A single `AppConfig` instance (system prompt + provider) is held in
  module-level state. Mutations go through `update_config()` /
  `reset_config()`. No persistence — restart resets to defaults.
- The frontends read this on mount and after every change so the UI matches
  whatever the server is currently using as fallback.

### Chaos service

See [`devcycle-openfeature.md`](devcycle-openfeature.md) for the full design.
In one sentence: `services/chaos.py` reads 15 flags (delays, error rates,
toggles) from OpenFeature on every request and exposes helpers
(`check_pre_llm_chaos`, `inject_delay`, `modify_llm_response`,
`should_inject`) that the chat path uses to add latency, raise typed
`ChaosInjectedError`s, or rewrite responses.

---

## Frontends

Both frontends implement the same two-screen app — chat + config — and
consume the same HTTP API. They differ only in framework idioms.

### React (`frontend/src/`)

```
App.jsx                        — Router: / → ChatPage, /config → ConfigPage
main.jsx                       — Wraps App in BrowserRouter + ConfigProvider
context/ConfigContext.jsx      — Global app config + chaos status; polls
                                 /api/chaos/status every 5s + on tab focus
hooks/useChat.js               — Messages, sessionId (crypto.randomUUID()),
                                 suggestions; calls /api/chat
pages/ChatPage.jsx             — Header, chaos banner, ChatWindow, chips,
                                 input bar
pages/ConfigPage.jsx           — Edit app config; read-only chaos display
                                 with DevCycle dashboard link
components/                    — ChatWindow, MessageBubble (markdown for
                                 assistant), InputBar, SuggestionChips
```

- Vite dev server proxies `/api` → `http://localhost:8000`.
- `useChat` reads `appConfig` from context — it does **not** locally manage
  system prompt or provider; the request body omits them and lets the
  server use its own config.
- Suggestion chips clear immediately when the user sends a new message.
- Dynatrace RUM is loaded via the standard JS agent.

### Flutter (`flutter_frontend/lib/`)

```
main.dart                       — Starts Dynatrace, builds MaterialApp
config.dart                     — baseUrl from --dart-define=BASE_URL=...
                                  (default http://localhost:8000)
providers/
  chat_provider.dart            — ChangeNotifier: messages, sessionId, chips
  config_provider.dart          — ChangeNotifier: app config + chaos status,
                                  polls every 5s, re-fetches on app resume
services/api_service.dart       — HTTP client built from
                                  Dynatrace().createHttpClient() so every
                                  request is auto-instrumented for RUM
screens/                        — chat_screen.dart, config_screen.dart
widgets/                        — ChatWindow, InputBar, MessageBubble,
                                  SuggestionChips, ChaosBanner,
                                  ChaosPresetButtons + read-only chaos
                                  detail sections
models/                         — chat_message, chat_request/response,
                                  starter_request/response, app_config,
                                  chaos_config
```

- State management: `provider` package — same mental model as React Context.
- `dynatrace.config.yaml` (gitignored) holds the Application ID and beacon
  URL. Copy from `dynatrace.config.yaml.example` before building.
- Android emulator note: use `--dart-define=BASE_URL=http://10.0.2.2:8000`
  instead of `localhost`.

Both frontends treat chaos as **observe-only** — DevCycle (driven by a
GitHub Actions workflow) is the only place chaos can be changed.

---

## Observability pipeline

```
Backend code  ──► Traceloop SDK (LangChain instrumentation)
              ──► FastAPIInstrumentor                ┐
              ──► LoggingInstrumentor                ├──► OTel SDK
              ──► _FixGenAiSystemProcessor           │     (resource = service.name)
                                                     ▼
                                          OTLP/HTTP exporter
                                                     │
                                                     ▼
                          Dynatrace tenant (traces + logs)

React frontend  ─► Dynatrace JS RUM agent        ─►  Dynatrace (user.events,
Flutter frontend ─► dynatrace_flutter_plugin     ─►  user.sessions)
```

Key points:

- **One service name.** `_APP_NAME = "nvidia-chatbot"` flows through the
  shared `Resource` so spans *and* logs land under the same service in
  Dynatrace (no `unknown_service`).
- **GenAI conventions are corrected on egress.** Traceloop's LangChain
  instrumentation sets `gen_ai.system="Langchain"`; a custom
  `SpanProcessor` overrides it to `"nvidia"` on `on_end()` so dashboards
  filtering by provider work.
- **Trace ID injection.** `LoggingInstrumentor(set_logging_format=True)`
  puts `otelTraceID`/`otelSpanID` into every Python log record, then
  forces root logger back to `INFO` to avoid debug flood.
- **Frontend RUM** runs independently and correlates with backend traces
  via the standard W3C `traceparent` headers Dynatrace emits.
- **Everything is optional.** Missing `OTLP_ENDPOINT` → no exporters
  registered, app still runs. Missing Dynatrace config in Flutter → fall
  back to bare HTTP client.

See `docs/opentelemetry-instrumentation.md` for the deep dive on
instrumentation choices.

---

## Configuration & secrets

All runtime config is environment-driven (`backend/.env`, loaded explicitly
from the repo root by `main.py` and `services/llm.py`):

| Variable | Required | Used by |
|---|---|---|
| `NVIDIA_API_KEY` | One of these two | `services/llm.py` (nim_api client) |
| `SELF_HOSTED_NIM_URL` | One of these two | `services/llm.py` (self_hosted client) |
| `OTLP_ENDPOINT` | No | `main.py` Traceloop + log exporter |
| `DEVCYCLE_SERVER_SDK_KEY` | No | `services/feature_flags.py` |
| `ALLOWED_ORIGINS` | No | CORS middleware |

`load_gen/.env` mirrors the same pattern with `load_dotenv()` so the load
generator runs independently. Flutter has its own
`flutter_frontend/dynatrace.config.yaml` for RUM credentials.

No secret is ever exposed to a frontend — they only see the backend URL.

---

## External control surfaces

- **DevCycle Management API** (via `.github/workflows/chaos.yml`) — the
  only thing that can change chaos state. PATCHes the production target of
  the `chaos-preset` feature; the backend's local-bucketing cache picks up
  the new variation within ~1s. Detailed in
  [`devcycle-openfeature.md`](devcycle-openfeature.md).
- **Backend `/api/config` PATCH** — changes the server-side fallback
  system prompt and provider. Lives only in memory.
- **Per-request overrides** — any `/api/chat` request can include its own
  `system_prompt` and `provider` to bypass server config.

---

## Running locally

See the README for setup commands. The four processes (backend, React,
Flutter, load_gen) are fully independent — start whichever subset you
need. The only hard dependency is that the frontends and load_gen need
the backend reachable at the URL they're configured for.

---

## File map

| Path | Role |
|---|---|
| `backend/main.py` | OTel + FastAPI bootstrap, lifespan, exception handler, CORS, routers |
| `backend/routers/chat.py` | Chat + starters + health + session delete; HTTP chaos gate |
| `backend/routers/chaos.py` | Read-only chaos status endpoints |
| `backend/routers/config.py` | App config read/update/reset |
| `backend/services/llm.py` | LangChain `ChatNVIDIA` clients, session store, chain builder |
| `backend/services/chaos.py` | OpenFeature flag reads + fault injection helpers |
| `backend/services/app_config.py` | In-memory app config singleton |
| `backend/services/feature_flags.py` | DevCycle init, OpenFeature provider registration |
| `backend/models/schemas.py` | Pydantic models (`ChatRequest`, `AppConfig`, `ChaosConfig`, …) |
| `frontend/src/context/ConfigContext.jsx` | App + chaos config, 5s polling |
| `frontend/src/hooks/useChat.js` | Messages, session ID, suggestions |
| `frontend/src/pages/*.jsx` | Chat and config pages |
| `flutter_frontend/lib/providers/*.dart` | ChatProvider, ConfigProvider |
| `flutter_frontend/lib/services/api_service.dart` | Dynatrace-instrumented HTTP client |
| `flutter_frontend/lib/screens/*.dart` | Chat and config screens |
| `load_gen/load_gen.py` | Async traffic generator |
| `docs/devcycle-openfeature.md` | Feature-flag architecture |
| `docs/opentelemetry-instrumentation.md` | Telemetry deep dive |
| `docs/chaos-devcycle-migration.md` | Historical migration plan |
