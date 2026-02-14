#!/data/data/com.termux/files/usr/bin/bash
# Healthcheck — runs via cron every 5 minutes.
# Checks runit service status + HTTP endpoints.
# Sends ntfy alert to tablet-alerts topic if anything is down.
#
# Crontab entry:
#   */5 * * * * /data/data/com.termux/files/home/conduit-tablet/scripts/healthcheck.sh

SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"
NTFY_TOPIC="https://ntfy.sh/tablet-alerts"
FAILURES=""

# Check runit services
for svc in conduit-server conduit-tunnel conduit-search conduit-ntfy \
           conduit-spectre conduit-nginx conduit-dashboard conduit-brief; do
    status=$(sv status "$SV_DIR/$svc" 2>&1)
    if ! echo "$status" | grep -q "^run:"; then
        FAILURES="${FAILURES}${svc} (runit: down)\n"
    fi
done

# Check HTTP endpoints
check_http() {
    local name="$1" url="$2"
    if ! curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
        FAILURES="${FAILURES}${name} (HTTP: unreachable)\n"
    fi
}

check_http "conduit-server" "http://localhost:8080/api/health"
check_http "conduit-search" "http://localhost:8889/health"
check_http "conduit-spectre" "http://localhost:8000"

# Send alert if any failures
if [ -n "$FAILURES" ]; then
    MESSAGE="Tablet health check FAILED at $(date '+%H:%M'):\n${FAILURES}"
    curl -sf \
        -H "Title: Tablet Alert" \
        -H "Priority: high" \
        -H "Tags: warning" \
        -d "$(printf "$MESSAGE")" \
        "$NTFY_TOPIC" > /dev/null 2>&1 || true
fi
