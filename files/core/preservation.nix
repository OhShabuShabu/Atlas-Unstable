{ config, lib, ... }:
let
  # ── User identity ──────────────────────────────────────────────────
  # Change these values to reconfigure the primary user for this machine.
  userName = "yusa";
  userHome = "/home/${userName}";

  # Folders from ~/Folder Structure/ that should be created in ~/ on boot and persist
  # These are bind-mounted from /persistent/${userHome}/<name> to ${userHome}/<name>
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
  # User home paths are persisted via bind-mounts from /persistent${userHome}/...

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

      # User home directories — persisted from /persistent${userHome}/<name>
      # to ${userHome}/<name> via bind mount
      users = {
        "${userName}" = {
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
  # 1. Create ${userHome} with mode 0755 (not writable by user —
  #    only bind-mounted persisted dirs can be written to)
  # 2. Create subdirs owned by ${userName} so home-manager + apps can write into them
  systemd.tmpfiles.settings."home-dir" = {
    "${userHome}".d = { user = "${userName}"; group = "users"; mode = "0755"; };
    "${userHome}/.config".d = { user = "${userName}"; group = "users"; mode = "0755"; };
    "${userHome}/.local".d = { user = "${userName}"; group = "users"; mode = "0755"; };
    "${userHome}/.local/share".d = { user = "${userName}"; group = "users"; mode = "0755"; };
    "${userHome}/.local/state".d = { user = "${userName}"; group = "users"; mode = "0755"; };
    "${userHome}/.cache".d = { user = "${userName}"; group = "users"; mode = "0755"; };
  };
}
