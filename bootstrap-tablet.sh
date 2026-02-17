#!/data/data/com.termux/files/usr/bin/bash
set -e

# ============================================================
# Conduit Tablet Bootstrap — Idempotent, Resumable
# Run from Termux terminal on tablet (NOT over SSH)
# Safe to re-run at any point — skips completed sections
# ============================================================

PROGRESS_FILE="$HOME/.bootstrap-stage"
LOG_FILE="$HOME/bootstrap.log"

current_stage() {
  [ -f "$PROGRESS_FILE" ] && cat "$PROGRESS_FILE" || echo "0"
}

mark_done() {
  echo "$1" > "$PROGRESS_FILE"
  echo "[$(date)] Stage $1 complete" >> "$LOG_FILE"
}

stage_done() {
  [ "$(current_stage)" -ge "$1" ]
}

echo "========================================"
echo "Conduit Tablet Bootstrap"
echo "Current stage: $(current_stage)"
echo "========================================"

# ── SECTION 0: Install Base Packages ──
# Everything downstream depends on these. Idempotent — pkg install skips already-installed.
if ! stage_done 0; then
  echo ">>> Stage 0: Installing base Termux packages..."
  yes | pkg update 2>/dev/null || true
  yes | pkg upgrade 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::='--force-confold' \
    python python-pip nodejs git openssh cloudflared nginx \
    termux-api libxml2 libxslt libjpeg-turbo zlib cronie rsync 2>&1 | tee -a "$LOG_FILE"

  # ntfy binary (not in Termux repos)
  if ! command -v ntfy &>/dev/null; then
    echo "  Installing ntfy..."
    mkdir -p ~/bin
    curl -sSL "https://github.com/binwiederhier/ntfy/releases/download/v2.16.0/ntfy_2.16.0_linux_arm64.tar.gz" \
      | tar xz --strip-components=1 -C ~/bin ntfy_2.16.0_linux_arm64/ntfy
    chmod +x ~/bin/ntfy
  fi

  # pip.conf — TUR + Eutalix indexes for prebuilt ARM64 wheels
  mkdir -p ~/.config/pip
  cat > ~/.config/pip/pip.conf << 'PIPCONF'
[global]
extra-index-url = https://termux-user-repository.github.io/pypi/
PIPCONF
  echo "  pip.conf configured with TUR indexes"

  # SSH key (if pushed via ADB to /sdcard)
  if [ -f /sdcard/ssh-key.pub ] && [ ! -f ~/.ssh/authorized_keys ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cp /sdcard/ssh-key.pub ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "  SSH key installed from /sdcard"
  fi

  # Start sshd
  sshd 2>/dev/null || true
  echo "  sshd started on port 8022"

  mark_done 0
fi

# ── SECTION 1: Wake Lock ──
if ! stage_done 1; then
  echo ">>> Stage 1: Acquiring wake lock..."
  termux-wake-lock
  mark_done 1
fi

# ── SECTION 2: Storage & Directories ──
if ! stage_done 2; then
  echo ">>> Stage 2: Storage & directories..."
  # termux-setup-storage grants access to /sdcard
  # (may prompt — tap Allow on screen)
  termux-setup-storage || true
  sleep 2

  mkdir -p ~/conduit-data/{watchdog,logs}
  mkdir -p ~/documents/work/lockheed/{sales,inventory,purchasing,reports}
  mkdir -p ~/documents/sorted
  mkdir -p ~/ntfy-data
  mkdir -p $PREFIX/etc
  mark_done 2
fi

# ── SECTION 3: DNS ──
if ! stage_done 3; then
  echo ">>> Stage 3: DNS for cloudflared..."
  echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > $PREFIX/etc/resolv.conf
  mark_done 3
fi

# ── SECTION 4: Clone Repos ──
if ! stage_done 4; then
  echo ">>> Stage 4: Cloning public repos from GitHub..."
  if [ ! -d ~/conduit/.git ]; then
    git clone https://github.com/josephloftus-ctrl/conduit-server.git ~/conduit
  else
    echo "  conduit-server already cloned, pulling latest..."
    cd ~/conduit && git pull
  fi

  if [ ! -d ~/conduit-tablet/.git ]; then
    git clone https://github.com/josephloftus-ctrl/conduit-tablet.git ~/conduit-tablet
  else
    echo "  conduit-tablet already cloned, pulling latest..."
    cd ~/conduit-tablet && git pull
  fi

  echo ""
  echo "  NOTE: spectre and morning-brief are private repos."
  echo "  They will be rsync'd from laptop after SSH is up (Stage 1.5)."
  echo ""
  mark_done 4
fi

# ── SECTION 5: Install .env ──
if ! stage_done 5; then
  echo ">>> Stage 5: Installing .env..."
  if [ -f /sdcard/conduit-env ]; then
    cp /sdcard/conduit-env ~/conduit/server/.env
    echo "  .env installed from /sdcard"
  elif [ -f ~/conduit/server/.env ]; then
    echo "  .env already exists, skipping"
  else
    echo "  WARNING: No .env found! Push via ADB: adb push .env /sdcard/conduit-env"
    echo "  Then re-run this script."
    exit 1
  fi
  mark_done 5
fi

# ── SECTION 6: Python Dependencies ──
# This is the long one — 5-10 minutes. If screen locks, re-run script.
if ! stage_done 6; then
  echo ">>> Stage 6: Installing Python dependencies (this takes a while)..."
  pip install -r ~/conduit/server/requirements.txt --break-system-packages 2>&1 | tee -a "$LOG_FILE"
  if [ -f ~/conduit-tablet/search-proxy/requirements.txt ]; then
    pip install -r ~/conduit-tablet/search-proxy/requirements.txt --break-system-packages 2>&1 | tee -a "$LOG_FILE"
  fi
  mark_done 6
fi

# ── SECTION 7: Web UI Build ──
if ! stage_done 7; then
  echo ">>> Stage 7: Building web UI..."
  cd ~/conduit/web
  npm install 2>&1 | tee -a "$LOG_FILE"
  NODE_OPTIONS=--max_old_space_size=512 npm run build 2>&1 | tee -a "$LOG_FILE"
  mark_done 7
fi

# ── SECTION 8: Config Overlay + Patches ──
if ! stage_done 8; then
  echo ">>> Stage 8: Applying config overlay and patches..."
  cp ~/conduit-tablet/config.yaml ~/conduit/server/config.yaml
  if [ -f ~/conduit-tablet/patches/apply-firestore-rest.sh ]; then
    bash ~/conduit-tablet/patches/apply-firestore-rest.sh ~/conduit/server/vectorstore.py
  fi
  mark_done 8
fi

# ── SECTION 9: termux-services + runit ──
# After this section, MUST restart Termux for runit to initialize
if ! stage_done 9; then
  echo ">>> Stage 9: Installing termux-services..."
  pkg install -y termux-services

  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║  CHECKPOINT: Close Termux completely and reopen it. ║"
  echo "║  Then run: bash ~/bootstrap-tablet.sh               ║"
  echo "║  (runit needs Termux restart to initialize)         ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  # Check if runit is actually running
  if [ -d "$PREFIX/var/service" ] && sv status sshd 2>/dev/null; then
    echo "  runit appears to be running already, continuing..."
    mark_done 9
  else
    mark_done 9
    echo "  Stage 9 marked done. Restart Termux and re-run to continue."
    exit 0
  fi
fi

# ── SECTION 10: Set Up runit Services ──
# Only runs after Termux restart when runit is active
if ! stage_done 10; then
  echo ">>> Stage 10: Setting up runit services..."

  # Verify runit is running
  if ! command -v sv &>/dev/null; then
    echo "  ERROR: sv command not found. Did you restart Termux after Stage 9?"
    echo "  Close Termux, reopen, and run: bash ~/bootstrap-tablet.sh"
    exit 1
  fi

  # Re-acquire wake lock after Termux restart
  termux-wake-lock

  bash ~/conduit-tablet/scripts/setup-runit.sh
  sleep 3

  echo "  Service status:"
  sv status $PREFIX/var/service/conduit-* 2>/dev/null || true
  sv status $PREFIX/var/service/sshd 2>/dev/null || true
  mark_done 10
fi

# ── SECTION 11: Boot Script ──
if ! stage_done 11; then
  echo ">>> Stage 11: Installing boot script..."
  mkdir -p ~/.termux/boot
  cat > ~/.termux/boot/conduit-start << 'BOOT'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sleep 10
# runit (from termux-services) auto-starts all enabled services
# sshd is supervised by runit — no need to start manually
BOOT
  chmod +x ~/.termux/boot/conduit-start
  mark_done 11
fi

# ── SECTION 12: Watchdog Cron ──
if ! stage_done 12; then
  echo ">>> Stage 12: Setting up watchdog cron..."
  mkdir -p ~/conduit-data/watchdog
  (crontab -l 2>/dev/null | grep -v "watchdog.sh"; echo "*/5 * * * * $HOME/conduit-tablet/scripts/watchdog.sh >> $HOME/conduit-data/logs/watchdog.log 2>&1") | crontab -
  mark_done 12
fi

# ── SECTION 13: Cloudflared Tunnel ──
if ! stage_done 13; then
  echo ">>> Stage 13: Cloudflared tunnel setup..."
  echo "  This step is interactive — requires browser login."
  echo ""

  if [ -f ~/.cloudflared/cert.pem ]; then
    echo "  Already authenticated with Cloudflare."
  else
    echo "  Running: cloudflared tunnel login"
    echo "  A URL will appear — open it in a browser to authenticate."
    cloudflared tunnel login
  fi

  # Check if tunnel already exists
  if cloudflared tunnel list 2>/dev/null | grep -q "conduit-tablet"; then
    echo "  Tunnel 'conduit-tablet' already exists."
  else
    cloudflared tunnel create conduit-tablet
    cloudflared tunnel route dns conduit-tablet conduit.josephloftus.com
  fi

  echo ""
  echo "  Verify: edit ~/.cloudflared/config.yml with your tunnel ID if needed."
  echo "  The conduit-tunnel runit service will run cloudflared."
  mark_done 13
fi

# ── SECTION 14: Automated Backup (daily, via cron) ──
if ! stage_done 14; then
  echo ">>> Stage 14: Setting up automated backup..."
  cat > ~/backup-conduit.sh << 'BACKUP'
#!/data/data/com.termux/files/usr/bin/bash
# Daily backup of critical config to conduit-data
BACKUP_DIR=~/conduit-data/backups/$(date +%Y%m%d)
mkdir -p "$BACKUP_DIR"
cp ~/conduit/server/.env "$BACKUP_DIR/" 2>/dev/null
cp ~/conduit/server/config.yaml "$BACKUP_DIR/" 2>/dev/null
cp -r ~/.cloudflared "$BACKUP_DIR/" 2>/dev/null
crontab -l > "$BACKUP_DIR/crontab.txt" 2>/dev/null
# Keep only last 7 days
find ~/conduit-data/backups -maxdepth 1 -mtime +7 -exec rm -rf {} \; 2>/dev/null
BACKUP
  chmod +x ~/backup-conduit.sh
  (crontab -l 2>/dev/null | grep -v "backup-conduit"; echo "0 3 * * * $HOME/backup-conduit.sh") | crontab -
  mark_done 14
fi

# ── DONE ──
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Bootstrap complete!                         ║"
echo "║                                              ║"
echo "║  Verify from laptop:                         ║"
echo "║    tablet status                             ║"
echo "║    tablet ping                               ║"
echo "║                                              ║"
echo "║  Or manually:                                ║"
echo "║    sv status \$PREFIX/var/service/conduit-*    ║"
echo "║    curl localhost:8080/api/health             ║"
echo "║    curl localhost:8889/health                 ║"
echo "║    curl localhost:8000/api/health             ║"
echo "╚══════════════════════════════════════════════╝"
