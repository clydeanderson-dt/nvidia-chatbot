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

(Historical: chaos engineering → DevCycle feature flags migration completed;
see [`docs/chaos-devcycle-migration.md`](docs/chaos-devcycle-migration.md)
for the plan and gotchas — file will eventually be deleted.)

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
- **The active LLM model is resolved per session via the `llm-model`
  DevCycle flag** (see `backend/services/llm.py:_resolve_model`). Targeting
  key is the chat session ID, so a session sticks to one model across its
  chat reply, follow-up suggestions, and starter suggestions. If you add
  another LLM call path, pass `session_id` through and resolve via
  `_resolve_model(session_id)` — don't reintroduce a hardcoded `_MODEL`
  constant. Fallback default is `meta/llama-3.1-8b-instruct`.
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

### LLM model A/B test (`llm-model` flag)

The resolved model is also written to the `llm.model` span attribute on
`chat_response.workflow` spans. To compare latency by model variation:

```
fetch spans, from:now() - 1h
| filter dt.service.name == "nvidia-chatbot"
| filter span.name == "chat_response.workflow"
| filter isNotNull(llm.model)
| summarize {requests = count(), p95_ms = percentile(duration, 95) / 1000000},
            by:{llm.model}
| sort requests desc
```
