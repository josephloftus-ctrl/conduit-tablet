#!/data/data/com.termux/files/usr/bin/bash
# Full bootstrap for Conduit on Android/Termux.
# Run once after cloning conduit-tablet.

set -euo pipefail

TABLET_DIR="$(cd "$(dirname "$0")" && pwd)"
CONDUIT_HOME="$HOME/conduit"
CONDUIT_DATA="$HOME/conduit-data"

echo "========================================"
echo "  Conduit Tablet Setup"
echo "========================================"
echo ""

# --- Step 1: Update Termux packages ---
echo "[1/10] Updating Termux packages..."
pkg update -y
pkg upgrade -y

# --- Step 2: Install system packages ---
echo "[2/10] Installing packages..."
pkg install -y \
    python \
    python-pip \
    git \
    openssh \
    tmux \
    cloudflared \
    termux-api \
    libxml2 \
    libxslt \
    libjpeg-turbo \
    zlib

# --- Step 3: Grant storage access ---
echo "[3/10] Setting up storage access..."
if [ ! -d "$HOME/storage" ]; then
    echo ">> Android will show a permission dialog — please grant storage access."
    termux-setup-storage
    echo ">> Waiting for permission..."
    sleep 5
fi

if [ -d "$HOME/storage/shared" ]; then
    echo ">> Storage access confirmed."
else
    echo ">> WARNING: ~/storage/shared not found. You may need to re-run termux-setup-storage."
fi

# --- Step 4: Create directory structure ---
echo "[4/10] Creating directories..."
mkdir -p "$CONDUIT_DATA/logs"
mkdir -p "$HOME/documents/work/lockheed/sales"
mkdir -p "$HOME/documents/work/lockheed/inventory"
mkdir -p "$HOME/documents/work/lockheed/purchasing"
mkdir -p "$HOME/documents/work/lockheed/reports"
mkdir -p "$HOME/documents/sorted"

# --- Step 5: Clone Conduit repo ---
echo "[5/10] Setting up Conduit..."
if [ -d "$CONDUIT_HOME" ]; then
    echo ">> Conduit repo already exists at $CONDUIT_HOME, pulling latest..."
    cd "$CONDUIT_HOME" && git pull --ff-only
    cd "$TABLET_DIR"
else
    echo ">> Enter your Conduit git repo URL:"
    echo "   (e.g., git@github.com:user/conduit.git or https://github.com/user/conduit.git)"
    read -r REPO_URL
    git clone "$REPO_URL" "$CONDUIT_HOME"
fi

# --- Step 6: Install Python dependencies ---
echo "[6/10] Installing Python dependencies..."
python -m venv "$HOME/conduit-venv"
source "$HOME/conduit-venv/bin/activate"
pip install --upgrade pip
pip install -r "$CONDUIT_HOME/server/requirements.txt"
pip install -r "$TABLET_DIR/search-proxy/requirements.txt"

# --- Step 7: Apply tablet config + patches ---
echo "[7/10] Applying tablet configuration..."
cp "$TABLET_DIR/config.yaml" "$CONDUIT_HOME/server/config.yaml"
bash "$TABLET_DIR/patches/apply-firestore-rest.sh" "$CONDUIT_HOME/server/vectorstore.py"

# --- Step 8: Set up .env ---
echo "[8/10] Setting up environment..."
if [ ! -f "$CONDUIT_HOME/server/.env" ]; then
    cp "$TABLET_DIR/.env.template" "$CONDUIT_HOME/server/.env"
    echo ""
    echo ">> IMPORTANT: Edit $CONDUIT_HOME/server/.env and fill in your API keys!"
    echo ">> You can copy them from your laptop's server/.env"
    echo ""
else
    echo ">> .env already exists, skipping."
fi

# --- Step 9: Set up SSH ---
echo "[9/10] Configuring SSH..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/authorized_keys" ]; then
    echo ">> Paste your SSH public key (from laptop: cat ~/.ssh/id_ed25519.pub):"
    read -r PUBKEY
    echo "$PUBKEY" > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    echo ">> SSH key added."
else
    echo ">> authorized_keys already exists, skipping."
fi
# Start sshd
sshd 2>/dev/null || true
echo ">> SSH available on port 8022"

# --- Step 10: Set up auto-start ---
echo "[10/10] Setting up auto-start..."
mkdir -p "$HOME/.termux/boot"
cp "$TABLET_DIR/termux/boot.sh" "$HOME/.termux/boot/conduit-start"
chmod +x "$HOME/.termux/boot/conduit-start"

# Add motd to .bashrc if not already there
if ! grep -q "conduit-tablet/termux/motd.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Conduit server status on login" >> "$HOME/.bashrc"
    echo "[ -f \"\$HOME/conduit-tablet/termux/motd.sh\" ] && bash \"\$HOME/conduit-tablet/termux/motd.sh\"" >> "$HOME/.bashrc"
fi

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Fill in API keys:"
echo "     nano $CONDUIT_HOME/server/.env"
echo ""
echo "  2. Set up cloudflared tunnel:"
echo "     cloudflared tunnel login"
echo "     cloudflared tunnel create conduit-tablet"
echo "     # Copy the tunnel ID, then edit ~/.cloudflared/config.yml:"
echo "     #   tunnel: <your-tunnel-id>"
echo "     #   credentials-file: ~/.cloudflared/<your-tunnel-id>.json"
echo "     cloudflared tunnel route dns conduit-tablet conduit.josephloftus.com"
echo ""
echo "  3. Copy work files from laptop:"
echo "     # From your laptop, run:"
echo "     # scp -P 8022 -r ~/Documents/Work/* tablet-ip:~/documents/work/"
echo ""
echo "  4. Start the server:"
echo "     ~/conduit-tablet/scripts/start.sh"
echo ""
echo "  5. Android settings (do manually):"
echo "     - Developer Options → Stay Awake while charging"
echo "     - Battery → Termux → Unrestricted"
echo ""
echo "  Check status anytime: ~/conduit-tablet/scripts/status.sh"
echo ""
