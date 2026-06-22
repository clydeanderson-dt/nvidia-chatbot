# Deployment & Local Development Guide

This guide covers two scenarios:

1. **[Running Locally](#running-locally)** — develop and test all components on your own machine
2. **[VM Deployment](#vm-deployment)** — deploy to a single Ubuntu 22.04 / 24.04 VM with nginx and systemd

---

## Running Locally

### Prerequisites

- Python 3.11+
- Node.js 20+
- Flutter SDK 3.x (only required for the Flutter frontend)
- An NVIDIA API key (`nvapi-…`) from [build.nvidia.com](https://build.nvidia.com)
- Dynatrace credentials (optional — backend starts with a warning if absent)

---

### 1 — Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Configuration lives in a single `.env` at the repo root, shared by the
# backend, the load generator, and the frontend build:
cp ../.env.example ../.env         # then edit ../.env with your credentials

uvicorn main:app --reload
# → API available at http://localhost:8000
# → Health check: curl http://localhost:8000/api/health
```

**Root `.env` variables** (see `.env.example` for full documentation):

| Variable | Required | Used by | Description |
|---|---|---|---|
| `NVIDIA_API_KEY` | **Yes** | backend | Your `nvapi-…` key |
| `DEVCYCLE_SERVER_SDK_KEY` | No | backend | DevCycle server SDK key (chaos engineering). Without it, chaos is disabled. |
| `OTLP_ENDPOINT` | No | backend, load_gen | OTel collector HTTP/protobuf endpoint (e.g. `http://localhost:4318`) |
| `ALLOWED_ORIGINS` | No | backend | Extra CORS origins (comma-separated, with protocol, no trailing slashes) |
| `SELF_HOSTED_NIM_URL` | No | backend | Base URL for a self-hosted NIM instance |
| `VITE_DYNATRACE_RUM_URL` | No | frontend build | Dynatrace RUM JS tag URL |
| `LOAD_GEN_URL` | No | load_gen | Backend base URL (default `http://localhost:8000`) |
| `LOAD_GEN_CONCURRENCY` | No | load_gen | Worker count (default `5`) |
| `LOAD_GEN_PROVIDER` | No | load_gen | `nim_api` or `self_hosted` (default `nim_api`) |
| `LOAD_GEN_RATE` | No | load_gen | Target req/s; unset = constant-concurrency mode |
| `SERVER_NAME` | No | setup.sh | nginx server_name on the VM (default: VM IP) |

> Optional Dynatrace/OTel variables can be left blank — the services start with a warning.

---

### 2 — React Frontend

```bash
cd frontend
npm install
npm run dev
# → UI available at http://localhost:5173 (proxies /api to :8000)
```

No environment variables required — all API calls are proxied via Vite's dev server.

---

### 3 — Flutter Frontend

#### One-time setup

```bash
cd flutter_frontend

# install dynatrace plugin
flutter pub add dynatrace_flutter_plugin

flutter pub get

# Copy the Dynatrace config template and fill in your credentials
cp dynatrace.config.yaml.example dynatrace.config.yaml
# Edit dynatrace.config.yaml: replace YOUR_DYNATRACE_APPLICATION_ID
#   and YOUR_ENVIRONMENT_ID with real values (or leave placeholders
#   if you don't need RUM instrumentation locally)

# configure Android/iOS project with dynatrace settings
dart run dynatrace_flutter_plugin
```

#### Run on a simulator / device

```bash
# Run against the local backend (default)
flutter run --dart-define=BASE_URL=http://localhost:8000

# Run against a deployed backend
flutter run --dart-define=BASE_URL=http://<vm-ip>

# Run on a specific device (list available devices first)
flutter devices
flutter run -d <device-id> --dart-define=BASE_URL=http://localhost:8000
```

> `BASE_URL` defaults to `http://localhost:8000` if `--dart-define` is omitted. Use `10.0.2.2` instead of `localhost` on Android emulators.

---

### 4 — Load Generator

```bash
cd load_gen
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# The load generator reads the same root `.env` as the backend — no separate
# file needed. Make sure `../.env` exists (see Backend section above).
python load_gen.py
```

---

## VM Deployment

Deploys all components — **backend**, **React frontend**, and **load generator** — onto a single Ubuntu 22.04 / 24.04 VM using nginx and systemd.

```
Internet
   │  port 80
   ▼
 nginx ──── /var/www/chatbot  (React static files)
   │
   │  /api/*
   ▼
 FastAPI :8000  (chatbot systemd service)
   │
   └── Load generator  (load_gen systemd service, continuous traffic)
```

---

### Prerequisites

| Requirement | Notes |
|---|---|
| Ubuntu 22.04 or 24.04 | Other Debian-based distros likely work but are untested |
| Non-root user with `sudo` | The script refuses to run as root |
| `git` installed | `sudo apt install git` |
| Outbound internet access | To install packages and reach the NVIDIA NIM API |
| NVIDIA API key | `nvapi-…` from [build.nvidia.com](https://build.nvidia.com) |
| Dynatrace credentials | OTLP endpoint URL + API token (scopes below) |

**Dynatrace token scopes required:** `openTelemetryTrace.ingest`, `metrics.ingest`, `logs.ingest`

---

### Step 1 — Get the code onto the VM

SSH into the VM, then clone the repo:

```bash
ssh your-user@<vm-ip>
git clone <your-repo-url> ~/chatbot-repo
cd ~/chatbot-repo
```

---

### Step 2 — Configure and run the setup script

Setup is driven by a single `.env` file at the repo root (the same file used
for local dev). Copy the example, fill it in, and run setup:

```bash
cp .env.example .env
$EDITOR .env              # at minimum, set NVIDIA_API_KEY
bash deploy/setup.sh
```

**Mandatory:** `NVIDIA_API_KEY`.

**Recommended:** `DEVCYCLE_SERVER_SDK_KEY` (chaos engineering), `OTLP_ENDPOINT`
(telemetry), `VITE_DYNATRACE_RUM_URL` (frontend RUM).

See `.env.example` for full documentation of every variable, including
optional load-generator tuning (`LOAD_GEN_CONCURRENCY`, `LOAD_GEN_RATE`, …)
and `SERVER_NAME` for nginx.

The script will then:

1. Install system packages (`python3`, `python3-venv`, `nginx`) and Node 20
2. Copy the application code to `/opt/chatbot/`
3. Create a Python virtualenv and install all Python dependencies
4. Copy your root `.env` to `/opt/chatbot/.env` (chmod 600, owned by `www-data`)
   — both systemd units read it via `EnvironmentFile=`
5. Build the React frontend (`npm ci && npm run build`), with `VITE_*` vars
   exported into the build environment from the same `.env`
6. Copy the frontend build to `/var/www/chatbot/` and configure nginx
7. Install, enable, and **start** the `chatbot` and `load_gen` systemd services

The script is **idempotent** — safe to re-run after editing `.env`. Re-running
will rewrite `/opt/chatbot/.env` with the current values and restart both
services.

> **After completion, all services are running and the application is ready to use.**

---

### Step 3 — Verify everything is working

```bash
# All three should show "active (running)"
sudo systemctl status nginx chatbot load_gen

# Test the API
curl http://localhost/api/health
# Expected: {"status":"ok"}

# Open the chat UI in your browser
http://<vm-ip>/

# Tail live logs
journalctl -u chatbot  -f
journalctl -u load_gen -f
```

---

### Configuration Files

The source of truth is a single `.env` at the repo root. `setup.sh` copies it
to the deployed location:

- **Unified env (deployed):** `/opt/chatbot/.env` — read by both systemd units via `EnvironmentFile=`
- **nginx:** `/etc/nginx/sites-available/chatbot`

To change configuration after deploy: edit `~/chatbot-repo/.env` (or
`/opt/chatbot/.env` directly for a one-off), then either re-run
`bash deploy/setup.sh` (recommended — also rebuilds the frontend if
`VITE_*` vars changed) or manually:

- Backend / load_gen: `sudo systemctl restart chatbot load_gen`
- Frontend (after changing `VITE_DYNATRACE_RUM_URL`): rebuild with
  `cd /opt/chatbot/frontend && VITE_DYNATRACE_RUM_URL=… npm run build && sudo cp -r dist/. /var/www/chatbot/`
- nginx: `sudo nginx -t && sudo systemctl reload nginx`

---

### Day-to-day operations

```bash
# View logs
journalctl -u chatbot  -f
journalctl -u load_gen -f
tail -f /var/log/nginx/chatbot.access.log

# Restart a service
sudo systemctl restart chatbot
sudo systemctl restart load_gen

# Update after a code change
cd ~/chatbot-repo && git pull
bash deploy/setup.sh     # reads .env, rewrites /opt/chatbot/.env, restarts services

# Quick update without re-running full setup
cd ~/chatbot-repo && git pull
sudo rsync -a --exclude='.venv' --exclude='__pycache__' --exclude='node_modules' --exclude='dist' . /opt/chatbot/
sudo systemctl restart chatbot load_gen
```

---

### File layout on the VM

```
/opt/chatbot/
├── .env                ← unified config (auto-generated from repo .env, chmod 600, www-data)
├── backend/            FastAPI application
├── frontend/           React source (used only for builds)
├── load_gen/           Load generator
└── venv/               Shared Python venv for backend and load_gen

/var/www/chatbot/       Compiled React static files served by nginx
/etc/nginx/sites-available/chatbot  ← nginx config (server_name from SERVER_NAME)
/etc/systemd/system/chatbot.service     ← EnvironmentFile=/opt/chatbot/.env
/etc/systemd/system/load_gen.service    ← EnvironmentFile=/opt/chatbot/.env
```

---

### Troubleshooting

| Symptom | Check |
|---|---|
| `chatbot` fails to start | `journalctl -u chatbot -n 50` — likely an invalid NVIDIA API key or Dynatrace credentials |
| Browser shows nginx 502 | Backend isn't running: `sudo systemctl start chatbot` and check logs |
| Browser shows nginx 404 | Frontend wasn't built/copied: re-run `setup.sh` |
| Load gen shows all errors | Backend not started yet or API key invalid |
| `nginx -t` fails | Syntax error in `/etc/nginx/sites-available/chatbot` |
| Flutter build fails with Dynatrace error | `dynatrace.config.yaml` missing — copy from `.example` and populate |
| Script fails at sed step | Your server name contains special characters — the script strips `http://` automatically |
