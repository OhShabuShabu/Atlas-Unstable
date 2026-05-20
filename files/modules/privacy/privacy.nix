{ config, pkgs, lib, ... }:

let
  username = "yusa";
  userHome = "/home/${username}";
  notifyUser = pkgs.writeShellScriptBin "notify-user" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    for user in ${username}; do
      uid=$(id -u "$user" 2>/dev/null || echo 1000)
      bus_path="/run/user/$uid/bus"
      if [ -S "$bus_path" ]; then
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path" \
          "$NOTIFY" -u "''${1:-normal}" -t 5000 "''${2:-Metadata Cleaner}" "''${3:-}" 2>/dev/null || true
      fi
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    mullvad-vpn
    mullvad-browser
    exiftool
    inotify-tools
    notifyUser
    nftables
  ];
  services.mullvad-vpn.enable = true;
  systemd.services.mullvad-daemon = {
    path = [ pkgs.nftables ];
    after = [ "network.target" "network-online.target" ];
    serviceConfig = {
      AmbientCapabilities = "CAP_NET_ADMIN";
    };
  };

  systemd.services.metadata-cleaner = {
    description = "Strip GPS and identifying metadata from media files in /home";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "metadata-cleaner.sh" ''
        set -e
        NOTIFY="${notifyUser}/bin/notify-user"
        CLEANED=0
        FAILED=0
        EXIF="${pkgs.exiftool}/bin/exiftool"

        clean_dir() {
          local dir="$1"
          [ -d "$dir" ] || return 0
          local count=0
          count=$($EXIF -overwrite_original -all= -gps:all= -makernotes:all= \
            -Thumbnail-Image= -XMP-iptcCore:all= -Software= -Artist= \
            -Copyright= -SerialNumber= -CameraSerialNumber= -OwnerName= \
            -r -ext jpg -ext jpeg -ext png -ext gif -ext tiff -ext webp \
            -ext mp4 -ext mov -ext avi -ext mkv \
            "$dir" 2>/dev/null | grep -c "image files updated" || echo 0)
          echo "$count"
        }

        for dir in "$userHome/Pictures" "$userHome/Downloads" "$userHome/Videos" "$userHome/Documents" "$userHome/Desktop"; do
          c=$(clean_dir "$dir")
          CLEANED=$((CLEANED + c))
        done

        if [ "$CLEANED" -gt 0 ]; then
          "$NOTIFY" normal "Metadata Cleaner" "Cleaned metadata from $CLEANED files"
        fi
      '';
    };
  };

  systemd.timers.metadata-cleaner = {
    description = "Daily metadata cleanup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };

  systemd.services.metadata-watcher = {
    description = "Real-time metadata cleaner for new media files";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "metadata-watcher.sh" ''
        set -e
        NOTIFY="${notifyUser}/bin/notify-user"
        EXIF="${pkgs.exiftool}/bin/exiftool"
        INOTIFY="${pkgs.inotify-tools}/bin/inotifywait"

        dirs="$userHome/Pictures $userHome/Downloads $userHome/Videos $userHome/Documents $userHome/Desktop"
        existing=""
        for d in $dirs; do
          [ -d "$d" ] && existing="$existing $d"
        done

        while true; do
          file=$($INOTIFY -q -e close_write --format '%w%f' $existing 2>/dev/null) || break
          ext=$(echo "$file" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]')
          case "$ext" in
            jpg|jpeg|png|gif|tiff|webp|mp4|mov|avi|mkv|webm|m4v)
              sleep 0.3
              $EXIF -overwrite_original -all= -gps:all= -makernotes:all= \
                -Thumbnail-Image= -Software= -Artist= -Copyright= \
                -SerialNumber= -CameraSerialNumber= -OwnerName= \
                "$file" 2>/dev/null && \
                "$NOTIFY" low "Metadata Cleaner" "Cleaned: $(basename "$file")"
              ;;
          esac
        done
      '';
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.setup-mullvad-dirs = {
    description = "Setup Mullvad browser directories";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = username;
    };
    script = ''
      export HOME="${userHome}"
      mkdir -p "$HOME/.local/share/mullvad-browser"
    '';
  };
}
