# conduit-tablet

Deployment kit for running the Conduit server on an Android tablet via Termux.

## Quick Start

```bash
# 1. Clone this repo onto the tablet
git clone <repo-url> ~/conduit-tablet
cd ~/conduit-tablet

# 2. Run the setup script (installs Termux packages, Python deps, cloudflared)
bash scripts/setup.sh

# 3. Copy and fill in your environment variables
cp .env.template ~/conduit/server/.env
# Edit .env with your API keys

# 4. Start the server
bash scripts/start.sh
```

## Documentation

See [docs/setup-guide.md](docs/setup-guide.md) for full setup instructions,
architecture notes, and troubleshooting.
