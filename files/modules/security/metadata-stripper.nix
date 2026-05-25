{ pkgs, lib, ... }:

let
  notifications = import ../../lib/notifications.nix { inherit pkgs; };
  notifyScript = notifications.notifyScript;

  # Directories to watch for new files and scan daily
  watchDirs = [
    "/home/yusa/Pictures"
    "/home/yusa/Downloads"
    "/home/yusa/Documents"
    "/home/yusa/Desktop"
  ];

  # exiftool flags to strip GPS, camera, and identifying metadata
  stripFlags = with pkgs; ''
    ${exiftool}/bin/exiftool -overwrite_original \
      -all= -gps:all= -makernotes:all= -ThumbnailImage- \
      -XMP-iptcCore:all= -Software= -Artist= -Copyright= \
      -SerialNumber= -CameraSerialNumber= -OwnerName= \
      -r -ext jpg -ext jpeg -ext png -ext gif -ext tiff -ext webp \
      -ext mp4 -ext mov -ext avi -ext mkv \
      "$@"
  '';

  exiftool = pkgs.exiftool;
in

{
  environment.systemPackages = [ notifyScript ];

  systemd.tmpfiles.rules = [
    "d /var/log/metadata-stripper 0750 root root -"
  ];

  # ─── Path Watcher: strip metadata from newly modified files ───────────────
  systemd.paths.metadata-stripper-watcher = {
    description = "Metadata stripper path watcher";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = watchDirs;
      Unit = "metadata-stripper-watcher.service";
    };
  };

  systemd.services.metadata-stripper-watcher = {
    description = "Strip metadata from newly modified media files";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "metadata-stripper-watcher.sh" ''
        set -e
        LOG="/var/log/metadata-stripper/watcher.log"
        mkdir -p "$(dirname "$LOG")"
        NOTIFY="${notifyScript}/bin/notify-user"
        EXIF="${exiftool}/bin/exiftool"
        STRIP_DIRS="${builtins.toString watchDirs}"

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watcher triggered" >> "$LOG"

        TOTAL=0
        for dir in $STRIP_DIRS; do
          [ -d "$dir" ] || continue
          # Strip metadata from files modified in the last 5 minutes
          count=$($EXIF -overwrite_original \
            -all= -gps:all= -makernotes:all= -ThumbnailImage- \
            -XMP-iptcCore:all= -Software= -Artist= -Copyright= \
            -SerialNumber= -CameraSerialNumber= -OwnerName= \
            -r -ext jpg -ext jpeg -ext png -ext gif -ext tiff -ext webp \
            -ext mp4 -ext mov -ext avi -ext mkv \
            -m -mmin -5 \
            "$dir" 2>/dev/null | grep -c "image files updated" || echo 0)
          TOTAL=$((TOTAL + count))
        done

        if [ "$TOTAL" -gt 0 ]; then
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stripped metadata from $TOTAL files" >> "$LOG"
          "$NOTIFY" low "Metadata Stripper" "Cleaned metadata from $TOTAL file(s)"
        fi
      '';
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ReadWritePaths = [ "/var/log/metadata-stripper" ];
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      SystemCallArchitectures = "native";
    };
  };

  # ─── Daily Scan: full sweep of watched directories ────────────────────────
  systemd.services.metadata-stripper-daily = {
    description = "Daily metadata stripping sweep";
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "metadata-stripper-daily.sh" ''
        set -e
        LOG="/var/log/metadata-stripper/daily.log"
        mkdir -p "$(dirname "$LOG")"
        NOTIFY="${notifyScript}/bin/notify-user"
        EXIF="${exiftool}/bin/exiftool"
        STRIP_DIRS="${builtins.toString watchDirs}"

        echo "=== Daily Metadata Strip $(date) ===" >> "$LOG"
        TOTAL=0

        for dir in $STRIP_DIRS; do
          [ -d "$dir" ] || continue
          count=$($EXIF -overwrite_original \
            -all= -gps:all= -makernotes:all= -ThumbnailImage- \
            -XMP-iptcCore:all= -Software= -Artist= -Copyright= \
            -SerialNumber= -CameraSerialNumber= -OwnerName= \
            -r -ext jpg -ext jpeg -ext png -ext gif -ext tiff -ext webp \
            -ext mp4 -ext mov -ext avi -ext mkv \
            "$dir" 2>/dev/null | grep -c "image files updated" || echo 0)
          echo "  $dir: $count files cleaned" >> "$LOG"
          TOTAL=$((TOTAL + count))
        done

        echo "Total: $TOTAL files processed" >> "$LOG"

        if [ "$TOTAL" -gt 0 ]; then
          "$NOTIFY" low "Metadata Stripper" "Daily sweep: cleaned $TOTAL file(s)"
        fi
      '';
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ReadWritePaths = [ "/var/log/metadata-stripper" ];
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      SystemCallArchitectures = "native";
    };
  };

  systemd.timers.metadata-stripper-daily = {
    description = "Daily metadata stripping timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };
}
