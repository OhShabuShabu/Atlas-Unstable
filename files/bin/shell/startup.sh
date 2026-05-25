#!/usr/bin/env bash
awww-daemon --quiet &
vicinae server &
xwayland-satellite 2>/dev/null &
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

ffplay -nodisp "$PROJECT_DIR/files/audio/startup.mp3" 2>/dev/null &
mullvad connect &

sleep 12

if command -v openrgb &>/dev/null; then
  openrgb -d 0 -c $(python3 "$PROJECT_DIR/files/bin/python/fix_rgb_color.py" $(tr -d '#' < "$PROJECT_DIR/files/config/primary_color.txt")) &
fi
# virsh --connect qemu:///system start win11 &
