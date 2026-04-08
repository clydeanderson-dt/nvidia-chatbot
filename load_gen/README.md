# Load Generator

Async Python load generator that simulates chat traffic against the backend. Runs continuously, sending randomised messages via `POST /api/chat` followed by `DELETE /api/chat/{session_id}`, and prints latency statistics. Exports OpenTelemetry traces to Dynatrace.

---

## Key files

| File | Role |
|---|---|
| `load_gen.py` | Async workers, request dispatcher, stats collection, periodic and final summary output |
| `requirements.txt` | Python dependencies |

---

## Environment variables

Configuration is read from environment variables first, then CLI flags, then built-in defaults.

| Variable | CLI flag | Default | Description |
|---|---|---|---|
| `LOAD_GEN_URL` | `--url` | `http://localhost:8000` | Backend base URL |
| `LOAD_GEN_CONCURRENCY` | `--concurrency` | `5` | Worker count (constant-concurrency mode) or max-concurrency cap (fixed-rate mode) |
| `LOAD_GEN_RATE` | `--rate` | *(unset)* | Target req/s; if set, switches to fixed-rate mode |
| `LOAD_GEN_PROVIDER` | `--provider` | `nim_api` | LLM provider sent to the backend (`nim_api` or `self_hosted`) |
| `DYNATRACE_OTLP_ENDPOINT` | — | *(unset)* | `https://{environmentId}.live.dynatrace.com` — telemetry disabled if absent |
| `DYNATRACE_API_TOKEN` | — | *(unset)* | Dynatrace API token with `openTelemetryTrace.ingest` scope |

---

## CLI reference

```
python load_gen.py [OPTIONS]
```

| Flag | Description |
|---|---|
| `--url URL` | Backend base URL |
| `--concurrency N` | Worker count |
| `--rate FLOAT` | Target req/s; enables fixed-rate mode |
| `--provider {nim_api,self_hosted}` | LLM provider |
| `--requests N` | Stop after N total requests *(mutually exclusive with `--duration`)* |
| `--duration SECONDS` | Stop after N seconds *(mutually exclusive with `--requests`)* |

---

## Operating modes

### Constant-concurrency (default)

Spawns `--concurrency` async workers that each loop continuously — sending a request, waiting for the response, then immediately sending the next. Throughput is limited only by backend latency. Use this for stress testing.

```bash
python load_gen.py --concurrency 10
```

### Fixed-rate

Dispatches exactly `--rate` requests per second, up to the `--concurrency` cap. Produces a smoother, more predictable load pattern. Use this for sustained load or baseline measurement.

```bash
python load_gen.py --rate 10 --concurrency 5
```

---

## Running

Install dependencies, then run the load generator from the `load_gen/` directory:

```bash
cd load_gen
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Common examples

```bash
# Default: 5 concurrent workers, runs indefinitely
python load_gen.py

# Stress test: 50 workers against a remote backend
python load_gen.py --concurrency 50 --url http://192.168.1.10:8000

# Sustained load: 20 req/s, max 10 in-flight, stop after 5 minutes
python load_gen.py --rate 20 --concurrency 10 --duration 300

# Smoke test: send 20 requests and exit
python load_gen.py --requests 20

# Self-hosted NIM provider
python load_gen.py --provider self_hosted

# With Dynatrace telemetry
DYNATRACE_OTLP_ENDPOINT=https://abc123.live.dynatrace.com \
DYNATRACE_API_TOKEN=dt0a01.XXXX \
python load_gen.py --rate 5 --concurrency 10
```

Stop the generator at any time with `Ctrl+C` or `SIGTERM`. In-flight requests are cancelled immediately and a final summary is printed.

---

## Output

**Periodic status line** (printed every 30 seconds):

```
[+  120s] sent=1234   ok=1200   err=34  p50=0.45s  p95=2.10s  p99=3.50s  req/s=10.28
```

**Final summary** (printed on exit):

```
=== Load Generator — Final Summary ===
  Duration      : 300.5s
  Total requests: 3000
  Successes     : 2950
  Failures      : 50
  Avg req/s     : 9.98
  p50 latency   : 0.450s
  p95 latency   : 2.100s
  p99 latency   : 3.500s
```

The summary is formatted as a `rich` table when the package is available, and falls back to plain text otherwise.

---

## Telemetry

When both `DYNATRACE_OTLP_ENDPOINT` and `DYNATRACE_API_TOKEN` are set, traces are exported to Dynatrace via OTLP/HTTP. If either variable is absent, a warning is printed and the generator continues without exporting.

`HTTPXClientInstrumentor` auto-instruments all outbound HTTP calls. Each request also creates a manual `load_gen.request` span with the following attributes:

| Attribute | Value |
|---|---|
| `session.id` | UUID of the request |
| `llm.provider` | `nim_api` or `self_hosted` |
| `http.status_code` | HTTP response code |
| `load_gen.success` | `true` / `false` |
| `load_gen.latency_s` | End-to-end latency in seconds |

---

## Developer notes

- Each request creates a **fresh session UUID** and deletes the session after the response. No persistent history is accumulated.
- Latency measurements cover the full round-trip including LLM inference and suggestion generation on the backend.
- The request corpus contains 20 diverse questions (ML, programming, general knowledge, DevOps) to produce varied traces.
- The `DELETE` cleanup call is best-effort — failures are silently ignored and do not affect stats.
