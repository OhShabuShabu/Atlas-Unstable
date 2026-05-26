#!/usr/bin/env bash
# ─── Post-desktop-init tasks ──────────────────────────────────────────
# Core services (awww, vicinae, xwayland-satellite, startup sound, OpenRGB)
# are now managed as systemd user services and auto-start with the session.
# This script handles remaining one-off tasks.

# Connect Mullvad VPN (handled here as fallback if auto-connect isn't configured)
# mullvad connect &

# Virtual machine auto-start (uncomment if needed)
# virsh --connect qemu:///system start win11 &
