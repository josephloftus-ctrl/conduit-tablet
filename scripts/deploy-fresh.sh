#!/usr/bin/env bash
# deploy-fresh.sh — One-shot tablet deployment from laptop after factory reset.
#
# Prerequisites (do these manually first):
#   1. Factory reset tablet
#   2. Skip through Android setup (connect to WiFi, skip Google sign-in or sign in)
#   3. Enable Developer Options (Settings > About > tap Build Number 7x)
#   4. Enable USB Debugging in Developer Options
#   5. Enable "Stay Awake while charging" in Developer Options
#   6. Plug in USB cable, accept ADB prompt on tablet
#   7. Install from F-Droid: Termux, Termux:Boot, Termux:API
#   8. Install from Play Store: Tailscale
#   9. Open Termux once to initialize, then open Tailscale and sign in
#  10. Open Termux:Boot once (so Android registers it)
#
# Then from laptop:
#   bash ~/Projects/conduit-tablet/scripts/deploy-fresh.sh
#
# What this does NOT do (learned the hard way):
#   - Does NOT disable Google Play Services
#   - Does NOT debloat any system packages
#   - Does NOT touch any Motorola/Lenovo system components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAPTOP_ENV="/home/joseph/Projects/conduit-server/server/.env"
KISS_APK="/tmp/kiss-launcher.apk"
TABLET_SSH="joseph@100.115.173.115"  # Update if Tailscale IP changes
SSH_PORT=8022
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINPXK9AouTH3yixV4KIx4npBihxUTiO26H41fSK/z3BU joseph@josephPC"
CONDUIT_REPO="https://github.com/josephloftus-ctrl/conduit-server.git"
TABLET_REPO="https://github.com/josephloftus-ctrl/conduit-tablet.git"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

step() { echo -e "\n${GREEN}[$1]${NC} $2"; }
warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
fail() { echo -e "${RED}FAILED:${NC} $1"; exit 1; }

# ============================================================
# PHASE 0: Pre-flight checks
# ============================================================
step "0" "Pre-flight checks"

if ! adb devices | grep -q "device$"; then
    fail "No ADB device found. Plug in tablet and accept USB debugging prompt."
fi
echo "  ADB: connected"

if [ ! -f "$LAPTOP_ENV" ]; then
    fail "Laptop .env not found at $LAPTOP_ENV"
fi
echo "  Laptop .env: found"

# ============================================================
# PHASE 1: KISS Launcher (ADB — no Termux needed)
# ============================================================
step "1" "Installing KISS Launcher via ADB"

if [ ! -f "$KISS_APK" ]; then
    echo "  Downloading KISS Launcher from F-Droid..."
    wget -q -O "$KISS_APK" "https://f-droid.org/repo/fr.neamar.kiss_189.apk"
fi

if adb shell pm list packages | grep -q "fr.neamar.kiss"; then
    echo "  KISS already installed"
else
    adb install "$KISS_APK"
    echo "  KISS installed"
fi

# Set KISS as default home
adb shell cmd package set-home-activity fr.neamar.kiss/.MainActivity 2>/dev/null || true
echo "  KISS set as default launcher"
echo "  (You may need to dismiss a contacts permission dialog on the tablet)"

# ============================================================
# PHASE 2: Bootstrap Termux via ADB
# ============================================================
step "2" "Bootstrapping Termux via ADB shell"

# Use run-as to push commands into Termux's context...
# Actually, the cleanest way: push a bootstrap script and run it in Termux.
# First, push files to a shared location ADB can write to.

BOOTSTRAP=$(mktemp)
cat > "$BOOTSTRAP" << 'TERMUX_BOOTSTRAP'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

echo "=== Termux Bootstrap ==="

# Update and install core packages
echo "[1] Installing packages..."
yes | pkg update 2>/dev/null || true
yes | pkg upgrade 2>/dev/null || true
pkg install -y python python-pip nodejs git openssh cloudflared nginx \
    termux-api termux-services libxml2 libxslt libjpeg-turbo zlib cronie

# Install ntfy binary
if ! command -v ntfy &>/dev/null; then
    echo "[2] Installing ntfy..."
    mkdir -p "$HOME/bin"
    curl -sSL "https://github.com/binwiederhier/ntfy/releases/download/v2.16.0/ntfy_2.16.0_linux_arm64.tar.gz" \
        | tar xz --strip-components=1 -C "$HOME/bin" ntfy_2.16.0_linux_arm64/ntfy
    chmod +x "$HOME/bin/ntfy"
fi

# SSH setup
echo "[3] Setting up SSH..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
cat > "$HOME/.ssh/authorized_keys" << 'SSHKEY'
PLACEHOLDER_SSH_KEY
SSHKEY
chmod 600 "$HOME/.ssh/authorized_keys"
sshd 2>/dev/null || true

# Clone repos
echo "[4] Cloning repos..."
if [ ! -d "$HOME/conduit-tablet" ]; then
    git clone PLACEHOLDER_TABLET_REPO "$HOME/conduit-tablet"
fi
if [ ! -d "$HOME/conduit" ]; then
    git clone PLACEHOLDER_CONDUIT_REPO "$HOME/conduit"
fi

# Python deps (system-wide, no venv on tablet)
echo "[5] Installing Python deps..."
pip install -r "$HOME/conduit/server/requirements.txt" 2>/dev/null || true
pip install -r "$HOME/conduit-tablet/search-proxy/requirements.txt" 2>/dev/null || true

# Build web UI
echo "[6] Building web UI..."
cd "$HOME/conduit/web"
npm install --silent 2>/dev/null || true
npm run build 2>/dev/null || true

# Apply tablet config + patches
echo "[7] Applying config overlay + patches..."
cp "$HOME/conduit-tablet/config.yaml" "$HOME/conduit/server/config.yaml"
bash "$HOME/conduit-tablet/patches/apply-firestore-rest.sh" "$HOME/conduit/server/vectorstore.py"

# Boot script
echo "[8] Setting up auto-start..."
mkdir -p "$HOME/.termux/boot"
cp "$HOME/conduit-tablet/termux/boot.sh" "$HOME/.termux/boot/conduit-start"
chmod +x "$HOME/.termux/boot/conduit-start"

# MOTD
if ! grep -q "conduit-tablet/termux/motd.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo '[ -f "$HOME/conduit-tablet/termux/motd.sh" ] && bash "$HOME/conduit-tablet/termux/motd.sh"' >> "$HOME/.bashrc"
fi

# ntfy data dir
mkdir -p "$HOME/ntfy-data"

# Storage
if [ ! -d "$HOME/storage" ]; then
    echo "[!] Run 'termux-setup-storage' manually to grant storage access"
fi

echo ""
echo "=== Bootstrap complete ==="
echo "Remaining: .env, runit services, cloudflared tunnel, watchdog"
TERMUX_BOOTSTRAP

# Replace placeholders
sed -i "s|PLACEHOLDER_SSH_KEY|$SSH_PUBKEY|" "$BOOTSTRAP"
sed -i "s|PLACEHOLDER_TABLET_REPO|$TABLET_REPO|" "$BOOTSTRAP"
sed -i "s|PLACEHOLDER_CONDUIT_REPO|$CONDUIT_REPO|" "$BOOTSTRAP"

echo "  Pushing bootstrap script to tablet..."
adb push "$BOOTSTRAP" /sdcard/termux-bootstrap.sh
rm "$BOOTSTRAP"

echo ""
echo "  ============================================"
echo "  NOW: Open Termux on the tablet and run:"
echo ""
echo "    cp /sdcard/termux-bootstrap.sh ~/ && bash ~/termux-bootstrap.sh"
echo ""
echo "  Wait for it to finish, then press Enter here."
echo "  ============================================"
read -r -p "  Press Enter when Termux bootstrap is done... "

# ============================================================
# PHASE 3: SSH setup — push .env, runit, watchdog, cron
# ============================================================
step "3" "Configuring via SSH"

# Wait for SSH
echo "  Waiting for SSH access..."
for i in $(seq 1 12); do
    if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -p $SSH_PORT $TABLET_SSH "echo ok" 2>/dev/null; then
        echo "  SSH: connected"
        break
    fi
    if [ "$i" -eq 12 ]; then
        fail "Cannot SSH to tablet. Check Tailscale is connected and sshd is running."
    fi
    sleep 5
done

SSH_CMD="ssh -p $SSH_PORT $TABLET_SSH"

# Push .env
echo "  Pushing .env..."
scp -P $SSH_PORT "$LAPTOP_ENV" "$TABLET_SSH:~/conduit/server/.env"

# Set up runit services
echo "  Setting up runit services..."
$SSH_CMD "bash ~/conduit-tablet/scripts/setup-runit.sh"

# Wait for services to start
echo "  Waiting for services to come up..."
sleep 10

# Create watchdog data dir
echo "  Setting up watchdog..."
$SSH_CMD "mkdir -p ~/conduit-data/watchdog"

# Set up cron for watchdog
$SSH_CMD 'echo "*/5 * * * * /data/data/com.termux/files/home/conduit-tablet/scripts/watchdog.sh" | crontab -'
echo "  Watchdog cron: active (every 5 min)"

# Create work directories
echo "  Creating directory structure..."
$SSH_CMD "mkdir -p ~/conduit-data/logs ~/documents/work/lockheed/{sales,inventory,purchasing,reports} ~/documents/sorted"

# ============================================================
# PHASE 4: Verify
# ============================================================
step "4" "Verifying deployment"

echo "  Checking services..."
$SSH_CMD "sv status \${PREFIX:-/data/data/com.termux/files/usr}/var/service/conduit-*"

echo ""
echo "  Checking HTTP endpoints..."
sleep 5

HEALTH=$($SSH_CMD "curl -sf --max-time 5 localhost:8080/api/health" 2>/dev/null || echo "FAIL")
if echo "$HEALTH" | grep -q '"ok"'; then
    echo "  conduit-server: OK ($HEALTH)"
else
    warn "conduit-server not responding yet (may still be starting)"
fi

SEARCH=$($SSH_CMD "curl -sf --max-time 5 localhost:8889/health" 2>/dev/null || echo "FAIL")
if echo "$SEARCH" | grep -q '"ok"'; then
    echo "  conduit-search: OK"
else
    warn "conduit-search not responding yet"
fi

echo ""
echo "  Running watchdog..."
$SSH_CMD "bash ~/conduit-tablet/scripts/watchdog.sh" 2>/dev/null || true
echo "  Watchdog state:"
$SSH_CMD "cat ~/conduit-data/watchdog/state.json 2>/dev/null | python3 -m json.tool" 2>/dev/null || echo "  (no state yet)"

# ============================================================
# Done
# ============================================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Deployment complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  Manual steps remaining:"
echo "    1. Open Tailscale on tablet and sign in"
echo "    2. In Android Settings:"
echo "       - Battery > Termux > Unrestricted"
echo "       - Lock Termux in recent apps"
echo "       - System > Software Update > Auto-update > Off"
echo "    3. Set up cloudflared tunnel (if not reusing existing):"
echo "       ssh -p 8022 $TABLET_SSH"
echo "       cloudflared tunnel login"
echo "       cloudflared tunnel create conduit-tablet"
echo "       # Edit ~/.cloudflared/config.yml with tunnel ID"
echo "    4. Grant storage: open Termux, run termux-setup-storage"
echo ""
echo "  Verify: ssh -p 8022 $TABLET_SSH '~/conduit-tablet/scripts/status.sh'"
echo ""
