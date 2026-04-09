#!/usr/bin/env bash
# deploy/setup.sh — one-shot VM setup for all three components
#
# Run as a non-root user with sudo privileges:
#   bash deploy/setup.sh
#
# Prerequisites: Ubuntu 22.04 / 24.04, git, internet access.
# The script is idempotent — safe to re-run after a partial failure.

set -euo pipefail

INSTALL_DIR=/opt/chatbot
FRONTEND_WEBROOT=/var/www/chatbot
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

log()  { echo "[setup] $*"; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "Run as a normal user with sudo, not as root."
command -v git  >/dev/null 2>&1 || die "git is not installed."
log "Repo root: $REPO_DIR"

# ---------------------------------------------------------------------------
# 1. System packages
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
# 2. Directory structure
# ---------------------------------------------------------------------------
log "Creating directory structure..."
sudo mkdir -p "$INSTALL_DIR" "$FRONTEND_WEBROOT"
sudo chown "$USER:$USER" "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# 3. Copy application code
# ---------------------------------------------------------------------------
log "Syncing application code to $INSTALL_DIR..."
rsync -a --exclude='.venv' --exclude='__pycache__' --exclude='node_modules' --exclude='dist' \
      "$REPO_DIR/" "$INSTALL_DIR/"

# ---------------------------------------------------------------------------
# 4. Backend — Python virtualenv + dependencies
# ---------------------------------------------------------------------------
log "Setting up backend virtualenv..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --quiet -r "$INSTALL_DIR/backend/requirements.txt"

# Prompt for .env if it doesn't already exist.
if [[ ! -f "$INSTALL_DIR/backend/.env" ]]; then
    log "Creating backend .env from example — fill in the real values before starting the service."
    cp "$INSTALL_DIR/backend/.env.example" "$INSTALL_DIR/backend/.env"
    chmod 600 "$INSTALL_DIR/backend/.env"
    sudo chown www-data:www-data "$INSTALL_DIR/backend/.env"
    echo ""
    echo "  *** Edit $INSTALL_DIR/backend/.env and set:"
    echo "      NVIDIA_API_KEY, DYNATRACE_OTLP_ENDPOINT, DYNATRACE_API_TOKEN"
    echo "      (and ALLOWED_ORIGINS if the VM has a public hostname)"
    echo ""
fi

# ---------------------------------------------------------------------------
# 5. Frontend — build static assets
# ---------------------------------------------------------------------------
log "Building frontend..."
pushd "$INSTALL_DIR/frontend" >/dev/null
npm ci --silent

# Ensure .env.local exists so VITE_DYNATRACE_RUM_URL is available at build time.
if [[ ! -f .env.local ]]; then
    log "Creating frontend .env.local from example — fill in the Dynatrace RUM URL for browser monitoring."
    cp .env.example .env.local
    chmod 600 .env.local
    echo ""
    echo "  *** Edit $INSTALL_DIR/frontend/.env.local and set:"
    echo "      VITE_DYNATRACE_RUM_URL"
    echo "      (Dynatrace RUM is optional — the app works without it)"
    echo ""
fi

npm run build --silent
popd >/dev/null

log "Copying frontend build to $FRONTEND_WEBROOT..."
sudo cp -r "$INSTALL_DIR/frontend/dist/." "$FRONTEND_WEBROOT/"
sudo chown -R www-data:www-data "$FRONTEND_WEBROOT"

# ---------------------------------------------------------------------------
# 6. nginx
# ---------------------------------------------------------------------------
log "Installing nginx config..."
sudo cp "$INSTALL_DIR/deploy/nginx.conf" /etc/nginx/sites-available/chatbot
# Enable site, remove default to avoid catch-all conflicts.
sudo ln -sf /etc/nginx/sites-available/chatbot /etc/nginx/sites-enabled/chatbot
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

# ---------------------------------------------------------------------------
# 7. Backend systemd service
# ---------------------------------------------------------------------------
log "Installing chatbot systemd service..."
sudo cp "$INSTALL_DIR/deploy/chatbot.service" /etc/systemd/system/chatbot.service
sudo systemctl daemon-reload
sudo systemctl enable chatbot

if [[ -f "$INSTALL_DIR/backend/.env" ]] && \
   grep -qv '^NVIDIA_API_KEY=nvapi-xxx' "$INSTALL_DIR/backend/.env" 2>/dev/null; then
    sudo systemctl start chatbot
    log "chatbot service started."
else
    log "Skipping chatbot start — fill in $INSTALL_DIR/backend/.env first, then run:"
    log "  sudo systemctl start chatbot"
fi

# ---------------------------------------------------------------------------
# 8. Load generator — Python virtualenv + dependencies
# ---------------------------------------------------------------------------
log "Setting up load_gen virtualenv..."
python3 -m venv "$INSTALL_DIR/load_gen_venv"
"$INSTALL_DIR/load_gen_venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/load_gen_venv/bin/pip" install --quiet -r "$INSTALL_DIR/load_gen/requirements.txt"

if [[ ! -f "$INSTALL_DIR/load_gen/.env" ]]; then
    log "Creating load_gen .env from example — fill in the real values before starting the service."
    cp "$INSTALL_DIR/load_gen/.env.example" "$INSTALL_DIR/load_gen/.env"
    chmod 600 "$INSTALL_DIR/load_gen/.env"
    sudo chown www-data:www-data "$INSTALL_DIR/load_gen/.env"
    echo ""
    echo "  *** Edit $INSTALL_DIR/load_gen/.env and set:"
    echo "      DYNATRACE_OTLP_ENDPOINT, DYNATRACE_API_TOKEN"
    echo "      (and LOAD_GEN_CONCURRENCY, LOAD_GEN_PROVIDER if needed)"
    echo ""
fi

log "Installing load_gen systemd service..."
sudo cp "$INSTALL_DIR/deploy/load_gen.service" /etc/systemd/system/load_gen.service
sudo systemctl daemon-reload
sudo systemctl enable load_gen
log "Run 'sudo systemctl start load_gen' once the backend is healthy."

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Setup complete."
echo "=========================================="
echo ""
echo "  Next steps:"
echo "  1. Edit $INSTALL_DIR/backend/.env"
echo "     — set NVIDIA_API_KEY, DYNATRACE_OTLP_ENDPOINT, DYNATRACE_API_TOKEN"
echo "     — set ALLOWED_ORIGINS to http://<vm-ip> if needed"
echo "  2. Edit $INSTALL_DIR/load_gen/.env (Dynatrace vars, LOAD_GEN_CONCURRENCY)"
echo "  3. Update server_name in /etc/nginx/sites-available/chatbot to your VM IP/hostname"
echo "     then: sudo nginx -t && sudo systemctl reload nginx"
echo "  4. sudo systemctl start chatbot"
echo "  5. curl http://localhost/api/health   # should return {\"status\":\"ok\"}"
echo "  6. sudo systemctl start load_gen"
echo ""
echo "  Service logs:"
echo "    journalctl -u chatbot  -f"
echo "    journalctl -u load_gen -f"
echo ""
