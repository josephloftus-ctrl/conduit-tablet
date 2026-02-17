#!/data/data/com.termux/files/usr/bin/bash
# Watchdog — replaces healthcheck.sh
# Runs via cron every 5 minutes.
# - Checks runit status + HTTP endpoints
# - Auto-restarts failed/hung services
# - Logs incidents with crash forensics
# - Escalates repeated failures
#
# Crontab: */5 * * * * ~/conduit-tablet/scripts/watchdog.sh

set -euo pipefail

SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"
DATA_DIR="$HOME/conduit-data/watchdog"
INCIDENTS="$DATA_DIR/incidents.jsonl"
STATE_FILE="$DATA_DIR/state.json"
NTFY_TOPIC="https://ntfy.sh/tablet-alerts"
TELEGRAM_TOPIC="https://ntfy.sh/tablet-critical"
NOW=$(date +%s)
ESCALATION_WINDOW=3600  # 1 hour
ESCALATION_THRESHOLD=3

# Services and their HTTP endpoints (empty = runit-only)
declare -A HTTP_CHECKS=(
    [conduit-server]="http://localhost:8080/api/health"
    [conduit-search]="http://localhost:8889/health"
    [conduit-spectre]="http://localhost:8000/api/health"
)

RUNIT_ONLY_SERVICES="conduit-tunnel conduit-ntfy conduit-nginx conduit-dashboard conduit-brief conduit-crond"

ALL_SERVICES="conduit-server conduit-search conduit-spectre $RUNIT_ONLY_SERVICES"

mkdir -p "$DATA_DIR"

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
    echo '{}' > "$STATE_FILE"
fi

# --- Helpers ---

log_incident() {
    local service="$1" type="$2" action="$3" result="$4" log_tail="$5"
    # Escape log_tail for JSON (replace newlines, quotes, backslashes)
    local escaped_tail
    escaped_tail=$(printf '%s' "$log_tail" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '|')
    printf '{"ts":%d,"service":"%s","type":"%s","action":"%s","result":"%s","log_tail":"%s"}\n' \
        "$NOW" "$service" "$type" "$action" "$result" "$escaped_tail" >> "$INCIDENTS"
}

get_log_tail() {
    local service="$1"
    local log_dir="$SV_DIR/$service/log/main"
    if [ -d "$log_dir" ]; then
        # svlogd writes to 'current'
        tail -30 "$log_dir/current" 2>/dev/null || echo "(no log)"
    else
        echo "(no log dir)"
    fi
}

record_failure() {
    local service="$1"
    local tmp
    tmp=$(mktemp)
    # Add failure timestamp to service's failure array, prune old entries
    python3 -c "
import json, sys
state = json.load(open('$STATE_FILE'))
svc = state.setdefault('$service', {'failures': [], 'last_ok': 0})
svc['failures'].append($NOW)
# Keep only failures within the escalation window
svc['failures'] = [t for t in svc['failures'] if $NOW - t < $ESCALATION_WINDOW]
json.dump(state, open('$tmp', 'w'))
" && mv "$tmp" "$STATE_FILE"
}

record_ok() {
    local service="$1"
    local tmp
    tmp=$(mktemp)
    python3 -c "
import json
state = json.load(open('$STATE_FILE'))
svc = state.setdefault('$service', {'failures': [], 'last_ok': 0})
svc['last_ok'] = $NOW
json.dump(state, open('$tmp', 'w'))
" && mv "$tmp" "$STATE_FILE"
}

get_failure_count() {
    local service="$1"
    python3 -c "
import json
state = json.load(open('$STATE_FILE'))
svc = state.get('$service', {'failures': []})
recent = [t for t in svc['failures'] if $NOW - t < $ESCALATION_WINDOW]
print(len(recent))
"
}

send_alert() {
    local title="$1" message="$2" priority="${3:-default}" tags="${4:-warning}"
    curl -sf \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$message" \
        "$NTFY_TOPIC" > /dev/null 2>&1 || true
}

send_escalation() {
    local title="$1" message="$2"
    # High priority to main topic
    send_alert "$title" "$message" "urgent" "rotating_light"
    # Also send to critical/Telegram topic
    curl -sf \
        -H "Title: $title" \
        -H "Priority: urgent" \
        -H "Tags: rotating_light" \
        -d "$message" \
        "$TELEGRAM_TOPIC" > /dev/null 2>&1 || true
}

restart_service() {
    local service="$1"
    sv restart "$SV_DIR/$service" > /dev/null 2>&1
    sleep 5
}

check_runit() {
    local service="$1"
    local status
    status=$(sv status "$SV_DIR/$service" 2>&1)
    echo "$status" | grep -q "^run:"
}

check_http() {
    local url="$1"
    curl -sf --max-time 5 "$url" > /dev/null 2>&1
}

# --- Main loop ---

ALERT_MESSAGES=""
CRITICAL_COUNT=0
HTTP_TOTAL=0
HTTP_DEAD=0

for service in $ALL_SERVICES; do
    http_url="${HTTP_CHECKS[$service]:-}"

    # Step 1: Check runit status
    if ! check_runit "$service"; then
        # Service is down per runit
        log_tail=$(get_log_tail "$service")
        log_incident "$service" "crash" "restart" "pending" "$log_tail"

        restart_service "$service"

        if check_runit "$service"; then
            log_incident "$service" "crash" "restart" "recovered" ""
            record_failure "$service"
            ALERT_MESSAGES="${ALERT_MESSAGES}${service}: crashed, auto-restarted OK\n"
        else
            log_incident "$service" "crash" "restart" "failed" ""
            record_failure "$service"
            ALERT_MESSAGES="${ALERT_MESSAGES}${service}: crashed, restart FAILED\n"
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
        fi
        continue
    fi

    # Step 2: If service has HTTP endpoint, check it
    if [ -n "$http_url" ]; then
        HTTP_TOTAL=$((HTTP_TOTAL + 1))

        if ! check_http "$http_url"; then
            # Runit says run but HTTP is dead — hung/zombie
            log_tail=$(get_log_tail "$service")
            log_incident "$service" "hung" "restart" "pending" "$log_tail"

            restart_service "$service"

            if check_http "$http_url"; then
                log_incident "$service" "hung" "restart" "recovered" ""
                record_failure "$service"
                ALERT_MESSAGES="${ALERT_MESSAGES}${service}: hung (HTTP dead), auto-restarted OK\n"
            else
                log_incident "$service" "hung" "restart" "failed" ""
                record_failure "$service"
                ALERT_MESSAGES="${ALERT_MESSAGES}${service}: hung, restart FAILED\n"
                HTTP_DEAD=$((HTTP_DEAD + 1))
                CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            fi
            continue
        fi
    fi

    # Service is healthy
    record_ok "$service"
done

# --- Escalation checks ---

for service in $ALL_SERVICES; do
    count=$(get_failure_count "$service")
    if [ "$count" -ge "$ESCALATION_THRESHOLD" ]; then
        send_escalation "ESCALATION: $service" \
            "$service has failed ${count}x in the last hour. Possible systemic issue. Check tablet immediately."
    fi
done

# All HTTP endpoints down = system-level
if [ "$HTTP_TOTAL" -gt 0 ] && [ "$HTTP_DEAD" -eq "$HTTP_TOTAL" ]; then
    send_escalation "CRITICAL: All HTTP services down" \
        "All $HTTP_TOTAL HTTP endpoints are unreachable. System-level failure on tablet."
fi

# --- Send normal alert if any issues ---

if [ -n "$ALERT_MESSAGES" ]; then
    send_alert "Watchdog $(date '+%H:%M')" "$(printf "$ALERT_MESSAGES")" "default" "wrench"
fi
