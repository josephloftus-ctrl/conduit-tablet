#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

KOJI_HOME="$HOME/koji"
TABLET_DIR="$HOME/koji-tablet"
SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"

echo "=== Updating Koji ==="

# Pull latest code
echo "Pulling latest from git..."
cd "$KOJI_HOME"
git pull --ff-only

# Re-overlay tablet config
echo "Applying tablet config..."
cp "$TABLET_DIR/config.yaml" "$KOJI_HOME/server/config.yaml"

# Re-apply patches
echo "Applying patches..."
bash "$TABLET_DIR/patches/apply-firestore-rest.sh" "$KOJI_HOME/server/vectorstore.py"

# Update pip dependencies (tablet installs system-wide, no venv)
echo "Updating dependencies..."
pip install -q -r "$KOJI_HOME/server/requirements.txt"

# Rebuild web UI
echo "Building web UI..."
cd "$KOJI_HOME/web"
npm install --silent
NODE_OPTIONS=--max_old_space_size=512 npm run build

# Restart all managed services
echo "Restarting services..."
for svc in koji-server koji-search koji-spectre koji-brief koji-tunnel koji-nginx koji-ntfy koji-crond; do
    sv restart "$SV_DIR/$svc" 2>/dev/null || true
done

sleep 2
sv status "$SV_DIR"/koji-*

echo "=== Update complete ==="
