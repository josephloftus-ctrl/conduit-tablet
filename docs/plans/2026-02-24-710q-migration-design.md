# Koji Server Migration: Tablet → 710Q

**Date**: 2026-02-24
**Status**: Approved

## Overview

Consolidate all services onto the Lenovo IdeaCentre 710Q (Ubuntu Server 24.04 LTS), replacing the tablet as production server and the laptop as Docker host for Suri. The laptop becomes a low-power NFS share and development workstation. The tablet stays as a standalone CUPS print server.

## Hardware: 710Q (koji)

- **CPU**: Intel i5-7400T, 4 cores @ 2.40GHz (x86_64)
- **RAM**: 16GB
- **Storage**: 256GB NVMe SSD (WDC PC SN530) — 215GB free
- **External**: 4TB USB drive (media library)
- **Network**: Gigabit ethernet, 192.168.1.183
- **OS**: Ubuntu Server 24.04.4 LTS
- **KVM**: Unavailable (check BIOS VT-x later)

## Architecture

### Three Independent Boxes

```
710Q (koji) ─── always on, runs everything
  ├── Koji stack (Docker Compose)
  ├── Suri stack (Docker Compose)
  ├── Cloudflare tunnel (4 public domains)
  ├── Tailscale (remote access to all services)
  └── 4TB USB media storage

Laptop (josephPC) ─── low power, dev + NFS
  ├── NFS share (secondary media archive)
  ├── Development workstation
  ├── Mac VM host (KVM)
  └── koji-node (Rust desktop relay)

Tablet (Lenovo-Tab-One) ─── standalone
  └── CUPS print server (USB printer)
```

No dependencies between boxes. Each operates independently.

### Network Access Tiers

**Tier 1 — Public (Cloudflare Tunnel)**

| Domain | Target | Service |
|--------|--------|---------|
| conduit.josephloftus.com | localhost:8080 | koji-server |
| steady.josephloftus.com | localhost:8090 | spectre (nginx) |
| brief.josephloftus.com | localhost:5050 | morning-brief |
| ntfy.josephloftus.com | localhost:2586 | ntfy |

**Tier 2 — Remote Private (Tailscale)**

All Suri services accessible via Tailscale IP:
- Jellyfin (:8096), Navidrome (:4533), Jellyseerr (:5055)
- Sieve dashboard (:8100)
- Sonarr (:8989), Radarr (:7878), Lidarr (:8686), Bazarr (:6767)
- Prowlarr (:9696), qBittorrent (:8081 — remapped from 8080)

**Tier 3 — LAN Only**

- SSH (port 22)
- NFS mount from laptop

### Docker Compose Structure

Two independent stacks, shared Docker network for optional inter-service communication:

```
/home/koji/
├── koji/
│   ├── docker-compose.yml    # Koji services
│   ├── .env                  # API keys, secrets
│   ├── server/               # koji-server code
│   ├── config.yaml           # server config
│   └── data/                 # SQLite DB, logs
├── suri/
│   ├── docker-compose.yml    # Suri services (14 containers)
│   ├── .env                  # Mullvad creds
│   ├── data/                 # Per-service data dirs
│   └── config.toml           # Suri config
└── services/
    ├── cloudflared/          # Tunnel config + creds
    ├── ntfy/                 # Notification server data
    └── tailscale/            # Tailscale state (optional)
```

### Koji Stack — Docker Services

| Container | Image/Build | Port | Purpose |
|-----------|-------------|------|---------|
| koji-server | Build from repo | 8080 | FastAPI AI backend |
| koji-search | Build from search-proxy/ | 8889 | Brave/SearXNG search proxy |
| koji-spectre | Build from spectre/ | 8000 | Inventory operations API |
| koji-nginx | nginx:alpine | 8090 | Reverse proxy (Spectre + Brief frontends) |
| koji-brief | Build from morning-brief/ | 5050 | Daily briefing generator |
| koji-ntfy | binwiederhier/ntfy | 2586 | Push notifications |
| koji-tunnel | cloudflare/cloudflared | — | Cloudflare tunnel |

### Suri Stack — Docker Services

Migrated as-is from laptop docker-compose.yml with path adjustments:

| Container | Port | Purpose |
|-----------|------|---------|
| gluetun | — | Mullvad VPN gateway |
| qbittorrent | 8081 | Torrent client (remapped from 8080) |
| prowlarr | 9696 | Indexer manager |
| sonarr | 8989 | TV series manager |
| radarr | 7878 | Movie manager |
| lidarr | 8686 | Music manager |
| bazarr | 6767 | Subtitle manager |
| jellyfin | 8096 | Video streaming |
| navidrome | 4533 | Music streaming |
| jellyseerr | 5055 | Request interface |
| sieve | 8100 | Recommendation engine |
| sieve-atv | — | Apple TV poller |
| queue-balancer | — | Download queue optimizer |
| vpn-optimizer | — | VPN endpoint rotation |
| audio-remux | — | FFmpeg transcoding |

### Storage Layout

| Mount Point | Device | Filesystem | Purpose |
|-------------|--------|------------|---------|
| / | NVMe (LVM) | ext4 | OS + Docker + service data |
| /mnt/media | 4TB USB | NTFS/ext4 | Primary media library |
| /mnt/laptop | NFS (laptop) | NFS | Secondary media archive |

### Port Map (all services)

| Port | Service | Access |
|------|---------|--------|
| 22 | SSH | LAN |
| 2586 | ntfy | Public |
| 4533 | Navidrome | Tailscale |
| 5050 | Morning Brief | Public |
| 5055 | Jellyseerr | Tailscale |
| 6767 | Bazarr | Tailscale |
| 7878 | Radarr | Tailscale |
| 8000 | Spectre API | Internal |
| 8080 | koji-server | Public |
| 8081 | qBittorrent | Tailscale |
| 8090 | nginx (Spectre/Brief UI) | Public |
| 8096 | Jellyfin | Tailscale |
| 8100 | Sieve dashboard | Tailscale |
| 8686 | Lidarr | Tailscale |
| 8889 | Search proxy | Internal |
| 8989 | Sonarr | Tailscale |
| 9696 | Prowlarr | Tailscale |

### Resource Budget

| Stack | Idle RAM | Active RAM | CPU |
|-------|----------|------------|-----|
| Koji | ~1GB | ~2GB | Low |
| Suri | ~2.5GB | ~4GB | Moderate |
| System + Docker | ~1GB | ~1GB | — |
| **Total** | **~4.5GB** | **~7GB** | Moderate |
| **Available** | **16GB** | **16GB** | 4 cores |

Plenty of headroom.

### Laptop Configuration

- **NFS server**: exports secondary media storage read-only
- **Power management**: TLP + powertop auto-tune for aggressive power saving
- **Suspend on idle**: systemd suspend timer when no SSH/NFS activity
- **Keeps running**: koji-node (Rust relay), Mac VM (on-demand), development tools

### What Gets Retired

- All 9 runit services on the tablet
- Termux workarounds (TUR index, phantom killer, grpcio patches, wake locks, boot scripts)
- Suri Docker stack on the laptop
- `~/bin/tablet` management script (replaced with equivalent for 710Q)
- koji-tablet bootstrap/deployment kit (replaced with Docker)

### Migration Order

1. Base setup (Docker, Tailscale, static IP, 4TB mount, NFS mount)
2. Koji stack (docker-compose, tunnel, verify 4 domains)
3. Suri stack (docker-compose, media paths, verify services)
4. Laptop NFS + power management
5. Retire tablet Koji services
6. Monitoring/watchdog
