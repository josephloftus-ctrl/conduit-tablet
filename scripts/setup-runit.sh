#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Setup runit services for all Conduit tablet services.
# Run once after: pkg install termux-services && sv-enable
# Hardcodes Termux paths — runit runs in minimal env where $HOME may be unset.

PREFIX="/data/data/com.termux/files/usr"
HOME="/data/data/com.termux/files/home"
SV_DIR="$PREFIX/var/service"

# runit runs scripts in a minimal env — PATH must be explicit
TERMUX_PATH="$PREFIX/bin:$HOME/bin:$HOME/.local/bin"

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
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
cd $HOME/conduit
set -a
. $HOME/conduit/server/.env
set +a
exec python -m server
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-server"

# --- 2. Cloudflared tunnel ---
SVC="$SV_DIR/conduit-tunnel"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
CONFIG="$HOME/.cloudflared/config.yml"
# Guard: refuse to start if config has placeholder tokens
if grep -q "TUNNEL_ID_HERE" "\$CONFIG" 2>/dev/null; then
  echo "FATAL: config.yml contains placeholder TUNNEL_ID_HERE — refusing to start" >&2
  echo "Edit \$CONFIG with your actual tunnel ID first." >&2
  sleep 60
  exit 1
fi
exec cloudflared tunnel --config "\$CONFIG" run
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-tunnel"

# --- 3. Search proxy ---
SVC="$SV_DIR/conduit-search"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
cd $HOME/conduit-tablet/search-proxy
exec python proxy.py
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-search"

# --- 4. ntfy server ---
SVC="$SV_DIR/conduit-ntfy"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
exec $HOME/bin/ntfy serve --config $HOME/ntfy-data/server.yml
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-ntfy"

# --- 5. Spectre backend ---
SVC="$SV_DIR/conduit-spectre"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
cd $HOME/spectre
exec uvicorn backend.api.main:app --host 0.0.0.0 --port 8000 --limit-max-requests 1000
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-spectre"

# --- 6. Nginx gateway (Spectre frontend) ---
SVC="$SV_DIR/conduit-nginx"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
exec nginx -g 'daemon off;' -c $HOME/spectre/nginx/spectre.conf -p $HOME/spectre/nginx/
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-nginx"

# --- 7. Morning Brief ---
SVC="$SV_DIR/conduit-brief"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
cd $HOME/morning-brief
exec python brief_server.py
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-brief"

# --- 8. crond (for watchdog cron) ---
SVC="$SV_DIR/conduit-crond"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
exec crond -n
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-crond"

# --- 9. sshd (supervised — no more manual restarts) ---
SVC="$SV_DIR/conduit-sshd"
mkdir -p "$SVC"
cat > "$SVC/run" <<EOF
#!/bin/sh
export PATH="$TERMUX_PATH"
export HOME="$HOME"
# Generate host keys if missing
if [ ! -f $PREFIX/etc/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -t ed25519 -f $PREFIX/etc/ssh/ssh_host_ed25519_key -N "" 2>/dev/null
fi
if [ ! -f $PREFIX/etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -t rsa -b 4096 -f $PREFIX/etc/ssh/ssh_host_rsa_key -N "" 2>/dev/null
fi
exec sshd -D -e
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-sshd"

echo ""
echo "Done. 9 services created (8 conduit + sshd)."
echo "runsvdir should pick them up within 5 seconds."
echo ""
echo "Verify with:"
echo "  sv status $SV_DIR/conduit-*"
