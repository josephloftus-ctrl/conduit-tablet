#!/data/data/com.termux/files/usr/bin/bash
# Login banner with quick server status.

echo ""
echo "  ╔═══════════════════════════════╗"
echo "  ║   Conduit Tablet Server       ║"
echo "  ╚═══════════════════════════════╝"
echo ""

SERVER="DOWN"; TUNNEL="DOWN"; SEARCH="DOWN"
curl -s --max-time 1 http://localhost:8080/api/health > /dev/null 2>&1 && SERVER="UP"
pgrep -x cloudflared > /dev/null 2>&1 && TUNNEL="UP"
curl -s --max-time 1 http://localhost:8889/health > /dev/null 2>&1 && SEARCH="UP"

echo "  Server: $SERVER  |  Tunnel: $TUNNEL  |  Search: $SEARCH"
echo "  Uptime: $(uptime -p 2>/dev/null || uptime)"
echo ""
echo "  start   → ~/conduit-tablet/scripts/start.sh"
echo "  stop    → ~/conduit-tablet/scripts/stop.sh"
echo "  status  → ~/conduit-tablet/scripts/status.sh"
echo "  update  → ~/conduit-tablet/scripts/update.sh"
echo ""
