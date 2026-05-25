{ config, lib, ... }:
let
  # Folders from ~/Folder Structure/ that should be created in ~/ on boot and persist
  # These are bind-mounted from /persistent/home/yusa/<name> to /home/yusa/<name>
  folderStructureDirs = [
    "Atlas"
    "Desktop"
    "Documents"
    "Downloads"
    "Encrypted Storage"
    "Games"
    "Music"
    "Pictures"
    "Public"
    "Templates"
    "Videos"
  ];

  # Critical dotfiles/dotdirs that must survive tmpfs reboot
  criticalDirs = [
    # SSH keys (auth)
    { directory = ".ssh"; mode = "0700"; }

    # Nix/home-manager profile state — without this, HM activation breaks on reboot
    ".local/state/nix"
    ".local/state/home-manager"
  ];

  # Additional app state that's nice to persist
  appStateDirs = [
    ".local/share/keyrings"
    ".steam"
    ".var"
  ];
in
{
  # Impermanent / + /home: only explicitly listed paths survive reboot.
  # System paths are persisted via bind-mounts from /persistent/...
  # User home paths are persisted via bind-mounts from /persistent/home/yusa/...

  preservation = {
    enable = true;

    preserveAt."/persistent" = {
      directories = [
        # SSH host keys — regenerating on every reboot causes MITM warnings
        "/etc/ssh"
        # NixOS configuration (symlinked from flake)
        "/etc/nixos"
      ];

      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
        }
      ];

      # User home directories — persisted from /persistent/home/yusa/<name>
      # to /home/yusa/<name> via bind mount
      users = {
        yusa = {
          # Directory listing must be explicit since /home is tmpfs:
          # only paths listed here survive reboot.
          directories = folderStructureDirs ++ criticalDirs ++ appStateDirs;

          files = [
            # Shell history
            ".bash_history"
            # Flatpak installations reference .local/share/flatpak
            ".local/share/flatpak/repo/config"
            ".local/share/flatpak/repo/refs/heads/mega"
          ];
        };
      };
    };
  };

  # Home directory + intermediate parents need explicit ownership.
  # With /home on tmpfs, these dirs don't survive reboot and must be recreated.
  #
  # 1. Create /home/yusa with mode 0555 (not writable by user —
  #    only bind-mounted persisted dirs can be written to)
  # 2. Create subdirs owned by yusa so home-manager + apps can write into them
  systemd.tmpfiles.settings."home-dir" = {
    "/home/yusa".d = { user = "yusa"; group = "users"; mode = "0555"; };
    "/home/yusa/.config".d = { user = "yusa"; group = "users"; mode = "0755"; };
    "/home/yusa/.local".d = { user = "yusa"; group = "users"; mode = "0755"; };
    "/home/yusa/.local/share".d = { user = "yusa"; group = "users"; mode = "0755"; };
    "/home/yusa/.local/state".d = { user = "yusa"; group = "users"; mode = "0755"; };
    "/home/yusa/.cache".d = { user = "yusa"; group = "users"; mode = "0755"; };
  };
}
