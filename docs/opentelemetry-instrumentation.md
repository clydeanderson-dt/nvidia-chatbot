# OpenTelemetry Instrumentation in the NVIDIA Chatbot

This document explains how observability is wired up across the four
deployables of this repo and how telemetry reaches Dynatrace.

- **Backend** (`backend/`): Traceloop SDK + native OTel — traces, logs, and
  GenAI semantic-convention spans for LangChain / NVIDIA NIM calls.
- **Load generator** (`load_gen/`): native OTel — distributed traces that
  link to the backend via injected `traceparent` headers.
- **React frontend** (`frontend/`): Dynatrace agentless RUM JavaScript tag.
- **Flutter frontend** (`flutter_frontend/`): Dynatrace Flutter plugin —
  native mobile/desktop RUM with auto-instrumented HTTP.

All four ship telemetry to the **same Dynatrace tenant**. Backend and
load-generator traces share a `traceparent` so a single load-gen request
becomes one connected trace across both services.

---

## Why this architecture

| Concern | Choice |
|---|---|
| Vendor-neutral trace/log SDK on the server | OpenTelemetry SDK + OTLP/HTTP exporter |
| GenAI-specific span attributes (model, tokens, prompts) | Traceloop SDK auto-instruments LangChain |
| Send Python `logging` records to Dynatrace | OTel `LoggerProvider` + `LoggingInstrumentor` |
| Server graceful start without telemetry config | All OTel init is guarded — missing `OTLP_ENDPOINT` only logs a warning |
| Web browser RUM with no app changes | Dynatrace agentless RUM script injected by Vite |
| Mobile RUM with auto HTTP instrumentation | `dynatrace_flutter_plugin` + `Dynatrace().createHttpClient()` |
| End-to-end trace from load-gen → backend → LLM | `OTLPSpanExporter` + `HTTPXClientInstrumentor` propagate `traceparent` |

---

## Environment variables (root `.env`)

A single repo-root `.env` is shared by the backend and the load generator
(both call `load_dotenv(Path(__file__).resolve().parents[1] / ".env")`).
The frontend reads its tag URL at Vite build time.

| Variable | Used by | Required | Notes |
|---|---|---|---|
| `OTLP_ENDPOINT` | backend, load_gen | No* | Base URL of the OTLP/HTTP collector (e.g. `http://localhost:4318`). If unset, all OTel init is **skipped with a warning** and the service still starts. |
| `VITE_DYNATRACE_RUM_URL` | React build | No | Dynatrace RUM JS tag URL. If unset, browser RUM is simply not loaded. |
| `dynatrace.config.yaml` | Flutter build | No | Per-platform Application ID + beacon URL. File is gitignored; copy from `dynatrace.config.yaml.example`. |

The backend appends `/v1/traces` and `/v1/logs` to `OTLP_ENDPOINT`, so the
value must be the collector **base URL with no trailing slash and no path**.

---

## End-to-end flow

```
┌──────────────┐     traceparent      ┌─────────────────────────┐
│  load_gen    │ ───────HTTPX───────▶ │  FastAPI /api/chat      │
│  (OTel SDK)  │                      │  (FastAPIInstrumentor)  │
└──────┬───────┘                      └────────────┬────────────┘
       │  spans                                    │ spans + logs
       │  /v1/traces                               │ /v1/traces, /v1/logs
       ▼                                           ▼
                  Dynatrace OTLP/HTTP (4318)
       ▲                                           ▲
       │                                           │
┌──────┴────────────┐                  ┌───────────┴──────────────┐
│  React frontend   │ ─ Dynatrace RUM ▶│  Dynatrace tenant        │
│  (JS tag in HTML) │                  │  (traces, logs, RUM,     │
└───────────────────┘                  │   sessions, GenAI spans) │
┌───────────────────┐                  │                          │
│  Flutter frontend │ ─ Dynatrace RUM ▶│                          │
│  (native plugin)  │                  └──────────────────────────┘
└───────────────────┘
```

Inside the backend, the trace tree for a single chat request is:

```
HTTP POST /api/chat                          (FastAPIInstrumentor)
└─ chat_response                             (Traceloop @workflow)
   ├─ chaos.check_pre_llm_chaos              (manual span attrs)
   ├─ ChatNVIDIA / langchain call            (Traceloop LangChain instr.)
   │     attrs: gen_ai.system=nvidia, model, prompts, completions, tokens
   └─ chat_suggestions                       (Traceloop @task)
         └─ ChatNVIDIA call                  (Traceloop LangChain instr.)
```

---

## Backend implementation

### 1. Dependencies — `backend/requirements.txt`

```
traceloop-sdk==0.52.6
opentelemetry-instrumentation-langchain==0.52.6
opentelemetry-exporter-otlp-proto-http==1.40.0
opentelemetry-instrumentation-fastapi==0.61b0
opentelemetry-instrumentation-logging==0.61b0
```

Traceloop bundles the OTel SDK + LangChain instrumentation. The remaining
packages add FastAPI auto-instrumentation, the OTLP/HTTP log exporter, and
the `logging` bridge.

### 2. Initialization order — `backend/main.py`

Order matters: Traceloop must initialize the `TracerProvider` **before**
FastAPI is imported, so its instrumentation hooks wrap the framework as it
loads. The log pipeline then reuses the same `Resource` so traces and logs
carry the same `service.name`.

```python
# 1. Load env first
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

# 2. Traceloop — sets the global TracerProvider, registers LangChain instr.
from traceloop.sdk import Traceloop
if _otlp_endpoint:
    Traceloop.init(app_name="nvidia-chatbot", api_endpoint=_otlp_endpoint)
else:
    logging.warning("OTLP_ENDPOINT is not set — Traceloop will not be initialised.")

# 3. Reuse Traceloop's Resource for the LoggerProvider so logs correlate
_tracer_provider = _otel_trace.get_tracer_provider()
_otel_resource = getattr(_tracer_provider, "resource", None)

# 4. Span processor to fix gen_ai.system (see Gotcha #1)
_tracer_provider.add_span_processor(_FixGenAiSystemProcessor())

# 5. OTel log pipeline → Dynatrace
if _otlp_endpoint:
    _log_exporter = OTLPLogExporter(endpoint=f"{_otlp_endpoint}/v1/logs")
    _logger_provider = LoggerProvider(resource=_otel_resource)
    _logger_provider.add_log_record_processor(BatchLogRecordProcessor(_log_exporter))
    set_logger_provider(_logger_provider)

# 6. Bridge stdlib logging → OTel; inject otelTraceID / otelSpanID into records
LoggingInstrumentor().instrument(set_logging_format=True)
logging.getLogger().setLevel(logging.INFO)  # set_logging_format=True flips it to DEBUG

# 7. Now safe to import FastAPI and instrument
from fastapi import FastAPI
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
app = FastAPI(...)
FastAPIInstrumentor.instrument_app(app)
```

Every branch that touches OTLP is guarded by `if _otlp_endpoint:` so the
server runs identically in a local dev environment without Dynatrace.

### 3. Fixing `gen_ai.system` — span processor

Traceloop's LangChain instrumentation sets `gen_ai.system="Langchain"`
(the framework name). The OTel GenAI semantic convention says this
attribute should identify the **AI provider** (`"nvidia"`, `"openai"`, …),
which is what Dynatrace's AI Observability views key off. A custom
`SpanProcessor.on_end` rewrites the attribute in place before export:

```python
class _FixGenAiSystemProcessor(_SpanProcessor):
    def on_end(self, span) -> None:
        attrs = getattr(span, "_attributes", None)
        if attrs is not None and attrs.get("gen_ai.system") == "Langchain":
            attrs["gen_ai.system"] = "nvidia"
```

This is the **one place** to change when adding a non-NVIDIA provider.

### 4. Manual spans and attributes — `backend/services/llm.py`

The LLM service uses Traceloop's `@workflow` and `@task` decorators to give
the trace tree a human-readable shape, then adds custom span attributes for
the session and any chaos that was injected.

```python
from opentelemetry import trace as _otel_trace
from traceloop.sdk.decorators import task, workflow

@workflow(name="chat_response")
async def get_response(session_id, message, system_prompt, provider="nim_api"):
    span = _otel_trace.get_current_span()
    span.set_attribute("session.id", session_id)

    chaos_meta = await chaos.check_pre_llm_chaos()
    for k, v in chaos_meta.items():
        span.set_attribute(k, v)  # e.g. chaos.injected=true, chaos.llm_delay_ms=5000

    chain = _build_chain(system_prompt, provider)
    result = await chain.ainvoke(...)  # LangChain auto-instrumented by Traceloop
    return result.content

@task(name="chat_suggestions")
async def get_suggestions(...): ...

@task(name="chat_starter_suggestions")
async def get_starter_suggestions(...): ...
```

`routers/chat.py` similarly sets `session.id` and `chaos.type` on the
current FastAPI server span for chaos-injected HTTP errors.

### 5. Logs → traces correlation

`LoggingInstrumentor(set_logging_format=True)` does two things:

1. Adds an OTel handler so every `logging` record is also exported as an
   OTel `LogRecord` to `/v1/logs`.
2. Reformats the stdlib log format to inject `otelTraceID` and
   `otelSpanID` into every line, so terminal logs are correlatable too.

Because the `LoggerProvider` uses the same `Resource` as the
`TracerProvider`, Dynatrace shows the logs under the same
`service.name=nvidia-chatbot` as the spans and links them inside the
trace waterfall.

> ⚠ `set_logging_format=True` also resets the root level to `DEBUG`. We
> immediately force it back to `INFO` to prevent a log flood (especially
> from `httpx`, `urllib3`, and LangChain internals).

### 6. Pre-built spans you get for free

| Source | What it produces |
|---|---|
| `FastAPIInstrumentor.instrument_app(app)` | Server span per HTTP request with route, status, method, peer attrs |
| `opentelemetry-instrumentation-langchain` (via Traceloop) | One span per `Runnable` step, GenAI attributes on the LLM call |
| `Traceloop.init(...)` | Auto-instruments outbound HTTP from the LangChain client so `traceparent` is propagated to NVIDIA's API |
| `@workflow` / `@task` decorators | Named parent spans grouping the request's work |

---

## Load generator implementation — `load_gen/load_gen.py`

The load generator is a standalone process and so it owns its **own**
`TracerProvider`. The key requirements: same `OTLP_ENDPOINT` as the
backend, and `traceparent` injection on every request so traces span both
processes.

### Dependencies — `load_gen/requirements.txt`

```
httpx>=0.27.0
opentelemetry-sdk>=1.20.0
opentelemetry-exporter-otlp-proto-http>=1.20.0
opentelemetry-instrumentation-httpx>=0.41b0
```

### Setup

```python
def setup_telemetry() -> trace.Tracer:
    endpoint = os.environ.get("OTLP_ENDPOINT", "").rstrip("/")
    if not endpoint:
        return trace.get_tracer("load_gen")  # no-op tracer

    resource = Resource.create({"service.name": "chatbot-load-gen"})
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=f"{endpoint}/v1/traces")
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    # Auto-instrument all httpx calls: injects `traceparent` and creates
    # client spans that link to the backend's server spans.
    HTTPXClientInstrumentor().instrument()

    return trace.get_tracer("load_gen")
```

`service.name=chatbot-load-gen` is deliberately different from the
backend's `nvidia-chatbot` so the two services appear as distinct
Smartscape entities in Dynatrace while still sharing a single trace.

---

## React frontend — `frontend/index.html`

Browser RUM is purely **agentless**: a single `<script>` tag in the HTML
shell loads Dynatrace's instrumentation, which then captures page loads,
XHR/fetch calls, user actions, and JS errors automatically.

```html
<head>
  <!-- Dynatrace Real User Monitoring (RUM) -->
  <script type="text/javascript"
          src="%VITE_DYNATRACE_RUM_URL%"
          crossorigin="anonymous"></script>
  ...
</head>
```

Vite substitutes `%VITE_DYNATRACE_RUM_URL%` at build time from the
`VITE_DYNATRACE_RUM_URL` env var (set in the root `.env`). If the variable
is empty, the build still succeeds — the literal placeholder remains in the
HTML and the browser simply fails to load the script. In Dynatrace, the
React app appears with the application name configured on the tag
(`AI_Chatbot`).

```dql
fetch user.sessions
| filter in(frontend.name, {"AI_Chatbot"})
```

---

## Flutter frontend — `flutter_frontend/`

Native mobile/desktop RUM is provided by the `dynatrace_flutter_plugin`
package, which wires into the Android and iOS Dynatrace agents.

### 1. Build-time config — `flutter_frontend/dynatrace.config.yaml`

A gitignored YAML (copy from `dynatrace.config.yaml.example`) supplies the
Application ID and beacon URL for **each platform**:

```yaml
android:
  config: "dynatrace { configurations { defaultConfig { autoStart {
            applicationId 'YOUR_DYNATRACE_APPLICATION_ID'
            beaconUrl   'YOUR_DYNATRACE_BEACON_URL'
          } ... } } }"
ios:
  config: "<key>DTXApplicationID</key><string>YOUR_DYNATRACE_APPLICATION_ID</string>
           <key>DTXBeaconURL</key><string>YOUR_DYNATRACE_BEACON_URL</string> ..."
```

The plugin's build hooks read this file during `flutter build` and inject
the agent into the native projects.

### 2. App startup — `flutter_frontend/lib/main.dart`

```dart
import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';

void main() => Dynatrace().start(MainApp());

class MainApp extends StatelessWidget {
  ...
  navigatorObservers: [
    DynatraceNavigationObserver(),   // captures route changes as RUM views
    routeObserver,
  ],
  ...
}
```

`Dynatrace().start(...)` boots the native agent before the first frame.
The navigation observer records every `Navigator.push/pop` as a view
change so screen flows show up in Dynatrace session replays.

### 3. Auto-instrumented HTTP — `flutter_frontend/lib/services/api_service.dart`

```dart
final http.Client _client = Dynatrace().createHttpClient();
```

This drop-in replacement for `http.Client` adds outbound request spans and
injects `traceparent` headers, so a tap in the Flutter app links to the
backend's FastAPI span in Dynatrace.

### 4. User-action attribution

Tappable widgets are wrapped in `UserInteractionWidget` (chips, send button,
chaos banner, config tiles) so RUM associates user clicks with the
resulting HTTP calls. The classic `Dynatrace().enterAction(...)` API is
intentionally commented out — Grail-based RUM does not require it.

```dart
return UserInteractionWidget(
  child: ElevatedButton(onPressed: ..., child: ...),
);
```

In Dynatrace the app appears as `AI_Chatbot_Flutter`:

```dql
fetch user.events
| filter frontend.name == "AI_Chatbot_Flutter"
```

---

## Querying telemetry in Dynatrace

### Backend traces

```dql
fetch spans
| filter dt.service.name == "nvidia-chatbot"
```

GenAI-specific spans (filter for the LLM call itself):

```dql
fetch spans
| filter dt.service.name == "nvidia-chatbot"
| filter gen_ai.system == "nvidia"
```

### Backend logs

```dql
fetch logs
| filter service.name == "nvidia-chatbot"
```

### Cross-service load-gen → backend trace

```dql
fetch spans
| filter dt.service.name in {"chatbot-load-gen", "nvidia-chatbot"}
| sort timestamp asc
```

### Frontend RUM

```dql
fetch user.events
| filter frontend.name in {"AI_Chatbot", "AI_Chatbot_Flutter"}
```

---

## Gotchas (read before changing OTel code)

1. **`gen_ai.system` must be the provider, not the framework.** Traceloop's
   LangChain instrumentation hard-codes `"Langchain"`. The
   `_FixGenAiSystemProcessor` in `backend/main.py` rewrites it to
   `"nvidia"` on `on_end`. If you add a non-NVIDIA provider, generalize
   the processor to map `provider → gen_ai.system`.

2. **Import order in `backend/main.py` is load-bearing.**
   `Traceloop.init(...)` must run before FastAPI is imported so its
   instrumentation hooks see the framework as it loads. Moving the
   `from fastapi import FastAPI` import above Traceloop silently drops
   request spans.

3. **`OTLP_ENDPOINT` is a base URL.** The backend appends `/v1/traces` and
   `/v1/logs`; the load-gen appends `/v1/traces`. A trailing slash or a
   pre-baked path will produce `//v1/traces` and 404s at the collector.

4. **`LoggingInstrumentor(set_logging_format=True)` flips root level to
   DEBUG.** We immediately force it back to `INFO`. If you remove that
   line, `httpx`, `urllib3`, and LangChain will flood Dynatrace logs.

5. **Missing telemetry config is non-fatal by design.** Every OTel branch
   is wrapped in `if _otlp_endpoint:`. The server still starts and serves
   `/api/chat` — Dynatrace just receives nothing. Don't add hard
   assertions on telemetry init.

6. **Trace context propagation is automatic only for instrumented HTTP
   clients.** The backend's outbound call to NVIDIA propagates because
   Traceloop instruments the LangChain HTTP client. The load-gen's
   `httpx.AsyncClient` propagates because `HTTPXClientInstrumentor` is
   called. A bare `urllib.request` call would break the trace.

7. **`service.name` is set by Traceloop and reused by the
   `LoggerProvider`.** Don't create a separate `Resource` for logs — that
   produces `unknown_service` in Dynatrace and breaks the
   logs-on-trace-waterfall view.

8. **Frontend RUM is build-time, not runtime.** The React build embeds
   `VITE_DYNATRACE_RUM_URL` into the HTML. If you change tenants, rebuild
   the frontend (`npm run build`) — restarting the backend is not enough.
   Flutter is the same: regenerate native projects after editing
   `dynatrace.config.yaml`.

---

## File map

| File | Role |
|---|---|
| `backend/main.py` | Traceloop init, OTel log pipeline, `_FixGenAiSystemProcessor`, `FastAPIInstrumentor` |
| `backend/services/llm.py` | `@workflow` / `@task` decorators, manual `session.id` and `chaos.*` span attrs |
| `backend/routers/chat.py` | Manual `chaos.injected` / `chaos.type` attrs on chaos paths |
| `backend/requirements.txt` | Traceloop + OTel package pins |
| `load_gen/load_gen.py` | Standalone `TracerProvider`, `OTLPSpanExporter`, `HTTPXClientInstrumentor` |
| `load_gen/requirements.txt` | OTel SDK + httpx instrumentation pins |
| `frontend/index.html` | `<script src="%VITE_DYNATRACE_RUM_URL%">` agentless RUM tag |
| `frontend/.env.example` | Documents `VITE_DYNATRACE_RUM_URL` |
| `flutter_frontend/lib/main.dart` | `Dynatrace().start(...)` + `DynatraceNavigationObserver` |
| `flutter_frontend/lib/services/api_service.dart` | `Dynatrace().createHttpClient()` — auto-instrumented HTTP |
| `flutter_frontend/lib/widgets/*.dart`, `screens/*.dart` | `UserInteractionWidget` wrappers for RUM action attribution |
| `flutter_frontend/dynatrace.config.yaml.example` | Per-platform Application ID + beacon URL template |
| `.env.example` | Documents `OTLP_ENDPOINT` and `VITE_DYNATRACE_RUM_URL` |
