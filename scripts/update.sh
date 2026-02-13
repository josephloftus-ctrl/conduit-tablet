#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

CONDUIT_HOME="$HOME/conduit"
TABLET_DIR="$HOME/conduit-tablet"

echo "=== Updating Conduit ==="

# Pull latest code
echo "Pulling latest from git..."
cd "$CONDUIT_HOME"
git pull --ff-only

# Re-overlay tablet config
echo "Applying tablet config..."
cp "$TABLET_DIR/config.yaml" "$CONDUIT_HOME/server/config.yaml"

# Re-apply patches
echo "Applying patches..."
bash "$TABLET_DIR/patches/apply-firestore-rest.sh" "$CONDUIT_HOME/server/vectorstore.py"

# Update pip dependencies
echo "Updating dependencies..."
source "$HOME/conduit-venv/bin/activate"
pip install -q -r "$CONDUIT_HOME/server/requirements.txt"

# Restart
echo "Restarting..."
bash "$TABLET_DIR/scripts/stop.sh"
sleep 2
bash "$TABLET_DIR/scripts/start.sh"

echo "=== Update complete ==="
