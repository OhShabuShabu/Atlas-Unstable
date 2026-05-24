{ pkgs, ... }:

let
  username = "yusa";
  userHome = "/home/${username}";
  notifications = import ../../lib/notifications.nix { inherit pkgs; };
  notifyUser = notifications.notifyScript;
in
{
  environment.systemPackages = with pkgs; [
    mullvad-vpn
    mullvad-browser
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

  systemd.paths.metadata-watcher = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = [
        "/home/yusa/Pictures"
        "/home/yusa/Downloads"
        "/home/yusa/Videos"
        "/home/yusa/Documents"
        "/home/yusa/Desktop"
      ];
      Unit = "metadata-watcher.service";
    };
  };

  systemd.services.metadata-watcher = {
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "metadata-watcher.sh" ''
        set -e
        NOTIFY="${notifyUser}/bin/notify-user"
        EXIF="${pkgs.exiftool}/bin/exiftool"

        CLEANED=0
        for dir in /home/yusa/Pictures /home/yusa/Downloads /home/yusa/Videos /home/yusa/Documents /home/yusa/Desktop; do
          [ -d "$dir" ] || continue
          count=$($EXIF -overwrite_original -all= -gps:all= -makernotes:all= \
            -Thumbnail-Image= -XMP-iptcCore:all= -Software= -Artist= \
            -Copyright= -SerialNumber= -CameraSerialNumber= -OwnerName= \
            -r -ext jpg -ext jpeg -ext png -ext gif -ext tiff -ext webp \
            -ext mp4 -ext mov -ext avi -ext mkv \
            -m -mmin -5 \
            "$dir" 2>/dev/null | grep -c "image files updated" || echo 0)
          CLEANED=$((CLEANED + count))
        done

        if [ "$CLEANED" -gt 0 ]; then
          "$NOTIFY" normal "Metadata Cleaner" "Cleaned metadata from $CLEANED files"
        fi
      '';
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
