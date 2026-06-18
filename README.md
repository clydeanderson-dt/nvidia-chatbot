# Running the AI Chatbot

## Prerequisites

- Python 3.11+
- Node.js 18+
- An [NVIDIA NIM API key](https://build.nvidia.com/)
- A Dynatrace SaaS environment with an OTLP ingest token *(required for telemetry; optional to run the app)*

---

## Components

| Component | README | Description |
|---|---|---|
| **Backend** | [backend/README.md](backend/README.md) | FastAPI server — LLM inference, session management, OpenTelemetry |
| **Frontend** | [frontend/README.md](frontend/README.md) | React/Vite SPA — chat UI, system prompt, provider selection |
| **Flutter Frontend** | [flutter_frontend/README.md](flutter_frontend/README.md) | Flutter mobile/desktop app — chat UI, Dynatrace RUM instrumentation |
| **Load generator** | [load_gen/README.md](load_gen/README.md) | Async load generator — stress testing, latency stats, Dynatrace export |

Each README covers environment variables, configuration, and how to run.

---

## Telemetry

The application instruments all components with observability telemetry, providing end-to-end visibility from load generation through backend processing to frontend user interactions.

### Backend (OpenTelemetry)

- **Traceloop SDK** auto-instruments FastAPI endpoints and LangChain chains, exporting traces and logs to Dynatrace via OTLP
- Captures request/response spans, LLM invocation details, and Python log records with trace correlation
- **Optional**: Backend starts without `OTLP_ENDPOINT` (telemetry skipped with a warning)

### React Frontend (Dynatrace RUM)

- **Dynatrace RUM JavaScript tag** injected into `index.html` via the `VITE_DYNATRACE_RUM_URL` environment variable at build time
- Captures page loads, user sessions, and frontend errors without manual instrumentation

### Flutter Frontend (Dynatrace RUM)

- **dynatrace_flutter_plugin** instruments HTTP calls via `Dynatrace().createHttpClient()` and tracks user interactions with `UserInteractionWidget`
- Requires `dynatrace.config.yaml` configuration (see `dynatrace.config.yaml.example`)

### Load Generator (OpenTelemetry)

- **OpenTelemetry SDK** creates manual spans per request with latency and success metrics, plus httpx auto-instrumentation
- Exports to Dynatrace OTLP endpoint; **enables distributed tracing** by injecting W3C `traceparent` headers that link load_gen → backend → LangChain → NVIDIA NIM spans
- **Optional**: Load generator runs without Dynatrace environment variables (telemetry skipped)

See [AGENTS.md](AGENTS.md) for detailed telemetry implementation and component READMEs for configuration instructions.

---

## Quick start (local development)

**Terminal 1 — backend:**

```bash
cp .env.example .env   # in the repo root; set NVIDIA_API_KEY at minimum
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
# → http://localhost:8000
```

**Terminal 2 — frontend:**

```bash
cd frontend
npm install
npm run dev
# → http://localhost:5173
```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| `NVIDIA_API_KEY is not set` error | Ensure `.env` exists at the repo root and contains a valid key |
| CORS errors in the browser | Verify `ALLOWED_ORIGINS` in `.env` matches the exact origin (including port) used by the browser |
| No traces/metrics/logs in Dynatrace | Confirm `OTLP_ENDPOINT` is set (base URL, no trailing slash, no path); check backend logs for the `OTLP_ENDPOINT is not set` warning; verify the Dynatrace token used in the URL has `openTelemetryTrace.ingest`, `metrics.ingest`, and `logs.ingest` scopes |