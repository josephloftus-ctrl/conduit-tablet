# Koji Ops

Deployment infrastructure and server management for the Koji platform.

## Current: 710Q Home Server

The Koji stack runs on a Lenovo IdeaCentre 710Q (Intel i3-7100T, 8GB RAM, 256GB NVMe) with Ubuntu Server 24.04.

### Services

Two Docker Compose stacks plus standalone services:

**Koji stack** (`~/koji/docker-compose.yml`):
- koji-server (8080) — AI backend
- koji-search (8889) — SearXNG proxy
- koji-spectre (8000) — inventory operations dashboard
- koji-nginx (8090) — static file server
- koji-brief (5050) — morning briefing generator
- koji-ntfy (2586) — push notifications
- cloudflared — Cloudflare tunnel (host network)

**Suri stack** (`~/suri/docker-compose.yml`):
- 15 media automation services (Jellyfin, *arr suite, qBittorrent, Navidrome, etc.)

**Standalone**: Gitea (3300), Mealie (9925), Prometheus (9090), Grafana (3000)

### Networking

- **Public**: 5 domains via Cloudflare tunnel (conduit, steady, brief, ntfy, git .josephloftus.com)
- **Private**: Tailscale (100.98.170.115)
- **Local**: 192.168.1.183
- **Storage**: 256GB NVMe (OS + Docker) + 4TB USB HDD (`/mnt/media`)

## Structure

```
scripts/         # Service management (start, stop, status, update, watchdog)
cloudflared/     # Tunnel config template
search-proxy/    # SearXNG search proxy (Python)
termux/          # Legacy Termux bootstrap (tablet era)
docs/plans/      # Architecture designs and migration plans
config.yaml      # Server config overlay
```

## Management

From the laptop:
```bash
server status          # check all services
server ssh             # SSH into 710Q
server logs <service>  # tail container logs
server restart <stack> # restart a compose stack
server update-koji     # deploy latest koji-server code
server rsync-private   # sync private repos
server backup          # trigger manual backup
```

## Legacy: Tablet Deployment

Previously ran on a Lenovo Tab P12 via Termux + proot + runit. Migrated to the 710Q in February 2026. The tablet remains as a CUPS print server.

## Related Repos

| Repo | Description |
|------|-------------|
| [koji-server](https://git.josephloftus.com/joseph/koji-server) | Python backend — agents, tools, memory |
| [koji](https://git.josephloftus.com/joseph/koji) | iOS chat app |
| [koji-node](https://git.josephloftus.com/joseph/koji-node) | Rust desktop daemon + KDE Plasma widget |
| [suri](https://git.josephloftus.com/joseph/suri) | Media automation stack |
