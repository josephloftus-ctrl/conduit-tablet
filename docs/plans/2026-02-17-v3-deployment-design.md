# Conduit Tablet Deployment v3 — Design Doc

**Date:** 2026-02-17
**Status:** Approved
**Approach:** Script-First, Then Deploy (Approach A)

---

## Summary

Update the conduit-tablet repo with clean v3 scripts, create the laptop `tablet` CLI, then deploy to the factory-reset Lenovo Tab M11 (4GB RAM, ARM64, Android 14, 256GB microSD).

## Device

- Lenovo Tab M11, 4GB RAM, ARM64, Android 14
- 256GB microSD card available (for conduit-data/backups if needed)
- Tailscale IP: 100.115.173.115
- Prerequisites complete (factory reset, Termux/Boot/API from F-Droid, Tailscale, base packages)

## Service Stack (8 services + sshd)

| # | Service | Source | Clone Method | Port |
|---|---------|--------|-------------|------|
| 1 | conduit-server (FastAPI) | conduit-server repo | git clone (public) | 8080 |
| 2 | conduit-tunnel (cloudflared) | config in conduit-tablet | config only | — |
| 3 | conduit-search (Brave proxy) | conduit-tablet/search-proxy/ | git clone (public) | 8889 |
| 4 | conduit-ntfy | ntfy binary | pre-installed | 2586 |
| 5 | conduit-spectre (uvicorn) | spectre repo | rsync (private) | 8000 |
| 6 | conduit-nginx | spectre/nginx/ config | rsync (private) | 80 |
| 7 | conduit-brief | morning-brief repo | rsync (private) | TBD |
| 8 | conduit-crond | cron daemon | system package | — |
| + | sshd | openssh | system package | 8022 |

**Removed:** conduit-dashboard (doesn't exist — steady.josephloftus.com routes to spectre)

## Cloudflared Tunnel Routes

```
conduit.josephloftus.com → localhost:8080  (conduit-server)
steady.josephloftus.com  → localhost:8000  (spectre backend/nginx)
brief.josephloftus.com   → localhost:PORT  (morning-brief)
ntfy.josephloftus.com    → localhost:2586  (ntfy)
```

## Repo Strategy

| Repo | GitHub | Tablet Path | Method |
|------|--------|-------------|--------|
| conduit-server | josephloftus-ctrl/conduit-server (public) | ~/conduit/ | git clone |
| conduit-tablet | josephloftus-ctrl/conduit-tablet (public) | ~/conduit-tablet/ | git clone |
| spectre | private | ~/spectre/ | rsync from laptop |
| morning-brief | private | ~/morning-brief/ | rsync from laptop |

## Files to Create/Modify

### In conduit-tablet repo

| Action | File | What |
|--------|------|------|
| Replace | setup.sh → bootstrap-tablet.sh | v3 idempotent 14-section bootstrap |
| Update | scripts/setup-runit.sh | Remove conduit-dashboard, verify paths |
| Update | scripts/update.sh | Update service list (no dashboard) |
| Update | scripts/start.sh | Remove dashboard refs |
| Update | scripts/stop.sh | Remove dashboard refs |
| Update | scripts/status.sh | Remove dashboard refs |
| Update | scripts/healthcheck.sh | Remove dashboard refs |
| Keep | scripts/watchdog.sh | Already good |
| Update | cloudflared/config.yml | Add steady + brief routes |
| Delete | scripts/deploy-fresh.sh | Replaced by bootstrap-tablet.sh |

### On Laptop (not in repo)

| File | What |
|------|------|
| ~/bin/tablet | CLI controller (status, restart, logs, update, backup, etc.) |

## Deployment Stages

### Stage 0 — Laptop (ADB, one-time)
1. Android hardening (phantom process killer, doze whitelist)
2. Safe debloat (Lenovo/Google bloat, one at a time)
3. Push .env via ADB to /sdcard/conduit-env
4. Push bootstrap-tablet.sh via ADB to /sdcard/
5. Install ~/bin/tablet CLI on laptop

### Stage 1 — Tablet Screen (Termux, no SSH)
Run bootstrap-tablet.sh — 14 idempotent sections:
1. Wake lock
2. Storage & directories
3. DNS (resolv.conf)
4. Clone PUBLIC repos (conduit-server, conduit-tablet)
5. Install .env from /sdcard
6. Python dependencies
7. Web UI build (npm)
8. Config overlay + patches
9. Install termux-services (CHECKPOINT: restart Termux)
10. Set up runit services
11. Boot script (Termux:Boot)
12. Watchdog cron
13. Cloudflared tunnel (interactive browser login)
14. Automated backup cron

### Stage 1.5 — Laptop (SSH now alive via runit)
1. rsync ~/Projects/spectre/ → tablet:~/spectre/
2. rsync ~/Projects/morning-brief/ → tablet:~/morning-brief/
3. Install spectre pip deps on tablet via SSH
4. Build spectre frontend if needed
5. Restart spectre/nginx/brief services

### Stage 2 — Laptop (verify)
1. `tablet status` — all services green
2. `tablet ping` — SSH + Conduit alive
3. curl health endpoints (localhost via SSH)
4. curl external domains (conduit/steady/brief/ntfy .josephloftus.com)
5. `tablet watchdog` — verify monitoring works

## Out of Scope (v4+)
- Monitoring stack (Prometheus/Grafana)
- Firewall (iptables) — Tailscale handles isolation
- Log rotation — 256GB microSD, not urgent
- Status dashboard — can add later
- Rollback mechanism — deploy-fresh is nuclear option
- MicroSD mount optimization — revisit if needed
