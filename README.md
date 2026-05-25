# Atlas

A personalized NixOS (nixos-unstable) configuration built with Home Manager, featuring the Noctalia desktop shell, enterprise-grade security hardening, gaming optimizations, and a privacy-first browsing setup.

## Overview

| Component | Choice |
|-----------|--------|
| **WM** | [Niri](https://github.com/YaLTeR/niri) (scrolling Wayland compositor) |
| **Shell** | [Noctalia](https://github.com/noctalia-dev/noctalia-shell) (Wayland desktop shell) |
| **Display Manager** | SDDM (astronaut theme, auto-login) |
| **Terminal** | [Ghostty](https://ghostty.org/) with Nushell |
| **Editor** | Neovim (LazyVim), opencode |

## Features

### Desktop Experience
- **Noctalia Shell** — Sleek Wayland desktop shell (status bar, notifications, OSD, widgets)
- **Dynamic theming** — [Matugen](https://github.com/InioX/matugen) generates colors from wallpapers, applied across GTK, Qt, and Ghostty
- **Wallpaper management** — [awww](https://github.com/end-4/awww) daemon for animated wallpapers
- **Application launcher** — [Vicinae](https://github.com/vicinaehq/vicinae)
- **Notifications** — Noctalia notification system

### Gaming & Performance
- **Steam** with [Millennium](https://github.com/SteamClientHomebrew/Millennium) theming overlay
- **PrismLauncher** (Minecraft with offline accounts)
- **Blockbench**, steamcmd
- AMD GPU with 32-bit drivers for gaming
- Intel CPU tuned with performance governor

### Privacy & Security
- **Mullvad VPN** with auto-connect + **Mullvad Browser**
- **Librewolf** as default browser
- **Lynis** security auditing
- **ClamAV** daemon with daily scans, auto-quarantine of detected threats, and desktop notifications
- **Snout** — security monitoring daemon that watches /etc/quarantine and integrates with ClamAV
- **AIDE** file integrity monitoring with daily checks
- **Quarantine** — sandboxed, locked-down directory at /etc/quarantine with 0000 permissions, chattr +a, noexec,nosuid,nodev bind mount, and automatic shredding at shutdown
- Extensive kernel hardening (sysctl, locked modules, disabled protocols, boot params)
- Systemd service sandboxing with security profiles (now properly applied)
- LUKS full-disk encryption

### Development & Tools
- Neovim (custom LazyVim config), opencode, claude-code
- bun runtime, Docker, Podman, Distrobox
- libvirtd + virt-manager (Windows 11 VM)
- Nushell with zoxide integration

### System
- **Boot** — systemd-boot (EFI) with silent Plymouth splash
- **Audio** — startup/close sound effects
- **RGB** — OpenRGB
- **Flatpak** — Flathub repository enabled
- **Ollama** — local LLM service (ROCm)
- **TCP BBR** congestion control + cake qdisc
- **Trashy** — CLI system trash manager (safer alternative to rm)

## Quick Configuration Guide

### Adding a Package

To add a system package:

1. Open `files/core/configuration.nix`
2. Find `environment.systemPackages`
3. Add the package name to the list: `pkgs.package_name`
4. Rebuild: `sudo nixos-rebuild switch --flake .#atlas`

### Adding a User Package

To add a user-level package:

1. Open `files/core/home.nix`
2. Find `home.packages`
3. Add the package
4. Rebuild Home Manager: `home-manager switch -b backup --flake .#yusa@atlas`

### Enabling/Disabling Modules

Each feature is implemented as a module. Optional modules live in a separate repo at `/home/yusa/atlas-modules` (imported via flake input). To disable:

1. Edit `files/core/configuration.nix`
2. Comment out the module import (line starting with `inputs.atlas-modules.nixosModules.`)
3. Rebuild: `sudo nixos-rebuild switch --flake .#atlas`

**WARNING**: Some modules are interdependent. Check module READMEs for dependencies.

## Troubleshooting

### USB devices not detected after inserting
- **Fix**: Usbguard may be blocking. Check: `sudo usbguard list-rules`
- Accept device: `sudo usbguard allow-device [device-id]`

### System slow after rebuild
- Check: `nix-collect-garbage -d` (removes old builds)
- Check: `systemd-analyze` (shows boot time)

### Network issues after rebuild
- Check: `sudo systemctl restart NetworkManager`
- Check firewall rules: `sudo nft list ruleset | grep -i rule`

### Module won't load
- Check syntax: `nix flake check`
- Check imports: grep the module name in configuration.nix
- View errors: `sudo journalctl -xeu systemd-nixos-setup.service`

### NixOS rebuild fails
- **First**: Run `nix flake check --show-trace` for detailed error
- **Check** file indentation (must be 2 spaces)
- **Check** balanced braces and semicolons
- **Revert**: `git checkout -- files/path/to/file.nix`

## Module Reference

See documentation in each module:
- `files/modules/security/README.md` — Security modules
- `/home/yusa/atlas-modules/dev/README.md` — Development tools
- `/home/yusa/atlas-modules/gaming/README.md` — Gaming setup
- `/home/yusa/atlas-modules/privacy/README.md` — Privacy features

## Structure

```
atlas/
├── flake.nix                           # Nix flake inputs + outputs
├── files/
│   ├── core/
│   │   ├── configuration.nix           # System-level config
│   │   ├── home.nix                    # Home Manager user config
│   │   └── hardware-configuration.nix  # Hardware-specific settings
│   ├── config/
│   │   ├── niri/                       # WM config (keybinds, layout, animations)
│   │   ├── vicinae/                    # Launcher config
│   │   └── .icons/                     # Cursor themes
│   ├── modules/
│   │   └── security/                   # Snout, ClamAV, AIDE, auditd, kernel, firewall
│   ├── lib/                            # Shared Nix library modules
│   ├── hardware/                       # CPU/GPU/audio auto-configs
│   ├── profiles/                       # System profiles (atlas, generic)
│   ├── audio/                          # Sound effects
│   └── bin/                            # Scripts (startup, fix_rgb_color)
│
├── Optional modules (separate repo):   /home/yusa/atlas-modules/
│   ├── dev/                            # Neovim, development tools
│   ├── gaming/                         # Steam, Millennium theming
│   ├── privacy/                        # Mullvad VPN + browser
│   ├── flatpak.nix                     # Flatpak packages
│   ├── minecraft.nix                   # PrismLauncher config
│   ├── performance.nix                 # CPU governor, Nix optimization
│   ├── tools.nix                       # CLI utilities
│   └── virtualisation.nix              # Docker, Podman, libvirt
```

## Security Hardening

### Kernel Hardening
- Kernel module loading locked after boot
- Pointer leak protection, kernel log restriction
- eBPF restricted, SysRq disabled
- ASLR enabled, core dumps disabled
- Boot params: slab_nomerge, init_on_alloc, pti=on, lockdown=integrity

### Network Hardening
- nftables firewall with minimal open ports
- ICMP redirects disabled, source routing disabled
- SYN cookies, reverse path filtering, martian logging

### Snout Daemon
The Snout security monitoring daemon runs as a systemd service and:
- Watches /etc/quarantine for new files via inotify
- Triggers automatic ClamAV scans on quarantined files
- Sends desktop notifications on security events
- Provides CLI interface: `snout scan`, `snout status`, `snout logs`

### Quarantine
The /etc/quarantine directory is sandboxed with:
- Permissions 0700 (root only), `chattr +a` (append-only — prevents rename/delete)
- Files inside get **0000 permissions** (no read/write/execute for anyone)
- Bound-mounted with noexec, nosuid, nodev
- Watched by a **quarantine-sanitizer** daemon that instantly strips permissions on new files
- **Shredded and wiped at every shutdown** via quarantine-cleanup systemd service
- Automatically monitored by Snout + ClamAV

### ClamAV Daemon
- Enabled as a persistent daemon with automatic updates
- Daily system scans at 3:00 AM with randomized delay
- **Auto-quarantines** detected threats: `clamscan --move=/etc/quarantine`
- Post-scan sanitization: quarantined files are immediately set to **0000 permissions**
- Separate quarantine verification scan
- Desktop notifications on threat detection and clean scans

### File Integrity (AIDE)
- Monitors /bin, /sbin, /usr, /etc, /var/lib
- Database auto-initializes on first boot
- Daily integrity checks with SHA512 checksums

## Quick Start

```bash
# First build (requires flakes enabled in /etc/nix/nix.conf)
sudo nixos-rebuild switch --flake .#atlas

# Update all inputs and rebuild
sudo nixos-rebuild switch --flake .#atlas --upgrade

# Just rebuild without updating
sudo nixos-rebuild switch --flake .#atlas
```

## Security Commands

```bash
# Snout security monitoring
snout scan          # Run security scan and report status
snout status        # Check daemon status
snout logs          # Follow daemon logs

# ClamAV
sudo systemctl start clamav-daily-scan    # Manual scan
cat /var/log/clamav/scan.log              # View scan results

# AIDE
sudo aide --check                         # Check file integrity

# Lynis audit
sudo lynis audit system --quick

# Trash management
trash put <file>        # Move file to trash
trash list              # List trashed files
trash restore <file>    # Restore from trash

# Quarantine
quarantine-list                           # List quarantined files
quarantine-purge                          # Securely shred and purge all files
sudo ls -la /etc/quarantine               # Direct listing (root only)
```

## Applications

| Category | Packages |
|----------|----------|
| **Browsers** | Librewolf (default), Mullvad Browser |
| **Gaming** | Steam (Millennium-themed), PrismLauncher, Blockbench |
| **Social** | (_via Flatpak_) |
| **Media** | mpv, mpvpaper, linux-wallpaperengine, imv |
| **Dev** | Neovim (LazyVim), opencode, claude-code, bun |
| **Security** | Snout, ClamAV, AIDE, Lynis, auditd |
| **Utilities** | Noctalia, btop, tty-clock, fzf, trashy, Nautilus |

## Theming

| Layer | Setting |
|-------|---------|
| GTK | Adwaita-dark |
| Icons | Papirus-Dark |
| Fonts | Monocraft, Roboto, Nerd Fonts, Material Design Icons |
| Cursors | oreo_black_cursors |
| Colors | Matugen (generated from wallpaper) |
| Shell | Noctalia (Catppuccin Mocha theme) |

## Key Bindings (Niri)

| Shortcut | Action |
|----------|--------|
| `Mod+T` | Open Ghostty terminal |
| `Mod+Space` | Open Vicinae launcher |
| `Mod+H/J/K/L` | Focus window (vim-style) |
| `Mod+Shift+W` | Noctalia panel toggle |
| `Print` | Screenshot |
| `Mod+Shift+E` | Quit Niri |

> See `~/.config/niri/config.kdl` for full keybinding reference.

## License

This configuration is personal and shared for reference. Individual components retain their own licenses.
