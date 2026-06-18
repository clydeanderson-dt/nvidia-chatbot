#!/usr/bin/env bash
# deploy/setup.sh — non-interactive VM setup for all three components.
#
# Configuration source of truth: a `.env` file in the repo root. Copy
# `.env.example` to `.env`, fill it in, then run:
#
#   bash deploy/setup.sh
#
# Prerequisites: Ubuntu 22.04 / 24.04, git, internet access, sudo.
# The script is idempotent — safe to re-run.

set -euo pipefail

INSTALL_DIR=/opt/chatbot
FRONTEND_WEBROOT=/var/www/chatbot
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
DEPLOYED_ENV_FILE="$INSTALL_DIR/.env"

log()  { echo "[setup] $*"; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "Run as a normal user with sudo, not as root."
command -v git >/dev/null 2>&1 || die "git is not installed."
log "Repo root: $REPO_DIR"

# ---------------------------------------------------------------------------
# 1. Load and validate configuration from $REPO_DIR/.env
# ---------------------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    die ".env not found at $ENV_FILE
        Copy .env.example to .env and fill in the values:
            cp $REPO_DIR/.env.example $ENV_FILE
            \$EDITOR $ENV_FILE"
fi

log "Loading configuration from $ENV_FILE"
# `set -a` auto-exports every var defined while it's on, so child processes
# (npm, sudo -E, etc.) inherit them.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Mandatory vars.
[[ -n "${NVIDIA_API_KEY:-}" ]] || die "NVIDIA_API_KEY is required in $ENV_FILE"

# Optional vars — assign defaults so the rest of the script can rely on them.
: "${DEVCYCLE_SERVER_SDK_KEY:=}"
: "${OTLP_ENDPOINT:=}"
: "${ALLOWED_ORIGINS:=}"
: "${SELF_HOSTED_NIM_URL:=}"
: "${VITE_DYNATRACE_RUM_URL:=}"
: "${LOAD_GEN_URL:=http://localhost:8000}"
: "${LOAD_GEN_CONCURRENCY:=10}"
: "${LOAD_GEN_PROVIDER:=nim_api}"
: "${SERVER_NAME:=}"

# Compute defaults that depend on the VM.
vm_ip=$(hostname -I | awk '{print $1}')
vm_hostname=$(hostname -f 2>/dev/null || hostname)

# nginx server_name: use the value from .env if set, otherwise fall back to
# the VM's primary IP. Strip protocol just in case the user pasted a URL.
if [[ -z "$SERVER_NAME" ]]; then
    SERVER_NAME="$vm_ip"
fi
SERVER_NAME=${SERVER_NAME#http://}
SERVER_NAME=${SERVER_NAME#https://}

# ALLOWED_ORIGINS: always include the VM-derived defaults; append any
# operator-supplied origins from .env.
default_origins="http://localhost:5173,http://localhost:3000,http://${vm_ip},http://${vm_hostname}"
if [[ -n "$ALLOWED_ORIGINS" ]]; then
    ALLOWED_ORIGINS="${default_origins},${ALLOWED_ORIGINS}"
else
    ALLOWED_ORIGINS="$default_origins"
fi

# Warnings for optional-but-recommended values.
[[ -n "$DEVCYCLE_SERVER_SDK_KEY" ]] || log "WARNING: DEVCYCLE_SERVER_SDK_KEY not set — chaos engineering will be disabled (all variables fall back to defaults)."
[[ -n "$OTLP_ENDPOINT" ]]            || log "WARNING: OTLP_ENDPOINT not set — telemetry export disabled."
[[ -n "$VITE_DYNATRACE_RUM_URL" ]]   || log "WARNING: VITE_DYNATRACE_RUM_URL not set — frontend RUM disabled."

log "Configuration loaded. Server name: $SERVER_NAME"

# ---------------------------------------------------------------------------
# 2. System packages
# ---------------------------------------------------------------------------
log "Installing system packages..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-venv python3-pip nginx

# Node 20 via NodeSource (Ubuntu may ship an older version; Vite 8 needs Node 18+).
if ! node --version 2>/dev/null | grep -qE '^v(1[89]|[2-9][0-9])'; then
    log "Installing Node.js 20 via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
log "Node $(node --version), npm $(npm --version)"

# ---------------------------------------------------------------------------
# 3. journald — cap disk usage and stop forwarding to syslog
# ---------------------------------------------------------------------------
log "Configuring systemd-journald to prevent disk fill..."
JOURNALD_CONF=/etc/systemd/journald.conf

sudo sed -i '/^ForwardToSyslog=/d'    "$JOURNALD_CONF"
sudo sed -i '/^SystemMaxUse=/d'       "$JOURNALD_CONF"
sudo sed -i '/^SystemMaxFileSize=/d'  "$JOURNALD_CONF"
sudo sed -i '/^MaxRetentionSec=/d'    "$JOURNALD_CONF"

sudo tee -a "$JOURNALD_CONF" >/dev/null <<'EOF'

# Added by chatbot setup.sh — prevent journal from flooding syslog and filling disk.
ForwardToSyslog=no
SystemMaxUse=500M
SystemMaxFileSize=50M
MaxRetentionSec=7day
EOF

sudo systemctl restart systemd-journald
log "journald configured: ForwardToSyslog=no, SystemMaxUse=500M, MaxRetentionSec=7day"

# Drop chatbot and load_gen messages from /var/log/syslog via rsyslog.
RSYSLOG_DROP=/etc/rsyslog.d/10-chatbot-drop.conf
sudo tee "$RSYSLOG_DROP" >/dev/null <<'EOF'
# Drop chatbot and load_gen log lines from syslog to prevent disk fill.
# OTel export to Dynatrace is unaffected (separate HTTP pipeline).
# Use: journalctl -u chatbot -f  or  journalctl -u load_gen -f  to read logs.
if $programname == 'chatbot' or $programname == 'load_gen' then stop
EOF
sudo systemctl restart rsyslog
log "rsyslog configured: chatbot and load_gen messages will not be written to /var/log/syslog"

# ---------------------------------------------------------------------------
# 4. Directory structure
# ---------------------------------------------------------------------------
log "Creating directory structure..."
sudo mkdir -p "$INSTALL_DIR" "$FRONTEND_WEBROOT"
sudo chown "$USER:$USER" "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# 5. Copy application code
# ---------------------------------------------------------------------------
log "Syncing application code to $INSTALL_DIR..."
rsync -a --exclude='.venv' --exclude='__pycache__' --exclude='node_modules' --exclude='dist' \
      "$REPO_DIR/" "$INSTALL_DIR/"

# ---------------------------------------------------------------------------
# 6. Install unified .env into deployed location
# ---------------------------------------------------------------------------
# Both systemd units (chatbot.service, load_gen.service) read this single
# file via EnvironmentFile=. systemd silently ignores vars the process
# doesn't consume, so the backend ignores LOAD_GEN_* and vice versa.
#
# We rewrite the on-disk file with the *resolved* values from this run
# (e.g. ALLOWED_ORIGINS with the VM IP appended) so what the services see
# matches what we just logged.
log "Writing unified env file to $DEPLOYED_ENV_FILE..."
sudo tee "$DEPLOYED_ENV_FILE" >/dev/null <<EOF
# Generated by deploy/setup.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Source of truth: $ENV_FILE in the repo. Re-run setup.sh to refresh.

NVIDIA_API_KEY=$NVIDIA_API_KEY
DEVCYCLE_SERVER_SDK_KEY=$DEVCYCLE_SERVER_SDK_KEY
OTLP_ENDPOINT=$OTLP_ENDPOINT
ALLOWED_ORIGINS=$ALLOWED_ORIGINS
SELF_HOSTED_NIM_URL=$SELF_HOSTED_NIM_URL

LOAD_GEN_URL=$LOAD_GEN_URL
LOAD_GEN_CONCURRENCY=$LOAD_GEN_CONCURRENCY
LOAD_GEN_PROVIDER=$LOAD_GEN_PROVIDER
EOF
# LOAD_GEN_RATE is optional and unset by default; only write it if provided.
if [[ -n "${LOAD_GEN_RATE:-}" ]]; then
    echo "LOAD_GEN_RATE=$LOAD_GEN_RATE" | sudo tee -a "$DEPLOYED_ENV_FILE" >/dev/null
fi
sudo chmod 600 "$DEPLOYED_ENV_FILE"
sudo chown www-data:www-data "$DEPLOYED_ENV_FILE"

# ---------------------------------------------------------------------------
# 7. Backend — Python virtualenv + dependencies
# ---------------------------------------------------------------------------
log "Setting up backend virtualenv..."
python3 -m venv "$INSTALL_DIR/venv"
log "Installing backend dependencies..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip >/dev/null
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/backend/requirements.txt"

# ---------------------------------------------------------------------------
# 8. Frontend — build static assets
# ---------------------------------------------------------------------------
log "Building frontend..."
# npm needs to write into node_modules and dist; current user owns these.
sudo chown -R "$USER:$USER" "$INSTALL_DIR/frontend"
pushd "$INSTALL_DIR/frontend" >/dev/null
log "Installing frontend dependencies..."
npm ci

# Vite auto-picks up VITE_* env vars from the process environment. Because
# we `set -a` + `source`d .env at the top, VITE_DYNATRACE_RUM_URL is already
# exported here — no .env.local needed.
log "Building frontend static assets (VITE_DYNATRACE_RUM_URL=${VITE_DYNATRACE_RUM_URL:+set})..."
npm run build
popd >/dev/null

log "Copying frontend build to $FRONTEND_WEBROOT..."
sudo cp -r "$INSTALL_DIR/frontend/dist/." "$FRONTEND_WEBROOT/"
sudo chown -R www-data:www-data "$FRONTEND_WEBROOT"

# ---------------------------------------------------------------------------
# 9. nginx
# ---------------------------------------------------------------------------
log "Installing nginx config..."
sudo cp "$INSTALL_DIR/deploy/nginx.conf" /etc/nginx/sites-available/chatbot

log "Configuring nginx server_name to $SERVER_NAME..."
sudo sed -i "s|^\s*server_name\s\+_;|    server_name $SERVER_NAME;|" /etc/nginx/sites-available/chatbot

sudo ln -sf /etc/nginx/sites-available/chatbot /etc/nginx/sites-enabled/chatbot
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

# ---------------------------------------------------------------------------
# 10. Backend systemd service
# ---------------------------------------------------------------------------
log "Installing chatbot systemd service..."
sudo cp "$INSTALL_DIR/deploy/chatbot.service" /etc/systemd/system/chatbot.service
sudo systemctl daemon-reload
sudo systemctl enable chatbot
sudo systemctl restart chatbot
log "chatbot service started."

# ---------------------------------------------------------------------------
# 11. Load generator — install dependencies into the shared venv
# ---------------------------------------------------------------------------
log "Installing load_gen dependencies..."
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/load_gen/requirements.txt" >/dev/null

log "Installing load_gen systemd service..."
sudo cp "$INSTALL_DIR/deploy/load_gen.service" /etc/systemd/system/load_gen.service
sudo systemctl daemon-reload
sudo systemctl enable load_gen
sudo systemctl restart load_gen
log "load_gen service started."

# ---------------------------------------------------------------------------
# 12. Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Setup complete!"
echo "=========================================="
echo ""
echo "  Services started:"
echo "    ✓ nginx (serving frontend on http://$SERVER_NAME)"
echo "    ✓ chatbot backend (FastAPI on port 8000)"
echo "    ✓ load_gen (generating synthetic traffic)"
echo ""
echo "  Verify:"
echo "    curl http://localhost/api/health       # → {\"status\":\"ok\"}"
echo "    curl http://$SERVER_NAME/              # → React app"
echo ""
echo "  Service logs:"
echo "    journalctl -u chatbot  -f"
echo "    journalctl -u load_gen -f"
echo "    journalctl -u nginx    -f"
echo ""
echo "  Configuration:"
echo "    Source of truth:   $ENV_FILE"
echo "    Deployed copy:     $DEPLOYED_ENV_FILE (chmod 600, www-data)"
echo "    nginx site:        /etc/nginx/sites-available/chatbot"
echo ""
echo "  To change config: edit $ENV_FILE then re-run this script."
echo ""
