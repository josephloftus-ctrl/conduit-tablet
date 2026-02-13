#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if ! tmux has-session -t conduit 2>/dev/null; then
    echo "Conduit session is not running."
    exit 0
fi

# Send Ctrl-C to each service window
for window in server tunnel search; do
    tmux send-keys -t "conduit:$window" C-c 2>/dev/null || true
done

sleep 2
tmux kill-session -t conduit 2>/dev/null || true
echo "Conduit stopped."
