# NVIDIA Chatbot Architecture

This document explains the end-to-end architecture of the NVIDIA Chatbot
application — what each piece does, how requests flow, and why the boundaries
are drawn where they are.

- **LLM**: [NVIDIA NIM](https://www.nvidia.com/en-us/ai/) serving
  `meta/llama-3.1-8b-instruct` by default; chat replies and suggestions are
  resolved independently per session via the `llm-model-chat` and
  `llm-model-suggestions` DevCycle flags (managed API or self-hosted)
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
   if `OTLP_ENDPOINT` is absent. Telemetry setup details (the
   `_FixGenAiSystemProcessor`, the log pipeline, `LoggingInstrumentor`) are
   documented in [`opentelemetry-instrumentation.md`](opentelemetry-instrumentation.md).
3. **Create FastAPI app** with a lifespan handler that calls
   `initialize_feature_flags()`; instrument with `FastAPIInstrumentor`.
4. **Register exception handler** mapping `ChaosInjectedError` subclasses to
   user-friendly HTTP status codes + messages.
5. **Apply CORS middleware** from `ALLOWED_ORIGINS` (default: localhost dev).
6. **Include three routers** (`chat`, `chaos`, `config`).

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

- Reads the optional `X-Client-Type` request header (`web` / `mobile` /
  `load-gen`; anything else → `unknown`) via `_normalise_client_type` and
  sets it as the `client.type` span attribute. The value is also threaded
  into `services/llm` so DevCycle can segment traffic by caller.
- `/api/chat` checks HTTP-level chaos *first* (so 500/503 can bypass the LLM
  entirely), then delegates to `services/llm.get_response` and
  `get_suggestions`. The response includes `model` and `suggestions_model`
  resolved per session from the `llm-model-*` DevCycle flags.
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
consume the same HTTP API. They differ only in framework idioms. Component
file maps live in each frontend's README:

- React: [`frontend/README.md`](../frontend/README.md)
- Flutter: [`flutter_frontend/README.md`](../flutter_frontend/README.md)

Key shared behaviours:

- **Routing** — both expose `/` (chat) and `/config` (settings).
- **Session ID** — generated client-side (React: per browser tab via
  `crypto.randomUUID()`; Flutter: per app launch via `const Uuid().v4()`).
- **Client identification** — every chat request sends an `X-Client-Type`
  header (React: `web`, Flutter: `mobile`, load_gen: `load-gen`). The
  backend uses it as the `client.type` span attribute and as a DevCycle
  audience attribute for the `llm-model-*` flags. If you add a new client,
  send this header so audience targeting keeps working.
- **System prompt and provider** — managed via `PATCH /api/config`; the
  chat hook reads them from context and does **not** send them in the
  request body, so the server uses its stored config as the source of truth.
- **Suggestion chips** — clear immediately when the user sends a new message.
- **Chaos** — both poll `/api/chaos/status` every 5s and treat the result as
  **observe-only** — DevCycle (driven by `.github/workflows/chaos.yml`) is
  the only place chaos can be changed.
- **RUM** — React uses the standard Dynatrace JS agent; Flutter uses
  `dynatrace_flutter_plugin` + `Dynatrace().createHttpClient()` so every
  request is auto-instrumented.

Flutter-specific gotcha: Android emulator needs
`--dart-define=BASE_URL=http://10.0.2.2:8000` instead of `localhost`.

---

## Observability pipeline

All four deployables ship telemetry to the same Dynatrace tenant: backend
and load_gen via OTLP/HTTP (sharing a `traceparent` so load-gen → backend →
NVIDIA appears as one connected trace), React via the Dynatrace JS RUM
agent, and Flutter via `dynatrace_flutter_plugin`. Telemetry is
**optional** — every OTel branch is guarded; missing `OTLP_ENDPOINT` only
logs a warning.

See **[`opentelemetry-instrumentation.md`](opentelemetry-instrumentation.md)**
for the full design (init order, `_FixGenAiSystemProcessor`, log bridging,
the end-to-end trace diagram, RUM specifics, and gotchas).

---

## Configuration & secrets

All runtime config is environment-driven via a **single `.env` at the repo
root**, shared by the backend and the load generator. Both call
`load_dotenv()` with an explicit path to `<repo-root>/.env` so they work
regardless of the current working directory; on the deployed VM, systemd
injects the same values via `EnvironmentFile=/opt/chatbot/.env`.

| Variable | Required | Used by |
|---|---|---|
| `NVIDIA_API_KEY` | One of these two | `services/llm.py` (nim_api client) |
| `SELF_HOSTED_NIM_URL` | One of these two | `services/llm.py` (self_hosted client) |
| `OTLP_ENDPOINT` | No | `main.py` Traceloop + log exporter; `load_gen.py` |
| `DEVCYCLE_SERVER_SDK_KEY` | No | `services/feature_flags.py` (chaos + `llm-model-*` flags) |
| `ALLOWED_ORIGINS` | No | CORS middleware |
| `LOAD_GEN_*` | No | `load_gen/load_gen.py` (url, concurrency, rate, provider) |
| `VITE_DYNATRACE_RUM_URL` | No | React build (`frontend/index.html`) |

The React build inlines `VITE_*` vars at build time. Flutter has its own
`flutter_frontend/dynatrace.config.yaml` for RUM credentials (gitignored;
copy from `.example`). See [`deploy/README.md`](../deploy/README.md) for the
canonical variable list.

No secret is ever exposed to a frontend — they only see the backend URL.

---

## External control surfaces

- **DevCycle Management API** (via `.github/workflows/chaos.yml`) — the
  only thing that can change chaos state, and the source of truth for the
  `llm-model-chat` / `llm-model-suggestions` A/B distributions. See
  [`devcycle-openfeature.md`](devcycle-openfeature.md) for the OAuth flow,
  PATCH payload, propagation details, and audience targeting (by
  `clientType`).
- **Backend `/api/config` PATCH** — changes the server-side fallback
  system prompt and provider. Lives only in memory.
- **Per-request overrides** — any `/api/chat` request can include its own
  `system_prompt` and `provider` to bypass server config. The
  `X-Client-Type` header on every chat request feeds DevCycle audience
  targeting; values outside `{web, mobile, load-gen}` normalise to
  `unknown`.

---

## Running locally

See the README for setup commands. The four processes (backend, React,
Flutter, load_gen) are fully independent — start whichever subset you
need. The only hard dependency is that the frontends and load_gen need
the backend reachable at the URL they're configured for.
