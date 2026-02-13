#!/data/data/com.termux/files/usr/bin/bash

echo "=== Conduit Tablet Status ==="
echo ""

# tmux session
if tmux has-session -t conduit 2>/dev/null; then
    echo "tmux session:   RUNNING"
    tmux list-windows -t conduit -F "  - #{window_name}: #{pane_current_command}" 2>/dev/null
else
    echo "tmux session:   STOPPED"
fi
echo ""

# Server health
if curl -s --max-time 3 http://localhost:8080/api/health > /dev/null 2>&1; then
    echo "Conduit server: UP (port 8080)"
else
    echo "Conduit server: DOWN"
fi

# Search proxy
if curl -s --max-time 3 http://localhost:8889/health > /dev/null 2>&1; then
    echo "Search proxy:   UP (port 8889)"
else
    echo "Search proxy:   DOWN"
fi

# Cloudflared
if pgrep -x cloudflared > /dev/null 2>&1; then
    echo "Cloudflared:    RUNNING"
else
    echo "Cloudflared:    STOPPED"
fi

# Tailscale
if command -v tailscale > /dev/null 2>&1; then
    TS_STATUS=$(tailscale status --json 2>/dev/null | python -c "import sys,json; print(json.load(sys.stdin).get('BackendState','unknown'))" 2>/dev/null || echo "unknown")
    echo "Tailscale:      $TS_STATUS"
else
    echo "Tailscale:      NOT INSTALLED"
fi

echo ""
echo "=== Resources ==="
echo "Uptime:  $(uptime -p 2>/dev/null || uptime)"
MEM_INFO=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%dMB / %dMB (%.0f%%)", $3, $2, $3/$2*100}' 2>/dev/null || echo "unknown")
echo "Memory:  $MEM_INFO"
echo "Disk:    $(df -h ~ 2>/dev/null | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')"
if [ -d "$HOME/storage/external-1" ]; then
    echo "SD Card: $(df -h ~/storage/external-1 2>/dev/null | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')"
fi
echo ""
echo "=== Recent Server Log ==="
tail -5 "$HOME/conduit-data/logs/server.log" 2>/dev/null || echo "(no logs yet)"
