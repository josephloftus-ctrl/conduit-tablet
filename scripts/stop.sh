#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"
SERVICES=(
    conduit-server conduit-tunnel conduit-search conduit-ntfy
    conduit-spectre conduit-nginx conduit-dashboard conduit-brief
)

echo "Stopping Conduit services..."
for svc in "${SERVICES[@]}"; do
    sv down "$SV_DIR/$svc" 2>/dev/null || true
done

sleep 1
echo ""
sv status "$SV_DIR"/conduit-*
