{ config, lib, pkgs, ... }:
let
  # ── User identity ──────────────────────────────────────────────────
  userName = "yusa";
  userHome = "/home/${userName}";

  # Folders from ~/Folder Structure/ that should be created in ~/ on boot and persist
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

  # ============================================================================
  # CRITICAL: Must persist — data loss or system breakage without these
  # ============================================================================

  # System identity — without these, machine changes identity every reboot
  systemIdentityDirs = [
    "/etc/ssh"
    "/etc/nixos"
  ];

  systemIdentityFiles = [
    {
      file = "/etc/machine-id";
      inInitrd = true;
    }
  ];

  # Root credentials — ssh/gpg for automation/remote access
  rootCredDirs = [
    "/root/.ssh"
    "/root/.gnupg"
  ];

  # User credentials — authentication material that MUST survive reboot
  userCredDirs = [
    { directory = ".ssh"; mode = "0700"; }
    { directory = ".gnupg"; mode = "0700"; }
    { directory = ".password-store"; mode = "0700"; }
  ];

  # Nix/home-manager profile state — without this, HM activation breaks on reboot
  userNixStateDirs = [
    ".local/state/nix"
    ".local/state/home-manager"
  ];

  # ============================================================================
  # RECOMMENDED: Should persist — significant usability/convenience loss otherwise
  # ============================================================================

  # Shell state and history
  userShellStateDirs = [
    ".local/state/nushell"
  ];

  userShellFiles = [
    ".bash_history"
  ];

  # Secret/keyring stores
  userKeyringDirs = [
    ".local/share/keyrings"
  ];

  # Flatpak — full installations (not just partial config)
  # Without this, all Flatpak apps must be re-installed after every reboot
  userFlatpakDirs = [
    ".var"
    ".local/share/flatpak"
  ];

  # Gaming — Steam, game configs, saves
  userGamingDirs = [
    ".steam"
  ];

  # VPN & privacy services
  userVpnDirs = [
    ".local/share/mullvad-vpn"
  ];

  # ============================================================================
  # OPTIONAL: Nice to have — improves UX but not critical
  # ============================================================================

  # Application configs that are NOT managed by home-manager
  # Managed by HM: niri, nushell, alacritty, ghostty, noctalia-shell, git
  # Unmanaged (persisted here): mpv, btop, kitty, vscodium, etc.
  userAppConfigDirs = [
    ".config/htop"
    ".config/mpv"
    ".config/btop"
    ".config/VSCodium"
  ];

  # User-installed fonts
  userFontDirs = [
    ".local/share/fonts"
  ];

  # Caches that improve performance/UX
  userCacheDirs = [
    ".cache/awww"
  ];

  # Development state
  userDevDirs = [
    ".direnv"
    ".local/share/nvim"
  ];
in
{
  preservation = {
    enable = true;

    preserveAt."/persistent" = {
      # ── System paths ──────────────────────────────────────────────
      directories = systemIdentityDirs ++ rootCredDirs;

      files = systemIdentityFiles;

      # ── User home paths ───────────────────────────────────────────
      users = {
        "${userName}" = {
          directories =
            # Folder structure (data directories)
            folderStructureDirs
            # Critical
            ++ userCredDirs
            ++ userNixStateDirs
            # Recommended
            ++ userShellStateDirs
            ++ userKeyringDirs
            ++ userFlatpakDirs
            ++ userGamingDirs
            ++ userVpnDirs
            # Optional
            ++ userAppConfigDirs
            ++ userFontDirs
            ++ userCacheDirs
            ++ userDevDirs;

          files = userShellFiles;
        };
      };
    };
  };

  # ============================================================================
  # systemd-tmpfiles: Ensure intermediate parent directories exist on tmpfs
  # ============================================================================
  # With /home on tmpfs, these dirs don't survive reboot and must be recreated.
  systemd.tmpfiles.settings."home-dir" = {
    "${userHome}".d = {
      user = "${userName}";
      group = "users";
      mode = "0755";
    };
    "${userHome}/.config".d = {
      user = "${userName}";
      group = "users";
      mode = "0755";
    };
    "${userHome}/.local".d = {
      user = "${userName}";
      group = "users";
      mode = "0755";
    };
    "${userHome}/.local/share".d = {
      user = "${userName}";
      group = "users";
      mode = "0755";
    };
    "${userHome}/.local/state".d = {
      user = "${userName}";
      group = "users";
      mode = "0755";
    };
    "${userHome}/.cache".d = {
      user = "${userName}";
      group = "users";
      mode = "0755";
    };
  };

  # ============================================================================
  # /var/lib persistence notes (already persistent — on btrfs subvol)
  # ============================================================================
  # The following live on /var (persistent btrfs subvol), NOT on tmpfs,
  # so they naturally survive reboots without preservation bind-mounts:
  #
  #   /var/log/                    — All system logs (audit, snort, snout, clamav, aide)
  #   /var/lib/clamav/             — ClamAV virus database (huge download avoided)
  #   /var/lib/aide/               — AIDE integrity database
  #   /var/lib/NetworkManager/     — NetworkManager connection profiles
  #   /var/lib/systemd/            — timesync state, random seed, etc.
  #   /var/lib/usbguard/           — USBGuard rules
  #   /var/lib/rsyslog/            — Rsyslog buffer state
  #   /var/account/                — Process accounting data
  #   /var/db/sudo/                — Sudo lecture state
  #
  # These services already declare systemd.tmpfiles rules for their
  # directories. No changes needed here.
  #
  # ============================================================================
  # Explicitly ephemeral paths (intentionally NOT persisted)
  # ============================================================================
  #   /tmp/*                       — Temporary files (tmpfs, cleaned on boot)
  #   /var/tmp/*                   — Persistent temp (on /var, cleaned by systemd)
  #   /run/*                       — Runtime state (tmpfs, cleaned on boot)
  #   ~/.cache/*                   — General caches (safe to lose, see exceptions above)
  #   ~/.local/share/Trash/        — Desktop trash (temporary by nature)
  #   ~/.npm/ ~/.cargo/ ~/.go/    — Build caches (can be re-downloaded)
  #   ~/.local/share/recently-used.xbel — File open history (privacy)
  #   ~/.thumbnails/               — Thumbnail caches (regenerated on demand)
  #   /etc/quarantine/             — Quarantined malware (wiped at shutdown)
}
