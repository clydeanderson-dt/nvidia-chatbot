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
| `ALLOWED_ORIGINS` | No | Comma-separated CORS origins (default: `http://localhost:5173,http://localhost:3000`) |
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

The script is **idempotent** — safe to re-run if it fails partway through. It will:

1. Install system packages (`python3`, `python3-venv`, `nginx`) and Node 20
2. Copy the application code to `/opt/chatbot/`
3. Create Python virtualenvs and install all Python dependencies
4. Build the React frontend (`npm ci && npm run build`)
5. Copy the frontend build to `/var/www/chatbot/` and configure nginx
6. Install and enable the `chatbot` and `load_gen` systemd services
7. Create stub `.env` files at `/opt/chatbot/backend/.env`, `/opt/chatbot/frontend/.env.local`, and `/opt/chatbot/load_gen/.env`

> **The script will pause and remind you to fill in the `.env` files before starting the backend.**

---

### Step 3 — Fill in the environment files

#### Backend — `/opt/chatbot/backend/.env`

```bash
sudo nano /opt/chatbot/backend/.env
```

| Variable | Required | Description |
|---|---|---|
| `NVIDIA_API_KEY` | **Yes** | Your `nvapi-…` key |
| `DYNATRACE_OTLP_ENDPOINT` | No | e.g. `https://abc12345.live.dynatrace.com` |
| `DYNATRACE_API_TOKEN` | No | Dynatrace API token |
| `ALLOWED_ORIGINS` | No | Comma-separated allowed origins — change to `http://<vm-ip>` |
| `SELF_HOSTED_NIM_URL` | No | Base URL for a self-hosted NIM instance |

#### Load generator — `/opt/chatbot/load_gen/.env`

```bash
sudo nano /opt/chatbot/load_gen/.env
```

| Variable | Default | Description |
|---|---|---|
| `LOAD_GEN_URL` | `http://localhost:8000` | Backend base URL — leave as-is on the same VM |
| `LOAD_GEN_CONCURRENCY` | `5` | Number of parallel async workers |
| `LOAD_GEN_PROVIDER` | `nim_api` | `nim_api` or `self_hosted` |
| `DYNATRACE_OTLP_ENDPOINT` | — | Same value as the backend |
| `DYNATRACE_API_TOKEN` | — | Same value as the backend |

#### Frontend — `/opt/chatbot/frontend/.env.local`

```bash
nano /opt/chatbot/frontend/.env.local
```

| Variable | Required | Description |
|---|---|---|
| `VITE_DYNATRACE_RUM_URL` | No | Full URL to your Dynatrace RUM JavaScript tag. If set, browser monitoring is injected into the frontend at build time. Leave the placeholder if you don't need RUM. |

> **Note:** Changes to `.env.local` require a frontend rebuild. Re-run `bash deploy/setup.sh` or rebuild manually in `/opt/chatbot/frontend/`.

---

### Step 4 — Set the server hostname in nginx

```bash
sudo nano /etc/nginx/sites-available/chatbot
```

Change `server_name _;` to your VM's IP or hostname:
```nginx
server_name 192.168.1.10;   # or chatbot.example.com
```

Then test and reload:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

### Step 5 — Start the services

```bash
sudo systemctl start chatbot

# Verify healthy
curl http://localhost/api/health
# Expected: {"status":"ok"}

sudo systemctl start load_gen
```

---

### Step 6 — Verify everything is working

```bash
# All three should show "active (running)"
sudo systemctl status nginx chatbot load_gen

# Open the chat UI
http://<vm-ip>/

# Tail live logs
journalctl -u chatbot  -f
journalctl -u load_gen -f
```

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
bash deploy/setup.sh
sudo systemctl restart chatbot load_gen
```

---

### File layout on the VM

```
/opt/chatbot/
├── backend/            FastAPI application
│   └── .env            ← credentials live here (chmod 600)
├── frontend/           React source (used only for builds)
│   └── .env.local      ← Dynatrace RUM URL (chmod 600)
├── load_gen/           Load generator
│   └── .env            ← load gen config (chmod 600)
├── venv/               Python venv for the backend
└── load_gen_venv/      Python venv for the load generator

/var/www/chatbot/       Compiled React static files served by nginx
/etc/nginx/sites-available/chatbot
/etc/systemd/system/chatbot.service
/etc/systemd/system/load_gen.service
```

---

### Troubleshooting

| Symptom | Check |
|---|---|
| `chatbot` fails to start | `journalctl -u chatbot -n 50` — likely a missing or wrong `.env` value |
| Browser shows nginx 502 | Backend isn't running: `sudo systemctl start chatbot` |
| Browser shows nginx 404 | Frontend wasn't copied: re-run `setup.sh` or copy `frontend/dist/*` to `/var/www/chatbot/` |
| Load gen shows all errors | Backend URL wrong in `load_gen/.env`, or backend isn't started yet |
| `nginx -t` fails | Syntax error in `/etc/nginx/sites-available/chatbot` — check `server_name` line |
| Flutter build fails with Dynatrace error | `dynatrace.config.yaml` missing — copy from `.example` and populate |
