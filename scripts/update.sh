#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

CONDUIT_HOME="$HOME/conduit"
TABLET_DIR="$HOME/conduit-tablet"
SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"

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

# Update pip dependencies (tablet installs system-wide, no venv)
echo "Updating dependencies..."
pip install -q -r "$CONDUIT_HOME/server/requirements.txt"

# Rebuild web UI
echo "Building web UI..."
cd "$CONDUIT_HOME/web"
npm install --silent
npm run build

# Restart affected services
echo "Restarting services..."
for svc in conduit-server conduit-search conduit-spectre conduit-brief; do
    sv restart "$SV_DIR/$svc" 2>/dev/null || true
done

sleep 2
sv status "$SV_DIR"/conduit-*

echo "=== Update complete ==="
