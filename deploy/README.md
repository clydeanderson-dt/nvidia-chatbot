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

cp .env.example .env               # then edit .env with your credentials
uvicorn main:app --reload
# → API available at http://localhost:8000
# → Health check: curl http://localhost:8000/api/health
```

**Backend `.env` variables:**

| Variable | Required | Description |
|---|---|---|
| `NVIDIA_API_KEY` | **Yes** | Your `nvapi-…` key |
| `DYNATRACE_OTLP_ENDPOINT` | No | e.g. `https://abc12345.live.dynatrace.com` |
| `DYNATRACE_API_TOKEN` | No | Dynatrace API token — required if endpoint is set |
| `ALLOWED_ORIGINS` | No | Comma-separated CORS origins (e.g., `http://localhost:5173,http://localhost:3000`). Include protocol, no trailing slashes. |
| `SELF_HOSTED_NIM_URL` | No | Base URL for a self-hosted NIM instance |

> Dynatrace variables are optional for local development. The server starts with a warning if they are absent.

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

cp .env.example .env               # then edit .env
python load_gen.py
```

**Load generator `.env` variables:**

| Variable | Default | Description |
|---|---|---|
| `LOAD_GEN_URL` | `http://localhost:8000` | Backend base URL |
| `LOAD_GEN_CONCURRENCY` | `5` | Number of parallel async workers |
| `LOAD_GEN_RATE` | unset | Target req/s (unset = constant-concurrency mode) |
| `LOAD_GEN_PROVIDER` | `nim_api` | `nim_api` or `self_hosted` |
| `DYNATRACE_OTLP_ENDPOINT` | — | Optional — telemetry export |
| `DYNATRACE_API_TOKEN` | — | Optional — telemetry export |

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

### Step 2 — Run the setup script

```bash
bash deploy/setup.sh
```

The script is **fully interactive** and will prompt you for all necessary configuration upfront. You'll be asked for:

1. **NVIDIA API Key** (required) — your `nvapi-...` key
2. **Dynatrace OTLP Endpoint** (optional) — e.g., `https://abc12345.live.dynatrace.com`
3. **Dynatrace API Token** (optional) — required if endpoint is provided
4. **Dynatrace RUM JavaScript tag URL** (optional) — for frontend browser monitoring
5. **ALLOWED_ORIGINS** (optional) — comma-separated list of allowed CORS origins (e.g., `http://192.168.1.100,https://chatbot.example.com`). Defaults to localhost + your VM IP/hostname. **Note:** Include protocol (`http://` or `https://`) but no trailing slashes.
6. **Self-hosted NIM URL** (optional) — only if using a self-hosted NIM instance
7. **Load generator concurrency** (optional) — defaults to 10
8. **Load generator provider** (optional) — `nim_api` or `self_hosted`, defaults to `nim_api`
9. **nginx server_name** (optional) — VM IP or hostname (without protocol). Defaults to your VM IP.

The script will then:

1. Install system packages (`python3`, `python3-venv`, `nginx`) and Node 20
2. Copy the application code to `/opt/chatbot/`
3. Create Python virtualenvs and install all Python dependencies
4. Create all `.env` files with the values you provided
5. Build the React frontend (`npm ci && npm run build`)
6. Copy the frontend build to `/var/www/chatbot/` and configure nginx
7. Install, enable, and **start** the `chatbot` and `load_gen` systemd services

The script is **idempotent** — safe to re-run if it fails partway through.

> **After completion, all services are running and the application is ready to use** — no manual configuration needed!

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

If you need to modify the configuration later, the following files were created:

- **Backend:** `/opt/chatbot/backend/.env`
- **Frontend:** `/opt/chatbot/frontend/.env.local`
- **Load generator:** `/opt/chatbot/load_gen/.env`
- **nginx:** `/etc/nginx/sites-available/chatbot`

After editing:
- Backend/load_gen: `sudo systemctl restart chatbot` or `sudo systemctl restart load_gen`
- Frontend: Rebuild with `cd /opt/chatbot/frontend && npm run build && sudo cp -r dist/. /var/www/chatbot/`
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
bash deploy/setup.sh     # Will prompt for config again; press Enter to keep existing values
sudo systemctl restart chatbot load_gen

# Quick update without re-running full setup
cd ~/chatbot-repo && git pull
sudo rsync -a --exclude='.venv' --exclude='__pycache__' --exclude='node_modules' --exclude='dist' . /opt/chatbot/
sudo systemctl restart chatbot load_gen
```

---

### File layout on the VM

```
/opt/chatbot/
├── backend/            FastAPI application
│   └── .env            ← backend credentials (auto-generated, chmod 600)
├── frontend/           React source (used only for builds)
│   └── .env.local      ← Dynatrace RUM URL (auto-generated, chmod 600)
├── load_gen/           Load generator
│   └── .env            ← load gen config (auto-generated, reuses Dynatrace vars, chmod 600)
└── venv/               Shared Python venv for backend and load_gen

/var/www/chatbot/       Compiled React static files served by nginx
/etc/nginx/sites-available/chatbot  ← nginx config (server_name auto-configured)
/etc/systemd/system/chatbot.service
/etc/systemd/system/load_gen.service
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
