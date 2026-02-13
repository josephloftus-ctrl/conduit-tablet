#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

CONDUIT_HOME="$HOME/conduit"
TABLET_DIR="$HOME/conduit-tablet"
LOG_DIR="$HOME/conduit-data/logs"

mkdir -p "$LOG_DIR"

# Check if session already exists
if tmux has-session -t conduit 2>/dev/null; then
    echo "Conduit session already running. Use 'tmux attach -t conduit' to view."
    exit 0
fi

# Source .env and activate venv
set -a
source "$CONDUIT_HOME/server/.env"
set +a
VENV="$HOME/conduit-venv/bin/activate"

# Window 0: Conduit server
tmux new-session -d -s conduit -n server \
    "source $VENV && cd $CONDUIT_HOME && python -m server 2>&1 | tee -a $LOG_DIR/server.log"

# Window 1: cloudflared tunnel
tmux new-window -t conduit -n tunnel \
    "cloudflared tunnel --config $HOME/.cloudflared/config.yml run 2>&1 | tee -a $LOG_DIR/tunnel.log"

# Window 2: search proxy
tmux new-window -t conduit -n search \
    "source $VENV && cd $TABLET_DIR/search-proxy && python proxy.py 2>&1 | tee -a $LOG_DIR/search-proxy.log"

# Window 3: free shell
tmux new-window -t conduit -n shell

tmux select-window -t conduit:server
echo "Conduit started. Use 'tmux attach -t conduit' to view."
