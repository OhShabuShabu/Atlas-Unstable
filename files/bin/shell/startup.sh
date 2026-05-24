#!/usr/bin/env bash
awww-daemon --quiet &
vicinae server 2>/dev/null &
xwayland-satellite 2>/dev/null &
ghostty -e btop &
ghostty -e tty-clock &
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

ffplay -nodisp "$PROJECT_DIR/files/audio/startup.mp3" 2>/dev/null &
mullvad connect &

sleep 12

openrgb -d 0 -c $(python3 "$PROJECT_DIR/files/bin/python/fix_rgb_color.py" $(tr -d '#' < "$PROJECT_DIR/files/config/primary_color.txt")) &
# virsh --connect qemu:///system start win11 &
