# AGENTS.md — Agent Guidance

Guidance for AI agents working in this repo. For the application itself,
read the canonical docs first:

- [`README.md`](README.md) — entry point + link map
- [`deploy/README.md`](deploy/README.md) — env vars, setup, deploy
- [`docs/architecture.md`](docs/architecture.md) — system overview, request flow
- [`docs/opentelemetry-instrumentation.md`](docs/opentelemetry-instrumentation.md) — telemetry
- [`docs/devcycle-openfeature.md`](docs/devcycle-openfeature.md) — feature flags + chaos

Per-component detail lives in `backend/README.md`, `frontend/README.md`,
`flutter_frontend/README.md`, and `load_gen/README.md`.

---

## Active Migrations

_None in progress._

---

## Key Conventions

- **Single `.env` at the repo root** is the source of truth. `backend/main.py`,
  `backend/services/llm.py`, and `load_gen/load_gen.py` all `load_dotenv()`
  with an explicit path to that file (via `Path(__file__).resolve().parents[N]`),
  so they work regardless of CWD. On the VM, systemd injects the same vars
  via `EnvironmentFile=/opt/chatbot/.env`, making `load_dotenv()` a no-op there.
- **Telemetry is optional.** Every OTel branch is guarded by
  `if _otlp_endpoint:`. Missing `OTLP_ENDPOINT` only logs a warning; the app
  still runs. Don't add hard assertions on telemetry init.
- **Chaos is read-only from the backend.** Only DevCycle (driven by
  `.github/workflows/chaos.yml`) can mutate chaos state. Don't reintroduce
  `PATCH /api/chaos`, `POST /api/chaos/reset`, or
  `POST /api/chaos/preset/{name}` — they were intentionally removed.
- **LLM models are resolved per session via two DevCycle flags**:
  `llm-model-chat` for the main reply (`get_response`) and
  `llm-model-suggestions` for follow-up + starter suggestions
  (`get_suggestions`, `get_starter_suggestions`). See
  `backend/services/llm.py:resolve_model` and `resolve_suggestions_model`.
  Targeting key is the chat session ID, so a session sticks to one model
  per call type. Both resolvers also accept an optional `client_type` arg
  that is forwarded to DevCycle as the `clientType` custom attribute
  (`web` / `mobile` / `load-gen` / `unknown`), so audiences in DevCycle can
  segment traffic by caller. If you add another LLM call path, pass
  `session_id` and `client_type` through and resolve via the appropriate
  helper — don't reintroduce a hardcoded `_MODEL` constant. Fallback
  defaults are `meta/llama-3.1-8b-instruct` (chat) and
  `meta/llama-3.2-3b-instruct` (suggestions).
- **All chat clients send an `X-Client-Type` header** identifying the caller:
  React frontend → `web`, Flutter frontend → `mobile`,
  `load_gen/load_gen.py` → `load-gen`. The backend reads it in
  `backend/routers/chat.py` via `_normalise_client_type` (whitelist; anything
  else → `unknown`), sets it as the `client.type` span attribute, and threads
  it into DevCycle as described above. If you add a new client, send this
  header so audience targeting and span filters keep working.
- **Traceloop init must come before FastAPI is imported in `main.py`.**
  Order is load-bearing; see `docs/opentelemetry-instrumentation.md` gotcha #2.
- **CSS Modules only** in the React frontend (`.module.css`). No global CSS framework.
- **`dynatrace.config.yaml`** is gitignored; the `.example` file in the same
  directory is the template.

---

## Observability — DQL Tips for Dynatrace

This application is monitored with Dynatrace. Interact with it via the
Dynatrace MCP or the `dtctl` CLI tool.

Before running a specific DQL query with filters / summaries, you MUST first
run a generic query to discover available fields:

```
fetch spans|logs|events
| limit 10
```

### Traces / Spans (backend)

```
fetch spans
| filter dt.service.name == "nvidia-chatbot"
```

GenAI-specific spans:

```
fetch spans
| filter dt.service.name == "nvidia-chatbot"
| filter gen_ai.system == "nvidia"
```

### Logs (backend)

```
fetch logs
| filter service.name == "nvidia-chatbot"
```

### Cross-service trace (load_gen → backend)

```
fetch spans
| filter dt.service.name in {"chatbot-load-gen", "nvidia-chatbot"}
| sort timestamp asc
```

### Real User Monitoring

React frontend:

```
fetch user.events
| filter frontend.name == "AI_Chatbot"
```

Flutter frontend:

```
fetch user.events
| filter frontend.name == "AI_Chatbot_Flutter"
```

Session counts:

```
fetch user.sessions
| filter in(frontend.name, {"AI_Chatbot", "AI_Chatbot_Flutter"})
| summarize {sessions = count()}, by:{frontend.name}
```

### Specifying the timeframe

```
fetch logs, from:now() - 30m
| filter service.name == "nvidia-chatbot"
```

### Feature flag evaluations

DevCycle flag evaluations are emitted as **span events** on the active parent
span via the OpenFeature OTel `TracingHook` (registered in
`backend/services/feature_flags.py`). They are not their own spans.

Dynatrace gotchas:
- The field is `span.events` (not `events` — querying `events` returns nothing).
- After `expand span.events`, event attributes live at the **top level** of the
  expanded record, keyed by their semconv name. The event name field is
  `span_event.name`.
- `span.id` is a UID — compare with `toUid("hex-string")`.

Example — count evaluations per flag/value:

```
fetch spans, from:now() - 15m
| filter dt.service.name == "nvidia-chatbot"
| expand span.events
| filter span.events[`span_event.name`] == "feature_flag.evaluation"
| fieldsAdd flag_key   = span.events[`feature_flag.key`],
            flag_value = span.events[`feature_flag.result.value`],
            flag_reason = span.events[`feature_flag.result.reason`]
| summarize evaluations = count(), by:{flag_key, flag_value, flag_reason}
| sort evaluations desc
```

### LLM model A/B test (`llm-model-chat` and `llm-model-suggestions` flags)

The resolved model is written to the `llm.model` span attribute on
`chat_response.workflow`, `chat_suggestions.task`, and
`chat_starter_suggestions.task` spans. To compare chat latency by model:

```
fetch spans, from:now() - 1h
| filter dt.service.name == "nvidia-chatbot"
| filter span.name == "chat_response.workflow"
| filter isNotNull(llm.model)
| summarize {requests = count(), p95_ms = percentile(duration, 95) / 1000000},
            by:{llm.model}
| sort requests desc
```

Swap `chat_response.workflow` for `chat_suggestions.task` or
`chat_starter_suggestions.task` to analyse the suggestions model split.

### Client type (`client.type` span attribute)

Every chat-router span carries `client.type` (`web` / `mobile` / `load-gen` /
`unknown`) sourced from the `X-Client-Type` request header. Use it to
separate real-user traffic from synthetic load_gen traffic, or to compare
web vs mobile.

Traffic mix by client:

```
fetch spans, from:now() - 1h
| filter dt.service.name == "nvidia-chatbot"
| filter span.name == "chat_response.workflow"
| summarize requests = count(), by:{client.type}
| sort requests desc
```

Latency comparison by model, excluding synthetic load:

```
fetch spans, from:now() - 1h
| filter dt.service.name == "nvidia-chatbot"
| filter span.name == "chat_response.workflow"
| filter client.type in {"web", "mobile"}
| filter isNotNull(llm.model)
| summarize {requests = count(), p95_ms = percentile(duration, 95) / 1000000},
            by:{llm.model}
| sort requests desc
```

Cross-tab of model × client (handy for confirming the DevCycle audiences
are routing traffic the way you expect):

```
fetch spans, from:now() - 1h
| filter dt.service.name == "nvidia-chatbot"
| filter span.name == "chat_response.workflow"
| filter isNotNull(llm.model)
| summarize requests = count(), by:{client.type, llm.model}
| sort requests desc
```
