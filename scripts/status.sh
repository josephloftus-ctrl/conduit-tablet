#!/data/data/com.termux/files/usr/bin/bash

SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"

echo "=== Conduit Tablet Status ==="
echo ""

# --- runit service status ---
echo "--- Services (runit) ---"
sv status "$SV_DIR"/conduit-* 2>/dev/null || echo "(runit not running)"
echo ""

# --- HTTP health checks ---
echo "--- Health Checks ---"

check_http() {
    local name="$1" url="$2"
    if curl -s --max-time 3 "$url" > /dev/null 2>&1; then
        printf "  %-18s UP\n" "$name"
    else
        printf "  %-18s DOWN\n" "$name"
    fi
}

check_http "Conduit server" "http://localhost:8080/api/health"
check_http "Search proxy" "http://localhost:8889/health"
check_http "Spectre backend" "http://localhost:8000"

# Cloudflared — process check (no HTTP endpoint)
if pgrep -x cloudflared > /dev/null 2>&1; then
    printf "  %-18s UP\n" "Cloudflared"
else
    printf "  %-18s DOWN\n" "Cloudflared"
fi

# Tailscale
if command -v tailscale > /dev/null 2>&1; then
    TS_STATUS=$(tailscale status --json 2>/dev/null | python -c "import sys,json; print(json.load(sys.stdin).get('BackendState','unknown'))" 2>/dev/null || echo "unknown")
    printf "  %-18s %s\n" "Tailscale" "$TS_STATUS"
fi

echo ""

# --- System resources ---
echo "--- Resources ---"
LOAD=$(awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "unknown")
echo "  Load:    $LOAD"
echo "  Uptime:  $(uptime -p 2>/dev/null || uptime)"

MEM_INFO=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%dMB / %dMB (%.0f%%)", $3, $2, $3/$2*100}' 2>/dev/null || echo "unknown")
echo "  Memory:  $MEM_INFO"

SWAP_INFO=$(free -m 2>/dev/null | awk '/Swap:/ {printf "%dMB / %dMB", $3, $2}' 2>/dev/null || echo "none")
echo "  Swap:    $SWAP_INFO"

echo "  Disk:    $(df -h ~ 2>/dev/null | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')"
if [ -d "$HOME/storage/external-1" ]; then
    echo "  SD Card: $(df -h ~/storage/external-1 2>/dev/null | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')"
fi

# Battery (requires termux-api)
if command -v termux-battery-status > /dev/null 2>&1; then
    BATT=$(termux-battery-status 2>/dev/null | python -c "
import sys, json
b = json.load(sys.stdin)
print(f\"{b['percentage']}% ({b['status']})\")" 2>/dev/null || echo "unknown")
    echo "  Battery: $BATT"
fi

echo ""
echo "  Processes: $(ps aux 2>/dev/null | wc -l) total"
