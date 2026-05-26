# Atlas

> A production-quality NixOS configuration with the Noctalia desktop shell,
> enterprise-grade security hardening, gaming optimizations, and a privacy-first
> browsing setup — ready from the first boot.

| Component | Choice |
|-----------|--------|
| **WM** | [Niri](https://github.com/YaLTeR/niri) (scrolling Wayland compositor) |
| **Shell** | [Noctalia](https://github.com/noctalia-dev/noctalia-shell) (Wayland desktop shell) |
| **Display Manager** | SDDM (nier-automata theme, auto-login) |
| **Terminal** | [Ghostty](https://ghostty.org/) with Nushell |
| **Editor** | Neovim (LazyVim), opencode |

---

## Quick Start (After Install)

### Every Day

| Action | Command |
|--------|---------|
| Rebuild system | `atlas-rebuild` (stops tamper-detection, rebuilds, runs health check) |
| Check system health | `atlas-health` |
| Quick health snapshot | `atlas-health quick` |
| Run config tests | `test-config` |

### Updating

```bash
# Update all flake inputs and rebuild
atlas-rebuild --upgrade

# Update only the flake lock (review changes first)
nix flake update
atlas-rebuild
```

### Common Tasks

| Task | Command |
|------|---------|
| Add system package | Edit `files/core/configuration.nix` → `environment.systemPackages` → `atlas-rebuild` |
| Add user package | Edit `files/core/home.nix` → `home.packages` → `atlas-rebuild` |
| Enable optional module | Download `.nix` to `files/modules/optional/{nixos,home}/` → `atlas-rebuild` |
| Check flake syntax | `nix-check` |
| View security logs | `security-logs` |
| Run security scan | `lynis-scan` |
| Check file integrity | `aide-check` |
| Run all config tests | `test-config` |

---

## System Health (`atlas-health`)

A unified status tool that checks everything in one place:

```
$ atlas-health
══════════════════════════════════════════
  Atlas System Health
══════════════════════════════════════════

System:
  Kernel: 6.14.0
  Uptime: up 2 hours
  Memory: 3.1Gi used / 15.4Gi total
  Nix store: 18G used / 234G total

Security:
  ✓ snort-daemon
  ✓ snout-watcher.service
  ✓ clamav-daemon
  ✓ aide-check.timer

Desktop:
  ✓ atlas-awww
  ✓ atlas-vicinae
  ✓ atlas-xwayland-satellite
  ✓ polkit-gnome-authentication-agent-1

Disk:
  Filesystem      Size  Used Avail Use%
  /dev/nvme0n1p2  1.9T  234G  1.6T  13%

LUKS:
  ✓ LUKS container 'crypt' is active

Last Scans:
  ClamAV: OK: 3171197 files scanned, 0 threats found
  ✓ AIDE last check passed
```

---

## Security Commands

```bash
# System health & monitoring
atlas-health              # Full system health check
atlas-health quick        # Quick health summary

# Snout security monitoring
snout scan                # Run security scan
snout status              # Check daemon status
snout logs                # Follow daemon logs

# ClamAV
sudo systemctl start clamav-daily-scan    # Manual system scan
cat /var/log/clamav/scan.log              # View scan results

# AIDE file integrity
sudo aide --check                         # Check file integrity

# Lynis audit
sudo lynis audit system --quick

# Quarantine
quarantine-list                           # List quarantined files
quarantine-purge                          # Securely purge all quarantined files

# Trash management
trash put <file>                          # Move file to trash
trash list                                # List trashed files
trash restore <file>                      # Restore from trash
```

---

## Recovery & Maintenance

### Boot into a Previous Generation

If a rebuild breaks something:

1. Reboot and hold **Space** during boot (or press repeatedly) to open the systemd-boot menu
2. Select an older generation (labeled by date)
3. Boot into the working configuration
4. To revert permanently:
   ```bash
   sudo nixos-rebuild switch --flake .#atlas --rollback
   ```

### NixOS Rebuild Failed

```bash
# Get detailed error information
nix flake check --show-trace

# Check common issues
# • File indentation must be 2 spaces (Nix is whitespace-sensitive)
# • Check balanced braces ({}) and semicolons (;)
# • Verify package names exist in nixpkgs

# Revert changes and rebuild
git checkout -- files/core/configuration.nix
atlas-rebuild
```

### Nix Store Filling Up

The system automatically garbage-collects weekly, but for immediate cleanup:

```bash
# Remove all old generations (frees the most space)
sudo nix-collect-garbage -d

# Remove old Home Manager generations (user-level)
home-manager expire-generations 30d

# Check what's using space
sudo ncdu /nix/store
```

### USB Devices Not Working

USBGuard may be blocking newly connected devices:

```bash
# List USB rules
sudo usbguard list-rules

# Temporarily allow a device (replace [device-id] with the actual ID)
sudo usbguard allow-device [device-id]

# Generate a permanent policy (captures all currently connected devices)
sudo usbguard generate-policy > /var/lib/usbguard/rules.conf
```

### LUKS Passphrase Issues

If TPM-based unlocking fails, you'll be prompted for the LUKS passphrase at boot.
If you forget it, recovery requires:
- The LUKS recovery key (if created during install), OR
- Restoring from backups

> **Always maintain backups of `/persistent`** — this contains your configs, SSH keys, and user data.

---

## Key Bindings (Niri)

| Shortcut | Action |
|----------|--------|
| `Mod+T` | Open Ghostty terminal |
| `Mod+Space` | Open Vicinae launcher |
| `Mod+H/J/K/L` | Focus window (vim-style) |
| `Mod+Shift+W` | Noctalia panel toggle |
| `Mod+Shift+E` | Quit Niri |
| `Print` | Screenshot |

> Full keybinding reference: `~/.config/niri/config.kdl`

---

## Structure

```
.
├── flake.nix                              # Flake entry point (inputs + outputs)
├── install.sh                             # Full-disk installer (NixOS live ISO)
├── test_config.sh                         # 300+ offline static tests
├── AGENTS.md                              # Guide for AI coding assistants
├── files/
│   ├── core/
│   │   ├── configuration.nix              # System-wide NixOS config
│   │   ├── home.nix                       # Home Manager user config
│   │   ├── current-system.nix             # Btrfs/tmpfs layout (impermanence)
│   │   ├── disko.nix                      # Disk partitioning (installer only)
│   │   ├── preservation.nix               # Persistent data paths
│   │   ├── hardware-configuration.nix     # Auto-generated (do not edit)
│   │   └── config/
│   │       ├── nix/nix.conf               # Nix daemon settings
│   │       └── shellrc.nu                 # Nushell aliases & config
│   ├── config/
│   │   ├── niri/                          # Niri WM configuration
│   │   ├── vicinae/vicinae.json           # Launcher config
│   │   └── .icons/                        # Cursor themes
│   ├── modules/
│   │   ├── security/                      # 24+ hardening submodules
│   │   └── optional/                      # External atlas-modules integration
│   ├── hardware/                          # GPU/CPU/audio auto-importers
│   ├── profiles/                          # System profiles (atlas)
│   ├── lib/                               # Shared Nix library modules
│   ├── bin/                               # Shell & Python scripts
│   ├── audio/                             # Sound effects
│   ├── etc/                               # Static config files
│   └── secrets/                           # SOPS-encrypted secrets
```

---

## Features

### Desktop Experience
- **Noctalia Shell** — Wayland desktop shell (status bar, notifications, OSD, widgets)
- **Dynamic theming** — [Matugen](https://github.com/InioX/matugen) generates colors from wallpapers
- **Wallpaper management** — [awww](https://github.com/end-4/awww) daemon (systemd-managed)
- **Application launcher** — [Vicinae](https://github.com/vicinaehq/vicinae) (systemd-managed)
- **Notifications** — Noctalia notification system
- **Startup sound** — Audio feedback on login (systemd-managed)
- **RGB lighting** — OpenRGB applies wallpaper-derived colors (systemd-managed)

All desktop background services run as proper **systemd user services** with automatic restart on failure, journald logging, and lifecycle management — no fragile background processes.

### Security Hardening
- **LUKS full-disk encryption** with TPM-sealed keyfile (passphrase + TPM 2FA)
- **AppArmor** MAC enforcement with killUnconfinedConfinables
- **Kernel hardening**: locked modules, boot params (slab_nomerge, init_on_alloc, pti=on, lockdown=integrity), sysctl hardening (50+ settings)
- **nftables firewall** with minimal open ports
- **ClamAV** daemon with daily scans, auto-quarantine, desktop notifications
- **AIDE** file integrity monitoring (SHA512, daily checks)
- **Snout** — security monitoring daemon (watches quarantine, triggers ClamAV)
- **Snort** — network IDS/IPS with custom rules
- **Auditd** — kernel audit subsystem with comprehensive rules
- **USBGuard** — USB device authorization
- **systemd service hardening** — sandboxing for NetworkManager, SSH, polkit, etc.
- **Memory wipe** — DRAM + log shredding at shutdown
- **Metadata stripper** — auto-strips GPS/exif from images in ~/Pictures, ~/Downloads, ~/Desktop
- **DNSSEC + DNS-over-TLS** via systemd-resolved with Cloudflare DNS

### Gaming & Performance
- **Steam** with [Millennium](https://github.com/SteamClientHomebrew/Millennium) theming
- **PrismLauncher** (Minecraft), Blockbench, steamcmd
- AMD 32-bit graphics drivers, Intel CPU with performance governor
- TCP BBR congestion control, cake qdisc

### Development & Tools
- Neovim (LazyVim), opencode, claude-code
- bun runtime, Docker, Podman, Distrobox
- libvirtd + virt-manager (Windows 11 VM)
- Nushell with zoxide, fzf integration

---

## Theming

| Layer | Setting |
|-------|---------|
| GTK | Adwaita-dark |
| Icons | Papirus-Dark |
| Fonts | Monocraft, Roboto, Nerd Fonts |
| Cursors | oreo_black_cursors |
| Colors | Matugen (generated from wallpaper) |
| Shell | Noctalia (Catppuccin Mocha theme) |

---

## License

This configuration is personal and shared for reference. Individual components retain their own licenses.
