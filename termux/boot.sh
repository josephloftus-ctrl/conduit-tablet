#!/data/data/com.termux/files/usr/bin/bash
# Auto-start Conduit on device boot.

# Acquire wake lock to prevent Android from sleeping Termux
termux-wake-lock

# Wait for networking to come up
sleep 30

# Start the server
exec "$HOME/conduit-tablet/scripts/start.sh"
