{ pkgs, ... }:

# INFO: Shared notification system for security modules
# This library provides a reusable function for sending desktop notifications
# to the active user via notify-send over DBUS.

{
  # INFO: Create a notify-send script targeting the yusa user
  # Uses DBUS session bus for desktop notifications (requires libnotify)
  notifyScript = pkgs.writeShellScriptBin "notify-user" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    for user in yusa; do
      uid=$(id -u "$user" 2>/dev/null || echo 1000)
      bus_path="/run/user/$uid/bus"
      if [ -S "$bus_path" ]; then
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path" \
          "$NOTIFY" -u "$''${1:-normal}" -t "$''${4:-15000}" "$''${2:-Notification}" "$''${3:-}" 2>/dev/null || true
      fi
    done
  '';
}
