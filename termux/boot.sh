#!/data/data/com.termux/files/usr/bin/bash
# Auto-start on device boot.
# runit (via termux-services) handles starting all conduit-* services automatically.
# This script just ensures wake lock and SSH are available.

# Acquire wake lock to prevent Android from sleeping Termux
termux-wake-lock

# Start SSH so we can always reach the tablet remotely
sshd 2>/dev/null || true
