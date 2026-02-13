# Conduit Tablet Setup Guide

How to get Conduit running on an Android tablet with Termux.

---

## Prerequisites

**Apps to install from F-Droid (NOT Play Store):**
- Termux
- Termux:Boot
- Termux:API

**Apps to install from Play Store:**
- Tailscale
- RustDesk
- Microsoft OneDrive (if not already installed)

**From your laptop, you'll need:**
- Your Conduit git repo URL
- Your SSH public key (`cat ~/.ssh/id_ed25519.pub`)
- Your `server/.env` file contents (API keys)

---

## Setup Steps

### 1. Install apps

Install all prerequisite apps listed above. Open Termux once to let it initialize its environment.

### 2. Clone the deployment kit

```bash
pkg install git
git clone <conduit-tablet-repo-url> ~/conduit-tablet
```

### 3. Run setup

```bash
bash ~/conduit-tablet/setup.sh
```

This is interactive. It will:
- Update and install Termux packages
- Prompt for storage access (grant it when the Android dialog appears)
- Ask for your Conduit git repo URL
- Install Python dependencies
- Apply tablet-specific config and patches
- Create the `.env` template
- Ask for your SSH public key
- Set up auto-start on boot

### 4. Fill in API keys

```bash
nano ~/conduit/server/.env
```

Copy the values from your laptop's `server/.env`. All the key names are the same.

### 5. Set up the cloudflared tunnel

```bash
# Authenticate with Cloudflare
cloudflared tunnel login

# Create a new tunnel
cloudflared tunnel create conduit-tablet

# Note the tunnel ID from the output, then edit the config:
nano ~/.cloudflared/config.yml
```

Replace `TUNNEL_ID_HERE` with your actual tunnel ID in both places (the `tunnel:` line and the `credentials-file:` path).

Then route DNS to the new tunnel:

```bash
cloudflared tunnel route dns conduit-tablet conduit.josephloftus.com
```

**Important:** Before routing DNS, disable the laptop's tunnel first so the DNS record doesn't conflict:

```bash
# On laptop:
sudo systemctl stop cloudflared
sudo systemctl disable cloudflared
```

### 6. Copy work files from laptop

```bash
# From your laptop (replace TABLET_IP with the tablet's Tailscale IP or local IP):
scp -P 8022 -r ~/Documents/Work/* TABLET_IP:~/documents/work/
```

### 7. Start the server

```bash
~/conduit-tablet/scripts/start.sh
```

This launches a tmux session called `conduit` with four windows:
- `server` — the Conduit Python server (port 8080)
- `tunnel` — cloudflared (forwards traffic from conduit.josephloftus.com)
- `search` — Brave-to-SearXNG search proxy (port 8889)
- `shell` — a free terminal for ad hoc commands

### 8. Verify

```bash
~/conduit-tablet/scripts/status.sh
```

All services should show UP/RUNNING.

### 9. Configure Android settings

Do these manually in the tablet's Settings app:

- **Developer Options > Stay Awake** — keeps screen on while charging (prevents Termux from sleeping)
- **Battery > Termux > Unrestricted** — disables battery optimization so Android won't kill Termux
- **Lock Termux in recent apps** — long-press Termux in the app switcher and tap Lock
- **System > Software Update > Auto-update > Off** — prevents surprise reboots

### 10. Set up Tailscale

Open the Tailscale app and sign in. The tablet gets a stable IP on your tailnet.

From that point on, you can SSH from anywhere:

```bash
ssh TABLET_TAILSCALE_IP -p 8022
```

---

## Day-to-Day Operations

| Task | Command |
|------|---------|
| Check status | `~/conduit-tablet/scripts/status.sh` |
| View server | `tmux attach -t conduit` |
| Stop server | `~/conduit-tablet/scripts/stop.sh` |
| Start server | `~/conduit-tablet/scripts/start.sh` |
| Update code | `~/conduit-tablet/scripts/update.sh` |
| View logs | `tail -f ~/conduit-data/logs/server.log` |

---

## Troubleshooting

### Server won't start

- Check `.env` has all required keys: `cat ~/conduit/server/.env`
- Check Python deps: `pip install -r ~/conduit/server/requirements.txt`
- Try running manually: `cd ~/conduit && python -m server`

### Cloudflared connection refused

- Is the server actually running? `curl http://localhost:8080/api/health`
- Check tunnel config: `cat ~/.cloudflared/config.yml`
- Run tunnel manually: `cloudflared tunnel --config ~/.cloudflared/config.yml run`

### Termux killed by Android

- Verify battery optimization is disabled for Termux
- Check wake lock: `termux-wake-lock`
- Make sure Termux:Boot is installed and has been opened at least once

### Storage permission issues

- Re-run: `termux-setup-storage`
- Check: `ls ~/storage/shared/` should show Android shared storage directories

### Search not working

- Check proxy health: `curl http://localhost:8889/health`
- Check API key: `echo $BRAVE_SEARCH_API_KEY`
- Run proxy manually: `cd ~/conduit-tablet/search-proxy && python proxy.py`

### Can't SSH to tablet

- Is sshd running? Run `sshd` to start it if not
- Is Tailscale connected? `tailscale status`
- Correct port? Termux SSH uses **8022**, not 22
