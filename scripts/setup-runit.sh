#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Setup runit services for all Conduit tablet services.
# Run once after: pkg install termux-services && sv-enable
# Hardcodes Termux paths — runit runs in minimal env where $HOME may be unset.

PREFIX="/data/data/com.termux/files/usr"
HOME="/data/data/com.termux/files/home"
SV_DIR="$PREFIX/var/service"

setup_log() {
    local svc_dir="$1"
    mkdir -p "$svc_dir/log/main"
    cat > "$svc_dir/log/run" <<'LOGEOF'
#!/bin/sh
exec svlogd -tt ./main
LOGEOF
    chmod +x "$svc_dir/log/run"
    # s1000000 = 1MB max per log file, n10 = keep 10 files
    printf 's1000000\nn10\n' > "$svc_dir/log/main/config"
}

echo "Creating runit services under $SV_DIR/conduit-*"

# --- 1. Conduit server (needs .env) ---
SVC="$SV_DIR/conduit-server"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
cd /data/data/com.termux/files/home/conduit
set -a
. /data/data/com.termux/files/home/conduit/server/.env
set +a
exec python -m server
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-server"

# --- 2. Cloudflared tunnel ---
SVC="$SV_DIR/conduit-tunnel"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
exec cloudflared tunnel --config /data/data/com.termux/files/home/.cloudflared/config.yml run
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-tunnel"

# --- 3. Search proxy ---
SVC="$SV_DIR/conduit-search"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
cd /data/data/com.termux/files/home/conduit-tablet/search-proxy
exec python proxy.py
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-search"

# --- 4. ntfy server ---
SVC="$SV_DIR/conduit-ntfy"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
exec /data/data/com.termux/files/home/bin/ntfy serve --config /data/data/com.termux/files/home/ntfy-data/server.yml
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-ntfy"

# --- 5. Spectre backend ---
SVC="$SV_DIR/conduit-spectre"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
cd /data/data/com.termux/files/home/spectre
exec uvicorn backend.api.main:app --host 0.0.0.0 --port 8000
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-spectre"

# --- 6. Nginx gateway (Spectre frontend) ---
SVC="$SV_DIR/conduit-nginx"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
exec nginx -g 'daemon off;' -c /data/data/com.termux/files/home/spectre/nginx/spectre.conf -p /data/data/com.termux/files/home/spectre/nginx/
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-nginx"

# --- 7. Morning Brief ---
SVC="$SV_DIR/conduit-brief"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
cd /data/data/com.termux/files/home/morning-brief
exec python brief_server.py
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-brief"

# --- 8. crond (for healthcheck cron) ---
SVC="$SV_DIR/conduit-crond"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
exec crond -n
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-crond"

echo ""
echo "Done. 8 services created."
echo "runsvdir should pick them up within 5 seconds."
echo ""
echo "Verify with:"
echo "  sv status $SV_DIR/conduit-*"
