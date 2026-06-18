# NVIDIA Chatbot

A full-stack AI chatbot demo: a Python/FastAPI backend serving
`meta/llama-3.1-8b-instruct` via the NVIDIA NIM API (LangChain), two
client apps (React web, Flutter mobile/desktop), and an async load
generator. Instrumented end-to-end with OpenTelemetry → Dynatrace and
controlled via DevCycle feature flags for chaos engineering.

## Components

| Component | README | Description |
|---|---|---|
| **Backend** | [backend/README.md](backend/README.md) | FastAPI server — LLM inference, session management |
| **React frontend** | [frontend/README.md](frontend/README.md) | React 19 / Vite SPA |
| **Flutter frontend** | [flutter_frontend/README.md](flutter_frontend/README.md) | Flutter mobile/desktop app |
| **Load generator** | [load_gen/README.md](load_gen/README.md) | Async load generator |

## Setup, running, and deployment

See **[deploy/README.md](deploy/README.md)** — single guide for local
development, environment variables, and Ubuntu VM deployment.

## Architecture and deep dives

- **[docs/architecture.md](docs/architecture.md)** — system overview, request flow, design decisions
- **[docs/opentelemetry-instrumentation.md](docs/opentelemetry-instrumentation.md)** — telemetry deep dive
- **[docs/devcycle-openfeature.md](docs/devcycle-openfeature.md)** — feature flags + chaos engineering

For AI-agent-specific guidance (DQL tips, conventions), see
[AGENTS.md](AGENTS.md).
