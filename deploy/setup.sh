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
# 0.5. Gather all configuration from user
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Configuration Setup"
echo "=========================================="
echo ""

# NVIDIA API Key (required)
while true; do
    read -p "Enter your NVIDIA API Key (nvapi-...): " nvidia_key
    if [[ -n "$nvidia_key" ]]; then
        break
    fi
    echo "NVIDIA_API_KEY is required."
done

# Dynatrace OTLP Endpoint (optional, but shared between backend and load_gen)
echo ""
echo "Dynatrace telemetry is optional but recommended for observability."
read -p "Enter Dynatrace OTLP endpoint (e.g., https://abc123.live.dynatrace.com) or press Enter to skip: " dt_endpoint

# Dynatrace API Token (optional, only prompt if endpoint was provided)
dt_token=""
if [[ -n "$dt_endpoint" ]]; then
    read -p "Enter Dynatrace API token (needs openTelemetryTrace.ingest, metrics.ingest, logs.ingest): " dt_token
fi

# Dynatrace RUM (optional, for frontend browser telemetry)
echo ""
echo "The frontend can send browser telemetry to Dynatrace Real User Monitoring."
echo "Get your JS tag URL from:"
echo "  Dynatrace > Web Applications > Your App > ... menu > Edit > Setup > Code snippet"
echo "Example: https://js-cdn.dynatracelabs.com/jstag/abc123/456def/complete.js"
read -p "Enter Dynatrace RUM JavaScript tag URL (or press Enter to skip): " rum_url

# ALLOWED_ORIGINS (optional, with smart default based on VM hostname)
echo ""
vm_ip=$(hostname -I | awk '{print $1}')
vm_hostname=$(hostname -f 2>/dev/null || hostname)
default_origins="http://localhost:5173,http://localhost:3000,http://${vm_ip},http://${vm_hostname}"
read -p "Enter ALLOWED_ORIGINS [${default_origins}]: " allowed_origins
allowed_origins=${allowed_origins:-$default_origins}

# Self-hosted NIM URL (optional)
echo ""
read -p "Enter self-hosted NIM base URL (or press Enter to skip): " nim_url

# Load generator concurrency (optional)
echo ""
read -p "Enter load generator concurrency level [10]: " load_concurrency
load_concurrency=${load_concurrency:-10}

# Load generator provider (optional)
read -p "Enter load generator LLM provider (nim_api or self_hosted) [nim_api]: " load_provider
load_provider=${load_provider:-nim_api}

# Server name for nginx
echo ""
read -p "Enter server name for nginx (VM IP or hostname) [${vm_ip}]: " server_name
server_name=${server_name:-$vm_ip}
# Strip protocol if user included it (nginx server_name doesn't use protocol)
server_name=${server_name#http://}
server_name=${server_name#https://}

echo ""
log "Configuration collected. Proceeding with installation..."

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
log "Installing backend dependencies..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip >/dev/null
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/backend/requirements.txt"

# Create backend .env with values from user input
log "Creating backend .env with provided configuration..."
sudo tee "$INSTALL_DIR/backend/.env" >/dev/null <<EOF
NVIDIA_API_KEY=$nvidia_key
DYNATRACE_OTLP_ENDPOINT=$dt_endpoint
DYNATRACE_API_TOKEN=$dt_token
ALLOWED_ORIGINS=$allowed_origins
SELF_HOSTED_NIM_URL=$nim_url
EOF
sudo chmod 600 "$INSTALL_DIR/backend/.env"
sudo chown www-data:www-data "$INSTALL_DIR/backend/.env"

# ---------------------------------------------------------------------------
# 5. Frontend — build static assets
# ---------------------------------------------------------------------------
log "Building frontend..."
pushd "$INSTALL_DIR/frontend" >/dev/null
log "Installing frontend dependencies..."
npm ci

# Create .env.local with RUM URL from earlier configuration
if [[ -n "$rum_url" ]]; then
    echo "VITE_DYNATRACE_RUM_URL=$rum_url" | sudo tee .env.local >/dev/null
    log "Dynatrace RUM configured."
else
    echo "VITE_DYNATRACE_RUM_URL=" | sudo tee .env.local >/dev/null
fi
sudo chmod 600 .env.local

log "Building frontend static assets..."
npm run build
popd >/dev/null

log "Copying frontend build to $FRONTEND_WEBROOT..."
sudo cp -r "$INSTALL_DIR/frontend/dist/." "$FRONTEND_WEBROOT/"
sudo chown -R www-data:www-data "$FRONTEND_WEBROOT"

# ---------------------------------------------------------------------------
# 6. nginx
# ---------------------------------------------------------------------------
log "Installing nginx config..."
sudo cp "$INSTALL_DIR/deploy/nginx.conf" /etc/nginx/sites-available/chatbot

# Update server_name in nginx config (using | as delimiter to handle special chars)
log "Configuring nginx server_name to $server_name..."
sudo sed -i "s|^\s*server_name\s\+_;|    server_name $server_name;|" /etc/nginx/sites-available/chatbot

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
sudo systemctl start chatbot
log "chatbot service started."

# ---------------------------------------------------------------------------
# 8. Load generator — install dependencies into shared venv
# ---------------------------------------------------------------------------
log "Installing load_gen dependencies..."
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/load_gen/requirements.txt" >/dev/null

# Create load_gen .env with values from user input (reusing Dynatrace vars)
log "Creating load_gen .env with provided configuration..."
sudo tee "$INSTALL_DIR/load_gen/.env" >/dev/null <<EOF
DYNATRACE_OTLP_ENDPOINT=$dt_endpoint
DYNATRACE_API_TOKEN=$dt_token
LOAD_GEN_CONCURRENCY=$load_concurrency
LOAD_GEN_PROVIDER=$load_provider
EOF
sudo chmod 600 "$INSTALL_DIR/load_gen/.env"
sudo chown www-data:www-data "$INSTALL_DIR/load_gen/.env"

log "Installing load_gen systemd service..."
sudo cp "$INSTALL_DIR/deploy/load_gen.service" /etc/systemd/system/load_gen.service
sudo systemctl daemon-reload
sudo systemctl enable load_gen
sudo systemctl start load_gen
log "load_gen service started."

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Setup complete!"
echo "=========================================="
echo ""
echo "  Services started:"
echo "    ✓ nginx (serving frontend on http://$server_name)"
echo "    ✓ chatbot backend (FastAPI on port 8000)"
echo "    ✓ load_gen (generating synthetic traffic)"
echo ""
echo "  Verify:"
echo "    curl http://localhost/api/health   # should return {\"status\":\"ok\"}"
echo "    curl http://$server_name/          # should serve the frontend"
echo ""
echo "  Service logs:"
echo "    journalctl -u chatbot  -f"
echo "    journalctl -u load_gen -f"
echo "    journalctl -u nginx    -f"
echo ""
echo "  Configuration files created:"
echo "    $INSTALL_DIR/backend/.env"
echo "    $INSTALL_DIR/load_gen/.env"
echo "    $INSTALL_DIR/frontend/.env.local"
echo "    /etc/nginx/sites-available/chatbot"
echo ""
echo "  To rebuild the frontend with new Dynatrace RUM settings:"
echo "    1. Edit $INSTALL_DIR/frontend/.env.local"
echo "    2. cd $INSTALL_DIR/frontend && npm run build"
echo "    3. sudo cp -r dist/. $FRONTEND_WEBROOT/"
echo ""
