#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"
SERVICES=(
    koji-server koji-tunnel koji-search koji-ntfy
    koji-spectre koji-nginx koji-brief
)

echo "Stopping Koji services..."
for svc in "${SERVICES[@]}"; do
    sv down "$SV_DIR/$svc" 2>/dev/null || true
done

sleep 1
echo ""
sv status "$SV_DIR"/koji-*
