# 710Q Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate all Koji and Suri services to the 710Q, set up laptop as NFS share, retire tablet Koji deployment.

**Architecture:** Two independent Docker Compose stacks (Koji + Suri) on Ubuntu Server 24.04, public access via Cloudflare tunnel, private access via Tailscale, media on 4TB USB, secondary media via NFS from laptop.

**Tech Stack:** Docker, Docker Compose, Cloudflared, Tailscale, Nginx, FastAPI, Python 3.13, Node 20

**Target:** `koji@192.168.1.183` (SSH key auth already configured)

---

## Task 1: Base System Setup

**What:** Install Docker, set static IP, configure timezone, basic hardening.

**Step 1: Install Docker Engine**

```bash
ssh koji@192.168.1.183 'sudo apt-get update && sudo apt-get install -y ca-certificates curl && sudo install -m 0755 -d /etc/apt/keyrings && sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && sudo chmod a+r /etc/apt/keyrings/docker.asc && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
```

**Step 2: Add koji user to docker group**

```bash
ssh koji@192.168.1.183 'sudo usermod -aG docker koji'
```

Log out and back in for group to take effect.

**Step 3: Verify Docker**

```bash
ssh koji@192.168.1.183 'docker run --rm hello-world'
```

Expected: "Hello from Docker!"

**Step 4: Set static IP via netplan**

```bash
ssh koji@192.168.1.183 'cat /etc/netplan/*.yaml'
```

Then create/edit the netplan config to set static IP 192.168.1.183:

```yaml
# /etc/netplan/01-static.yaml
network:
  version: 2
  ethernets:
    enp0s31f6:
      dhcp4: no
      addresses:
        - 192.168.1.183/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

Apply: `sudo netplan apply`

**Step 5: Set timezone**

```bash
ssh koji@192.168.1.183 'sudo timedatectl set-timezone America/New_York'
```

**Step 6: Install useful packages**

```bash
ssh koji@192.168.1.183 'sudo apt-get install -y htop git nfs-common ntfs-3g'
```

**Step 7: Verify**

Run: `ssh koji@192.168.1.183 'docker --version && timedatectl && ip a show enp0s31f6 | grep inet'`

---

## Task 2: Mount 4TB USB Drive

**What:** Mount the 4TB NTFS drive at `/mnt/media` with auto-mount on boot.

**Step 1: Identify the drive**

```bash
ssh koji@192.168.1.183 'sudo blkid /dev/sda2'
```

Note the UUID.

**Step 2: Create mount point and mount**

```bash
ssh koji@192.168.1.183 'sudo mkdir -p /mnt/media && sudo mount -t ntfs-3g /dev/sda2 /mnt/media -o uid=1000,gid=1000,dmask=022,fmask=133'
```

**Step 3: Add to fstab for auto-mount**

Using the UUID from step 1:

```bash
ssh koji@192.168.1.183 'echo "UUID=<THE_UUID> /mnt/media ntfs-3g uid=1000,gid=1000,dmask=022,fmask=133,nofail 0 0" | sudo tee -a /etc/fstab'
```

The `nofail` flag prevents boot failure if the USB isn't plugged in.

**Step 4: Verify**

```bash
ssh koji@192.168.1.183 'df -h /mnt/media && ls /mnt/media'
```

Expected: 4TB drive mounted, media files visible.

---

## Task 3: Install Tailscale

**What:** Install Tailscale for private remote access to all services.

**Step 1: Install**

```bash
ssh koji@192.168.1.183 'curl -fsSL https://tailscale.com/install.sh | sh'
```

**Step 2: Authenticate**

```bash
ssh koji@192.168.1.183 'sudo tailscale up'
```

This will print a URL — Joseph opens it in browser to authenticate. Note the Tailscale IP assigned.

**Step 3: Verify**

```bash
ssh koji@192.168.1.183 'tailscale status'
```

Expected: Shows as connected, lists other devices (laptop, tablet).

**Step 4: Record Tailscale IP**

Note the 100.x.x.x IP for the 710Q — this is the address for Tier 2 (Tailscale) service access.

---

## Task 4: Create Directory Structure

**What:** Set up the project layout on the 710Q.

**Step 1: Create directories**

```bash
ssh koji@192.168.1.183 'mkdir -p ~/koji ~/suri ~/services/cloudflared ~/services/ntfy'
```

**Step 2: Clone Koji server repo**

```bash
ssh koji@192.168.1.183 'git clone https://github.com/josephloftus/koji ~/koji/server || echo "need correct repo URL"'
```

If the repo is on git.josephloftus.com:

```bash
ssh koji@192.168.1.183 'git clone https://git.josephloftus.com/joseph/koji ~/koji/server'
```

**Step 3: Copy search-proxy from koji-tablet**

From laptop:
```bash
scp -r /home/joseph/Projects/koji-tablet/search-proxy/ koji@192.168.1.183:~/koji/search-proxy/
```

**Step 4: Rsync private repos (spectre, morning-brief)**

```bash
rsync -avz --exclude='.venv' --exclude='__pycache__' --exclude='node_modules' /home/joseph/Projects/spectre/ koji@192.168.1.183:~/koji/spectre/
rsync -avz --exclude='.venv' --exclude='__pycache__' /home/joseph/Projects/morning-brief/ koji@192.168.1.183:~/koji/morning-brief/
```

**Step 5: Copy env files and config**

```bash
scp /home/joseph/Projects/koji-server/server/.env koji@192.168.1.183:~/koji/.env
scp /home/joseph/Projects/koji-tablet/config.yaml koji@192.168.1.183:~/koji/config.yaml
```

**Step 6: Copy Suri project**

```bash
rsync -avz --exclude='data' --exclude='.venv' --exclude='__pycache__' --exclude='node_modules' /home/joseph/Projects/suri/ koji@192.168.1.183:~/suri/
```

Then copy Suri data separately (service configs, not media):

```bash
rsync -avz /home/joseph/Projects/suri/data/ koji@192.168.1.183:~/suri/data/
```

**Step 7: Copy Suri config and env**

```bash
scp /home/joseph/Projects/suri/.env koji@192.168.1.183:~/suri/.env
scp /home/joseph/.config/suri/config.toml koji@192.168.1.183:~/suri/config.toml
```

**Step 8: Verify structure**

```bash
ssh koji@192.168.1.183 'find ~/koji ~/suri ~/services -maxdepth 2 -type d | sort'
```

---

## Task 5: Write Koji Dockerfiles

**What:** Create Dockerfiles for koji-server, search-proxy, spectre, and morning-brief. ntfy and cloudflared use official images. Spectre already has Dockerfiles.

**Step 1: Create koji-server Dockerfile**

Write to `koji@192.168.1.183:~/koji/Dockerfile.server`:

```dockerfile
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ git curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server/ ./server/

# Build web UI if source exists
COPY web/ ./web/
RUN if [ -f web/package.json ]; then \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    cd web && npm ci && npm run build && \
    rm -rf node_modules && \
    apt-get purge -y nodejs && apt-get autoremove -y; \
    fi

ENV PYTHONUNBUFFERED=1
EXPOSE 8080

CMD ["python", "-m", "server"]
```

**Step 2: Create search-proxy Dockerfile**

Write to `koji@192.168.1.183:~/koji/Dockerfile.search`:

```dockerfile
FROM python:3.13-slim

WORKDIR /app

RUN pip install --no-cache-dir fastapi uvicorn httpx

COPY search-proxy/proxy.py .

ENV PYTHONUNBUFFERED=1
EXPOSE 8889

CMD ["uvicorn", "proxy:app", "--host", "0.0.0.0", "--port", "8889"]
```

**Step 3: Create morning-brief Dockerfile**

Write to `koji@192.168.1.183:~/koji/Dockerfile.brief`:

```dockerfile
FROM python:3.13-slim

WORKDIR /app

RUN pip install --no-cache-dir flask requests apscheduler jinja2

COPY morning-brief/ .

ENV PYTHONUNBUFFERED=1
EXPOSE 5050

CMD ["python", "brief_server.py"]
```

**Step 4: Verify Dockerfiles exist**

```bash
ssh koji@192.168.1.183 'ls -la ~/koji/Dockerfile.*'
```

---

## Task 6: Write Koji docker-compose.yml

**What:** Create the Koji stack compose file with all 7 services.

Write to `koji@192.168.1.183:~/koji/docker-compose.yml`:

```yaml
services:
  koji-server:
    build:
      context: .
      dockerfile: Dockerfile.server
    container_name: koji-server
    env_file: .env
    volumes:
      - ./config.yaml:/app/server/config.yaml:ro
      - ./data:/app/server/data
      - koji-db:/app/server/db
    ports:
      - "8080:8080"
    restart: unless-stopped
    networks:
      - koji

  koji-search:
    build:
      context: .
      dockerfile: Dockerfile.search
    container_name: koji-search
    env_file: .env
    ports:
      - "8889:8889"
    restart: unless-stopped
    networks:
      - koji

  koji-spectre:
    build:
      context: ./spectre/backend
    container_name: koji-spectre
    env_file: .env
    environment:
      - SPECTRE_DATA_DIR=/app/data
    volumes:
      - spectre-data:/app/data
    ports:
      - "8000:8000"
    restart: unless-stopped
    networks:
      - koji

  koji-nginx:
    image: nginx:alpine
    container_name: koji-nginx
    volumes:
      - ./spectre/nginx/spectre.conf:/etc/nginx/conf.d/default.conf:ro
      - ./spectre/frontend/dist:/usr/share/nginx/html/spectre:ro
      - ./morning-brief/output:/usr/share/nginx/html/brief:ro
      - ./morning-brief/static:/usr/share/nginx/html/brief/static:ro
    ports:
      - "8090:8090"
    restart: unless-stopped
    networks:
      - koji

  koji-brief:
    build:
      context: .
      dockerfile: Dockerfile.brief
    container_name: koji-brief
    volumes:
      - ./morning-brief/output:/app/output
      - ./morning-brief/health_data:/app/health_data
    ports:
      - "5050:5050"
    restart: unless-stopped
    networks:
      - koji

  koji-ntfy:
    image: binwiederhier/ntfy
    container_name: koji-ntfy
    command: serve
    volumes:
      - ../services/ntfy:/var/cache/ntfy
    ports:
      - "2586:80"
    environment:
      - TZ=America/New_York
      - NTFY_BASE_URL=https://ntfy.josephloftus.com
    restart: unless-stopped
    networks:
      - koji

  koji-tunnel:
    image: cloudflare/cloudflared:latest
    container_name: koji-tunnel
    command: tunnel run
    volumes:
      - ../services/cloudflared:/etc/cloudflared:ro
    environment:
      - TUNNEL_CONFIG=/etc/cloudflared/config.yml
    restart: unless-stopped
    network_mode: host

volumes:
  koji-db:
  spectre-data:

networks:
  koji:
    name: koji
```

**Verify:** `ssh koji@192.168.1.183 'cat ~/koji/docker-compose.yml'`

---

## Task 7: Write Suri docker-compose.yml (710Q version)

**What:** Adapt the existing Suri compose file for 710Q paths. Key changes: qBit port 8080→8081, media paths use /mnt/media, secondary media from /mnt/laptop.

Write to `koji@192.168.1.183:~/suri/docker-compose.yml`:

The existing compose file needs these changes from the laptop version:

1. **qBittorrent port**: `8080:8080` → `8081:8080` (on gluetun, avoids koji-server conflict)
2. **Media paths**: `/mnt/media/media` → `/mnt/media` (direct mount, no nested media/)
3. **Secondary media**: `/home/joseph/Media` → `/mnt/laptop` (NFS from laptop)
4. **Navidrome music**: `/home/joseph/Media/Music` → `/mnt/media/Music` (or wherever music lives on the 4TB)
5. **Sieve config**: `~/.config/suri` → `/home/koji/suri` (config.toml location)
6. **Sieve host mount**: `/:/host:ro` stays (for filesystem introspection)

Check the actual media directory structure on the 4TB before writing:

```bash
ssh koji@192.168.1.183 'ls /mnt/media/ | head -20'
```

Then adjust paths accordingly and write the compose file. Keep container names as `suri-*` prefix.

**Verify:** `ssh koji@192.168.1.183 'docker compose -f ~/suri/docker-compose.yml config --quiet'`

---

## Task 8: Set Up Cloudflare Tunnel

**What:** Create a new Cloudflare tunnel on the 710Q and route the 4 domains to it.

**Step 1: Install cloudflared on host (for initial auth)**

```bash
ssh koji@192.168.1.183 'sudo mkdir -p --mode=0755 /usr/share/keyrings && curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list && sudo apt-get update && sudo apt-get install -y cloudflared'
```

**Step 2: Authenticate**

```bash
ssh koji@192.168.1.183 'cloudflared tunnel login'
```

Opens a URL — Joseph authenticates in browser.

**Step 3: Delete old tunnel (from tablet)**

```bash
ssh koji@192.168.1.183 'cloudflared tunnel delete koji-tablet'
```

Or keep it and create a new one — the DNS routing is what matters.

**Step 4: Create new tunnel**

```bash
ssh koji@192.168.1.183 'cloudflared tunnel create koji-server'
```

Note the tunnel ID.

**Step 5: Write tunnel config**

Write to `~/services/cloudflared/config.yml`:

```yaml
tunnel: <TUNNEL_ID>
credentials-file: /etc/cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: conduit.josephloftus.com
    service: http://localhost:8080
  - hostname: status.josephloftus.com
    service: http://localhost:8080
  - hostname: steady.josephloftus.com
    service: http://localhost:8090
  - hostname: brief.josephloftus.com
    service: http://localhost:8090
  - hostname: ntfy.josephloftus.com
    service: http://localhost:2586
  - service: http_status:404
```

**Step 6: Copy tunnel credentials**

```bash
ssh koji@192.168.1.183 'cp ~/.cloudflared/<TUNNEL_ID>.json ~/services/cloudflared/'
```

**Step 7: Route DNS**

```bash
ssh koji@192.168.1.183 'cloudflared tunnel route dns --overwrite-dns koji-server conduit.josephloftus.com && cloudflared tunnel route dns --overwrite-dns koji-server status.josephloftus.com && cloudflared tunnel route dns --overwrite-dns koji-server steady.josephloftus.com && cloudflared tunnel route dns --overwrite-dns koji-server brief.josephloftus.com && cloudflared tunnel route dns --overwrite-dns koji-server ntfy.josephloftus.com'
```

**Step 8: Verify tunnel config**

```bash
ssh koji@192.168.1.183 'cloudflared tunnel info koji-server'
```

---

## Task 9: Build and Launch Koji Stack

**What:** Build images and bring up the Koji stack.

**Step 1: Build spectre frontend first (needed for nginx)**

```bash
ssh koji@192.168.1.183 'cd ~/koji/spectre/frontend && docker run --rm -v $(pwd):/app -w /app node:20-alpine sh -c "npm ci && npm run build"'
```

**Step 2: Build and start Koji stack**

```bash
ssh koji@192.168.1.183 'cd ~/koji && docker compose build && docker compose up -d'
```

**Step 3: Check containers**

```bash
ssh koji@192.168.1.183 'cd ~/koji && docker compose ps'
```

Expected: All 7 containers running.

**Step 4: Check logs for errors**

```bash
ssh koji@192.168.1.183 'cd ~/koji && docker compose logs --tail=20'
```

**Step 5: Verify health endpoints**

```bash
ssh koji@192.168.1.183 'curl -s http://localhost:8080/api/health && echo && curl -s http://localhost:8889/health && echo && curl -s http://localhost:8000/api/health'
```

**Step 6: Verify public domains (after tunnel is up)**

From laptop:
```bash
curl -s https://conduit.josephloftus.com/api/health
curl -s https://ntfy.josephloftus.com/v1/health
```

**Step 7: Fix issues**

If any container fails, check logs: `docker compose logs <service-name> --tail=50`

Common issues:
- Missing env vars → check `.env` has all required keys
- Config paths → verify volume mounts match what the app expects
- Port conflicts → check `ss -tlnp` on host
- Build failures → check Dockerfile, requirements.txt

---

## Task 10: Launch Suri Stack

**What:** Bring up the Suri media stack.

**Step 1: Verify media mount**

```bash
ssh koji@192.168.1.183 'ls /mnt/media && df -h /mnt/media'
```

**Step 2: Start Suri stack**

```bash
ssh koji@192.168.1.183 'cd ~/suri && docker compose up -d'
```

Note: Most services use prebuilt images, only sieve and sieve-atv need building.

**Step 3: Check containers**

```bash
ssh koji@192.168.1.183 'cd ~/suri && docker compose ps'
```

Expected: 14-15 containers running (sieve-atv may restart if Apple TV is off — that's OK).

**Step 4: Verify key services**

```bash
ssh koji@192.168.1.183 'curl -s http://localhost:8096 | head -5 && echo "---jellyfin OK" && curl -s http://localhost:8989/api/v3/system/status?apiKey=0dd6ceeecd8b47cda01536c775fb6dcd | head -5 && echo "---sonarr OK"'
```

**Step 5: Check VPN is working**

```bash
ssh koji@192.168.1.183 'docker exec suri-gluetun wget -qO- ifconfig.me'
```

Expected: A Mullvad exit IP, NOT your home IP.

**Step 6: Verify qBit WebUI on new port**

From laptop: `curl -s http://192.168.1.183:8081` — should return qBit login page.

---

## Task 11: Laptop NFS Server Setup

**What:** Export laptop media storage as read-only NFS share for the 710Q.

**Step 1: Install NFS server on laptop**

```bash
sudo apt-get install -y nfs-kernel-server
```

**Step 2: Create export**

Add to `/etc/exports`:

```
/home/joseph/Media 192.168.1.183(ro,sync,no_subtree_check,no_root_squash)
```

If also sharing `/mnt/storage`:

```
/mnt/storage 192.168.1.183(ro,sync,no_subtree_check,no_root_squash)
```

**Step 3: Apply exports**

```bash
sudo exportfs -ra && sudo systemctl restart nfs-kernel-server
```

**Step 4: Mount on 710Q**

```bash
ssh koji@192.168.1.183 'sudo mkdir -p /mnt/laptop && sudo mount -t nfs 192.168.1.166:/home/joseph/Media /mnt/laptop -o ro,soft,timeo=30'
```

The `soft,timeo=30` options prevent hangs if the laptop is asleep/off.

**Step 5: Add to 710Q fstab**

```bash
ssh koji@192.168.1.183 'echo "192.168.1.166:/home/joseph/Media /mnt/laptop nfs ro,soft,timeo=30,nofail,x-systemd.automount 0 0" | sudo tee -a /etc/fstab'
```

The `x-systemd.automount` mounts on first access instead of at boot, so it won't block boot if laptop is off.

**Step 6: Verify**

```bash
ssh koji@192.168.1.183 'ls /mnt/laptop'
```

---

## Task 12: Laptop Power Management

**What:** Configure laptop for minimal power consumption when idle.

**Step 1: Install TLP**

```bash
sudo apt-get install -y tlp powertop
```

**Step 2: Enable and start TLP**

```bash
sudo systemctl enable tlp && sudo systemctl start tlp
```

**Step 3: Run powertop auto-tune**

```bash
sudo powertop --auto-tune
```

**Step 4: Keep lid-close from suspending (if used as headless NFS)**

Check `/etc/systemd/logind.conf`:

```
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
```

Then: `sudo systemctl restart systemd-logind`

---

## Task 13: Stop Suri on Laptop

**What:** Once Suri is verified working on 710Q, stop it on the laptop.

**Step 1: Stop Suri containers on laptop**

```bash
cd /home/joseph/Projects/suri && docker compose down
```

**Step 2: Verify nothing is running**

```bash
docker ps --filter "name=suri-" --format "{{.Names}}"
```

Expected: No output.

**Step 3: Optionally prune old images**

```bash
docker image prune -a --filter "label=com.docker.compose.project=suri"
```

---

## Task 14: Retire Tablet Koji Services

**What:** Stop all Koji services on the tablet. CUPS stays.

**Step 1: SSH into tablet and stop services**

```bash
ssh -p 8022 joseph@100.115.173.115 'sv stop koji-server koji-tunnel koji-search koji-ntfy koji-spectre koji-nginx koji-brief koji-crond'
```

**Step 2: Disable services from runit**

```bash
ssh -p 8022 joseph@100.115.173.115 'rm -f $PREFIX/var/service/koji-*'
```

**Step 3: Disable boot script**

```bash
ssh -p 8022 joseph@100.115.173.115 'rm -f ~/.termux/boot/koji-start'
```

**Step 4: Disable watchdog cron**

```bash
ssh -p 8022 joseph@100.115.173.115 'crontab -r || echo "no crontab"'
```

**Step 5: Verify tablet is clean**

```bash
ssh -p 8022 joseph@100.115.173.115 'sv status koji-* 2>&1; echo "---"; crontab -l 2>&1'
```

Expected: All services gone, no crontab.

---

## Task 15: Update Laptop Management Script

**What:** Create `~/bin/server` script (replaces `~/bin/tablet`) for managing the 710Q.

Write to `/home/joseph/bin/server`:

```bash
#!/bin/bash
HOST="koji@192.168.1.183"

case "${1:-status}" in
  status)
    ssh $HOST 'echo "=== KOJI ===" && cd ~/koji && docker compose ps --format "table {{.Name}}\t{{.Status}}" && echo && echo "=== SURI ===" && cd ~/suri && docker compose ps --format "table {{.Name}}\t{{.Status}}" && echo && echo "=== SYSTEM ===" && free -h | head -2 && df -h / /mnt/media | tail -2'
    ;;
  ssh)
    shift; ssh $HOST "$@"
    ;;
  logs)
    shift
    stack="${1:-koji}"; shift
    ssh $HOST "cd ~/$stack && docker compose logs --tail=50 --follow $*"
    ;;
  restart)
    shift
    stack="${1:-koji}"; shift
    ssh $HOST "cd ~/$stack && docker compose restart $*"
    ;;
  update-koji)
    ssh $HOST 'cd ~/koji/server && git pull'
    ssh $HOST 'cd ~/koji && docker compose build && docker compose up -d'
    ;;
  rsync-private)
    rsync -avz --exclude='.venv' --exclude='__pycache__' --exclude='node_modules' /home/joseph/Projects/spectre/ $HOST:~/koji/spectre/
    rsync -avz --exclude='.venv' --exclude='__pycache__' /home/joseph/Projects/morning-brief/ $HOST:~/koji/morning-brief/
    ssh $HOST 'cd ~/koji && docker compose build koji-spectre koji-brief && docker compose up -d koji-spectre koji-brief'
    ;;
  backup)
    mkdir -p ~/backups/koji
    rsync -avz $HOST:~/koji/.env ~/backups/koji/
    rsync -avz $HOST:~/koji/config.yaml ~/backups/koji/
    rsync -avz $HOST:~/services/cloudflared/ ~/backups/koji/cloudflared/
    echo "Backed up to ~/backups/koji/"
    ;;
  *)
    echo "Usage: server {status|ssh|logs|restart|update-koji|rsync-private|backup} [args...]"
    echo ""
    echo "  status              Show all service status"
    echo "  ssh [cmd]           SSH into server"
    echo "  logs <stack> [svc]  Tail logs (stack: koji or suri)"
    echo "  restart <stack> [s] Restart services"
    echo "  update-koji         Git pull + rebuild koji"
    echo "  rsync-private       Push spectre + brief, rebuild"
    echo "  backup              Backup env/config/creds to laptop"
    ;;
esac
```

Then: `chmod +x ~/bin/server`

---

## Task 16: Monitoring & Watchdog

**What:** Set up basic health monitoring via cron on the 710Q.

**Step 1: Create watchdog script**

Write to `koji@192.168.1.183:~/watchdog.sh`:

```bash
#!/bin/bash
# Simple health watchdog — checks critical services, alerts via ntfy

NTFY_URL="http://localhost:2586"
NTFY_TOPIC="koji-alerts"
FAILURES=""

check() {
    local name="$1" url="$2"
    if ! curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
        FAILURES="$FAILURES $name"
    fi
}

check "koji-server" "http://localhost:8080/api/health"
check "spectre" "http://localhost:8000/api/health"
check "search" "http://localhost:8889/health"
check "jellyfin" "http://localhost:8096/health"

if [ -n "$FAILURES" ]; then
    curl -sf -d "Services down:$FAILURES" \
        -H "Title: Koji Alert" \
        -H "Priority: high" \
        "$NTFY_URL/$NTFY_TOPIC" >/dev/null 2>&1
fi
```

**Step 2: Make executable and add to cron**

```bash
ssh koji@192.168.1.183 'chmod +x ~/watchdog.sh && (crontab -l 2>/dev/null; echo "*/5 * * * * /home/koji/watchdog.sh") | crontab -'
```

**Step 3: Verify cron**

```bash
ssh koji@192.168.1.183 'crontab -l'
```

---

## Task 17: Final Verification

**What:** End-to-end verification that everything works.

**Step 1: Check all containers**

```bash
ssh koji@192.168.1.183 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sort'
```

Expected: ~21 containers running (7 Koji + 14 Suri).

**Step 2: Check public domains**

```bash
curl -s https://conduit.josephloftus.com/api/health
curl -s https://steady.josephloftus.com
curl -s https://brief.josephloftus.com
curl -s https://ntfy.josephloftus.com/v1/health
```

**Step 3: Check Tailscale access**

Using the 710Q's Tailscale IP:

```bash
curl -s http://<TAILSCALE_IP>:8096  # Jellyfin
curl -s http://<TAILSCALE_IP>:8100  # Sieve
curl -s http://<TAILSCALE_IP>:5055  # Jellyseerr
```

**Step 4: Check VPN isolation**

```bash
ssh koji@192.168.1.183 'docker exec suri-gluetun wget -qO- ifconfig.me && echo " (VPN)" && curl -s ifconfig.me && echo " (host)"'
```

Expected: Two different IPs — VPN exit vs home IP.

**Step 5: Check media access**

```bash
ssh koji@192.168.1.183 'ls /mnt/media | head -10 && echo "---4TB OK" && ls /mnt/laptop 2>/dev/null | head -5 && echo "---NFS OK"'
```

**Step 6: Run management script**

```bash
~/bin/server status
```

**Step 7: Send test notification**

```bash
curl -d "710Q migration complete" https://ntfy.josephloftus.com/koji-alerts
```

---

## Migration Checklist

- [ ] Task 1: Docker + static IP + base packages
- [ ] Task 2: 4TB USB mounted
- [ ] Task 3: Tailscale installed
- [ ] Task 4: Directory structure + code deployed
- [ ] Task 5: Koji Dockerfiles written
- [ ] Task 6: Koji docker-compose.yml written
- [ ] Task 7: Suri docker-compose.yml adapted
- [ ] Task 8: Cloudflare tunnel configured
- [ ] Task 9: Koji stack running + verified
- [ ] Task 10: Suri stack running + verified
- [ ] Task 11: Laptop NFS server
- [ ] Task 12: Laptop power management
- [ ] Task 13: Suri stopped on laptop
- [ ] Task 14: Tablet Koji services retired
- [ ] Task 15: Management script created
- [ ] Task 16: Watchdog cron
- [ ] Task 17: Final verification
