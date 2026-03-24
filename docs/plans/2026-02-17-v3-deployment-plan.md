# Conduit Tablet v3 Deployment — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update conduit-tablet repo with clean v3 scripts, create laptop CLI, then deploy to factory-reset tablet.

**Architecture:** 8 runit services + sshd on Lenovo Tab M11 (Android 14, ARM64, 4GB RAM). Public repos (conduit-server, conduit-tablet) cloned via git; private repos (spectre, morning-brief) rsync'd from laptop after SSH is up.

**Tech Stack:** Bash (Termux), runit, cloudflared, nginx, Python/pip, Node/npm, ADB

---

## Task 1: Remove conduit-dashboard from setup-runit.sh

**Files:**
- Modify: `scripts/setup-runit.sh:98-109`

**Step 1: Remove the dashboard service block**

Delete lines 98-109 (the `# --- 7. Dashboard ---` block). Update the final echo from "9 services" to "8 services".

```bash
# DELETE this entire block (lines 98-109):
# --- 7. Dashboard ---
SVC="$SV_DIR/conduit-dashboard"
mkdir -p "$SVC"
cat > "$SVC/run" <<'EOF'
#!/bin/sh
cd /data/data/com.termux/files/home/dashboard
export DASHBOARD_PASSWORD=conduit
exec python server.py
EOF
chmod +x "$SVC/run"
setup_log "$SVC"
echo "  conduit-dashboard"
```

Change the final echo:
```bash
# FROM:
echo "Done. 9 services created."
# TO:
echo "Done. 8 services created."
```

**Step 2: Verify file is clean**

Run: `bash -n scripts/setup-runit.sh`
Expected: no output (syntax OK)

**Step 3: Commit**

```bash
git add scripts/setup-runit.sh
git commit -m "remove conduit-dashboard service (does not exist)"
```

---

## Task 2: Remove dashboard from start.sh, stop.sh, update.sh

**Files:**
- Modify: `scripts/start.sh:6`
- Modify: `scripts/stop.sh:6`
- Modify: `scripts/update.sh:35`

**Step 1: Update the SERVICES arrays in start.sh and stop.sh**

Both files have identical arrays. Change:
```bash
# FROM:
SERVICES=(
    conduit-server conduit-tunnel conduit-search conduit-ntfy
    conduit-spectre conduit-nginx conduit-dashboard conduit-brief
)
# TO:
SERVICES=(
    conduit-server conduit-tunnel conduit-search conduit-ntfy
    conduit-spectre conduit-nginx conduit-brief
)
```

**Step 2: Update the restart list in update.sh**

Line 35, change:
```bash
# FROM:
for svc in conduit-server conduit-search conduit-spectre conduit-dashboard conduit-brief; do
# TO:
for svc in conduit-server conduit-search conduit-spectre conduit-brief; do
```

**Step 3: Syntax check all three**

Run: `bash -n scripts/start.sh && bash -n scripts/stop.sh && bash -n scripts/update.sh && echo OK`
Expected: `OK`

**Step 4: Commit**

```bash
git add scripts/start.sh scripts/stop.sh scripts/update.sh
git commit -m "remove dashboard refs from start/stop/update scripts"
```

---

## Task 3: Remove dashboard from healthcheck.sh and watchdog.sh

**Files:**
- Modify: `scripts/healthcheck.sh:14-15`
- Modify: `scripts/watchdog.sh:30`

**Step 1: Update healthcheck.sh service list**

Lines 14-15, change:
```bash
# FROM:
for svc in conduit-server conduit-tunnel conduit-search conduit-ntfy \
           conduit-spectre conduit-nginx conduit-dashboard conduit-brief; do
# TO:
for svc in conduit-server conduit-tunnel conduit-search conduit-ntfy \
           conduit-spectre conduit-nginx conduit-brief; do
```

**Step 2: Update watchdog.sh RUNIT_ONLY_SERVICES**

Line 30, change:
```bash
# FROM:
RUNIT_ONLY_SERVICES="conduit-tunnel conduit-ntfy conduit-nginx conduit-dashboard conduit-brief conduit-crond"
# TO:
RUNIT_ONLY_SERVICES="conduit-tunnel conduit-ntfy conduit-nginx conduit-brief conduit-crond"
```

**Step 3: Syntax check**

Run: `bash -n scripts/healthcheck.sh && bash -n scripts/watchdog.sh && echo OK`
Expected: `OK`

**Step 4: Commit**

```bash
git add scripts/healthcheck.sh scripts/watchdog.sh
git commit -m "remove dashboard refs from healthcheck and watchdog"
```

---

## Task 4: Update cloudflared config with all domain routes

**Files:**
- Modify: `cloudflared/config.yml`

**Step 1: Replace config.yml with complete routing**

```yaml
# Cloudflared tunnel config for tablet deployment.
# tunnel and credentials-file are populated during setup.
# Run: cloudflared tunnel login && cloudflared tunnel create conduit-tablet

tunnel: TUNNEL_ID_HERE
credentials-file: /data/data/com.termux/files/home/.cloudflared/TUNNEL_ID_HERE.json

ingress:
  - hostname: conduit.josephloftus.com
    service: http://localhost:8080
  - hostname: steady.josephloftus.com
    service: http://localhost:8090
  - hostname: brief.josephloftus.com
    service: http://localhost:5050
  - hostname: ntfy.josephloftus.com
    service: http://localhost:2586
  - service: http_status:404
```

Port reference:
- 8080 = conduit-server (FastAPI)
- 8090 = nginx (spectre frontend + proxy to backend:8000)
- 5050 = morning-brief (Flask)
- 2586 = ntfy

**Step 2: Commit**

```bash
git add cloudflared/config.yml
git commit -m "add steady and brief domain routes to cloudflared config"
```

---

## Task 5: Create bootstrap-tablet.sh

**Files:**
- Create: `bootstrap-tablet.sh` (repo root)
- Delete: `setup.sh` (old bootstrap)

**Step 1: Delete old setup.sh**

```bash
git rm setup.sh
```

**Step 2: Create bootstrap-tablet.sh**

This is the v3 idempotent bootstrap from the playbook, modified for:
- Only clone PUBLIC repos in section 4 (conduit-server, conduit-tablet)
- Private repos (spectre, morning-brief) are NOT cloned here — they come via rsync in Stage 1.5
- Section 7 (web UI build) uses `NODE_OPTIONS=--max_old_space_size=512` for 4GB device
- Section 10 references the updated setup-runit.sh (8 services, no dashboard)

Full script content: use the bootstrap-tablet.sh from `~/Downloads/tablet-deployment-v3.md` (sections 1-14) with these modifications to section 4:

```bash
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
```

And modify section 7 for memory safety:
```bash
# ── SECTION 7: Web UI Build ──
if ! stage_done 7; then
  echo ">>> Stage 7: Building web UI..."
  cd ~/conduit/web
  npm install 2>&1 | tee -a "$LOG_FILE"
  NODE_OPTIONS=--max_old_space_size=512 npm run build 2>&1 | tee -a "$LOG_FILE"
  mark_done 7
fi
```

**Step 3: Syntax check**

Run: `bash -n bootstrap-tablet.sh`
Expected: no output

**Step 4: Commit**

```bash
git add bootstrap-tablet.sh
git commit -m "add v3 idempotent bootstrap, remove old setup.sh"
```

---

## Task 6: Delete deploy-fresh.sh

**Files:**
- Delete: `scripts/deploy-fresh.sh`

**Step 1: Remove the old laptop-side deploy script**

```bash
git rm scripts/deploy-fresh.sh
```

**Step 2: Commit**

```bash
git commit -m "remove v1 deploy-fresh.sh (replaced by v3 bootstrap + tablet CLI)"
```

---

## Task 7: Push conduit-tablet repo to GitHub

**Step 1: Push all commits**

```bash
cd ~/Projects/conduit-tablet
git push origin main
```

This makes the updated repo available for `git clone` on the tablet.

---

## Task 8: Create ~/bin/tablet CLI on laptop

**Files:**
- Create: `~/bin/tablet`

**Step 1: Create the tablet CLI**

Use the `tablet` script from the v3 playbook (`~/Downloads/tablet-deployment-v3.md` section 0F) with these modifications:
- Remove `conduit-dashboard` from all service lists
- Update the `update` command to also pull conduit-tablet repo
- Add `rsync-private` command for pushing spectre + morning-brief

Add this command to the case statement:
```bash
  rsync-private)
    echo "Pushing private repos to tablet..."
    rsync -avz --delete --exclude='.git' --exclude='node_modules' --exclude='__pycache__' --exclude='.venv' --exclude='*.pyc' \
      -e "ssh -p 8022" ~/Projects/spectre/ joseph@$TABLET_IP:~/spectre/
    rsync -avz --delete --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
      -e "ssh -p 8022" ~/Projects/morning-brief/ joseph@$TABLET_IP:~/morning-brief/
    echo "Done. You may need to: tablet restart conduit-spectre conduit-brief"
    ;;
```

**Step 2: Make executable**

```bash
chmod +x ~/bin/tablet
```

**Step 3: Verify it's in PATH**

```bash
which tablet
tablet help
```

Expected: shows the help text

---

## Task 9: Execute Stage 0 — ADB Hardening + Push Files

**This is manual execution from the laptop. Commands from v3 playbook section 0A + 0E.**

**Step 1: Verify ADB connection**

```bash
adb devices
```
Expected: tablet serial number listed

**Step 2: Run Android hardening**

```bash
adb shell settings put global settings_enable_monitor_phantom_procs false
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
adb shell settings get global settings_enable_monitor_phantom_procs
# Should return: 0

adb shell cmd deviceidle whitelist +com.termux
adb shell cmd appops set com.termux RUN_IN_BACKGROUND allow
adb shell cmd appops set com.termux RUN_ANY_IN_BACKGROUND allow
adb shell cmd deviceidle whitelist +com.termux.boot
adb shell cmd deviceidle whitelist +com.termux.api
```

**Step 3: Push files via ADB**

```bash
adb push ~/Projects/conduit-server/server/.env /sdcard/conduit-env
adb push ~/Projects/conduit-tablet/bootstrap-tablet.sh /sdcard/bootstrap-tablet.sh
```

---

## Task 10: Execute Stage 1 — Bootstrap on Tablet Screen

**This runs on the tablet itself, in the Termux app. NOT over SSH.**

**Step 1: Copy bootstrap from /sdcard and run**

```bash
cp /sdcard/bootstrap-tablet.sh ~/bootstrap-tablet.sh
chmod +x ~/bootstrap-tablet.sh
bash ~/bootstrap-tablet.sh
```

**Step 2: After section 9 completes (termux-services installed)**

Close Termux completely (swipe away), reopen, then:
```bash
bash ~/bootstrap-tablet.sh
```

**Step 3: Section 13 — Cloudflared tunnel**

Interactive step. A URL will appear — open it in a browser to authenticate.
After authenticating, note the tunnel ID and update `~/.cloudflared/config.yml` with it.

**Step 4: Verify bootstrap completed**

```bash
cat ~/.bootstrap-stage
# Should show: 14
```

---

## Task 11: Execute Stage 1.5 — Rsync Private Repos + Install Deps

**From laptop, SSH is now alive.**

**Step 1: Verify SSH**

```bash
tablet ping
```
Expected: `SSH alive` + `Conduit alive`

**Step 2: Push private repos**

```bash
tablet rsync-private
```

**Step 3: Install spectre dependencies on tablet**

```bash
tablet ssh "cd ~/spectre && pip install -r backend/requirements.txt --break-system-packages"
tablet ssh "cd ~/spectre/frontend && npm install && npm run build"
```

**Step 4: Install morning-brief dependencies on tablet**

```bash
tablet ssh "cd ~/morning-brief && pip install flask apscheduler requests --break-system-packages"
```

**Step 5: Create tablet-specific spectre nginx config**

The spectre nginx config has laptop-specific paths. Create a tablet version:

```bash
tablet ssh "sed -i 's|/home/joseph/Documents/spectre|/data/data/com.termux/files/home/spectre|g; s|/etc/nginx/mime.types|/data/data/com.termux/files/usr/etc/nginx/mime.types|g' ~/spectre/nginx/spectre.conf"
tablet ssh "mkdir -p ~/spectre/nginx/logs"
```

**Step 6: Restart spectre/nginx/brief services**

```bash
tablet restart conduit-spectre
tablet restart conduit-nginx
tablet restart conduit-brief
```

---

## Task 12: Execute Stage 2 — Full Verification

**Step 1: Full status check**

```bash
tablet status
```
Expected: all 8 services `run:` + 3 HTTP checks `UP`

**Step 2: External domain checks**

```bash
curl -s https://conduit.josephloftus.com/api/health
curl -s https://steady.josephloftus.com
curl -s https://brief.josephloftus.com
curl -s https://ntfy.josephloftus.com
```

**Step 3: Run watchdog**

```bash
tablet watchdog
```
Expected: no failures in state.json

**Step 4: Check resource usage**

```bash
tablet ssh "free -h"
```
Expected: ~2GB free

---

## Port Reference

| Port | Service | Health Endpoint |
|------|---------|----------------|
| 8080 | conduit-server (FastAPI) | /api/health |
| 8090 | nginx (spectre frontend) | / |
| 8000 | conduit-spectre (uvicorn) | /api/health |
| 8889 | conduit-search (Brave proxy) | /health |
| 5050 | conduit-brief (Flask) | / |
| 2586 | conduit-ntfy | — |
| 8022 | sshd | — |
