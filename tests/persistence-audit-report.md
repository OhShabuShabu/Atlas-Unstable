# Atlas Persistence Audit Report

**Date:** 2026-05-28  
**System:** Atlas NixOS (impermanent — `/`, `/home`, `/tmp` on tmpfs)  
**Persistence Backend:** `preservation` (nix-community module) + btrfs subvols  
**Persistent Storage:** `/persistent` (bind-mount origin), `/var` (btrfs subvol)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    FILESYSTEM LAYOUT                         │
├──────────────────────┬──────────────────────────────────────┤
│  Tmpfs (ephemeral)   │  Btrfs on LUKS (persistent)          │
├──────────────────────┼──────────────────────────────────────┤
│  /                   │  /nix      — Nix store               │
│  /home               │  /var      — Service state / logs    │
│  /tmp                │  /persistent — Bind-mount origin     │
│  /run                │                                      │
│  /sys                │  /boot (vfat ESP, not tmpfs)         │
│  /proc               │                                      │
└──────────────────────┴──────────────────────────────────────┘

Preservation mechanism:
  /persistent/etc/ssh/       → bind-mount → /etc/ssh/
  /persistent/etc/machine-id → bind-mount → /etc/machine-id
  /persistent/root/.ssh/     → bind-mount → /root/.ssh/
  /persistent/home/yusa/... → bind-mount → /home/yusa/...
  /var/lib/*                 → already on persistent btrfs subvol
```

---

## 2. Persistence Paths by Priority

### 2.1 CRITICAL — System breaks or data loss without persistence

| Path | Type | Why | Implementation |
|------|------|-----|----------------|
| `/etc/ssh/` | system | SSH host keys — regenerating every boot triggers MITM warnings on every SSH connection | preservation bind-mount from `/persistent/etc/ssh/` |
| `/etc/machine-id` | file | System identity — changes every boot without persistence. Affects DNS caching, DHCP leases, DBUS, journald | preservation in-initrd bind-mount from `/persistent/etc/machine-id` |
| `/etc/nixos/` | system | Symlink to flake — rebuilds fail without it | preservation bind-mount from `/persistent/etc/nixos/` |
| `/root/.ssh/` | system | Root SSH keys — required for any automated SSH operations as root | preservation bind-mount from `/persistent/root/.ssh/` |
| `/root/.gnupg/` | system | Root GPG trust — required if root signs or verifies anything | preservation bind-mount from `/persistent/root/.gnupg/` |
| `~/.ssh/` | user | User SSH keys — primary authentication for git, SSH, rsync | preservation bind-mount, mode 0700 |
| `~/.gnupg/` | user | GPG keys + trust db — signing commits, decrypting files | preservation bind-mount, mode 0700 |
| `~/.password-store/` | user | `pass` password store — all credentials stored here | preservation bind-mount, mode 0700 |
| `~/.local/state/nix/` | user | Nix profile state — without this, `nix profile list` breaks and nix commands may not find installed packages | preservation bind-mount |
| `~/.local/state/home-manager/` | user | HM generation registry — HM activation breaks on reboot without this | preservation bind-mount |

### 2.2 RECOMMENDED — Significant usability loss without persistence

| Path | Type | Why | Implementation |
|------|------|-----|----------------|
| `~/.local/share/keyrings/` | user | GNOME/secret-service keyrings — stores app passwords, wifi passwords | preservation bind-mount |
| `~/.local/share/flatpak/` | user | Full flatpak installations + runtimes — without this, ALL flatpak apps must be re-installed after every reboot (~2-10GB download) | preservation bind-mount (replaces previous partial persistence) |
| `~/.var/` | user | Flatpak app data — per-app state (configs, caches, databases) | preservation bind-mount |
| `~/.steam/` | user | Steam game data + configs — without this, Steam re-downloads everything (~50-200GB for typical library) | preservation bind-mount |
| `~/.bash_history` | file | Shell command history — loses all command recall on every reboot | preservation bind-mount |
| `~/.local/state/nushell/` | user | Nushell history, command completions, scrollback | preservation bind-mount |
| `~/.local/share/mullvad-vpn/` | user | Mullvad VPN account data, daemon state | preservation bind-mount |

### 2.3 OPTIONAL — Nice to have, improves UX

| Path | Type | Why | Implementation |
|------|------|-----|----------------|
| `~/.config/mpv/` | user | MPV player config, input.conf, watch_later resume state | preservation bind-mount |
| `~/.config/btop/` | user | Btop theme + layout preferences | preservation bind-mount |
| `~/.config/VSCodium/` | user | VSCodium settings, extensions, workspace state | preservation bind-mount |
| `~/.local/share/fonts/` | user | User-installed fonts (not managed by nix) | preservation bind-mount |
| `~/.cache/awww/` | user | Wallpaper cache — prevents re-downloading on each boot | preservation bind-mount |
| `~/.direnv/` | user | direnv allow state — without this, `direnv allow` needed on every dir after reboot | preservation bind-mount |
| `~/.local/share/nvim/` | user | Neovim state — site extensions, swap files, shuttle history | preservation bind-mount |
| Folder structure dirs | user | `~/Desktop/`, `~/Documents/`, `~/Downloads/`, etc. | preservation bind-mount |

### 2.4 PERSISTENT VIA `/var` (btrfs subvol — no changes needed)

| Path | Service | Why |
|------|---------|-----|
| `/var/log/` | All services | Audit logs, snort alerts, ClamAV scan results, AIDE reports, snout events, metadata stripping logs, journald |
| `/var/lib/clamav/` | ClamAV | Virus signature database (~200MB) — huge download every boot without persistence |
| `/var/lib/aide/` | AIDE | File integrity database — must persist to detect changes across boots |
| `/var/lib/NetworkManager/` | NetworkManager | WiFi connection profiles, secrets, device state |
| `/var/lib/systemd/` | systemd | Timesync clock state, random seed, backlight state |
| `/var/lib/usbguard/` | USBGuard | USB device allowlist rules — regenerated on every boot if not persisted |
| `/var/lib/rsyslog/` | Rsyslog | Log buffer state |
| `/var/account/` | Process accounting | Process accounting data (`pacct`) |
| `/var/db/sudo/` | sudo | Sudo lecture timestamps — re-lectured on every boot if not persisted |
| `/var/lib/mullvad-vpn/` | Mullvad | VPN daemon operational data |
| `/var/lib/docker/` | Docker (if enabled) | Container images, volumes, overlay state |
| `/var/lib/podman/` | Podman (if enabled) | Container images, volumes |
| `/var/lib/libvirt/` | libvirt (if enabled) | VM images, network configs, storage pools |

---

## 3. Security Assessment

### 3.1 Sensitive Persistence (with mitigations)

| Path | Sensitivity | Risk | Mitigation |
|------|-------------|------|------------|
| `~/.ssh/` | **HIGH** — private keys | Persisted unencrypted on disk | LUKS encryption at rest; mode 0700; full disk encryption |
| `~/.gnupg/` | **HIGH** — private keys | Persisted unencrypted on disk | LUKS encryption at rest; mode 0700 |
| `~/.password-store/` | **HIGH** — all passwords | Persisted unencrypted on disk | LUKS encryption at rest; mode 0700; main passphrase is GPG key |
| `/etc/ssh/` | **HIGH** — host private key | Persisted unencrypted on disk | LUKS encryption at rest; mode 0600 |
| `~/.local/share/keyrings/` | **MEDIUM** — service passwords | Persisted on disk | LUKS at rest; login keyring unlocks at login |
| `/var/lib/NetworkManager/` | **MEDIUM** — WiFi passwords | Persisted on `/var` | LUKS encryption; NetworkManager encrypts secrets |
| `~/.local/share/mullvad-vpn/` | **MEDIUM** — VPN account token | Persisted on disk | LUKS at rest |
| `~/.bash_history` | **LOW** — command history | Could leak commands | LUKS at rest; no passwords in history assumed |

### 3.2 What is NOT persisted (by design)

| Path | Reason |
|------|--------|
| `/tmp/*` | Temporary files — cleaned every boot |
| `/var/tmp/*` | System temp — cleaned periodically by systemd |
| `/run/*` | Runtime state — volatile by nature |
| `~/.cache/*` (except awww) | General caches safe to lose; can bloat significantly |
| `~/.local/share/Trash/` | Desktop trash — temporary by nature |
| `~/.npm/`, `~/.cargo/`, `~/.go/` | Build caches — re-downloaded as needed |
| `~/.local/share/recently-used.xbel` | File history — privacy concern |
| `~/.thumbnails/` | Thumbnail caches — regenerated on demand |
| `/etc/quarantine/` | Quarantined malware — securely wiped at shutdown |
| `~/Downloads/` **content** | Downloads folder persisted BUT contents survive. Ephemeral if not explicitly managed. User responsibility. |
| Browser caches | Regenerated; privacy benefit to ephemeral |
| nix store (`/nix/`) | Already on persistent `/nix` subvol — no bind-mount needed |
| Secret tokens that expire | Regenerated by services (e.g., DHCP lease, VPN session) |

---

## 4. What Changed vs Previous Configuration

### 4.1 Added to persistence

| Path | Priority | Why it was missing |
|------|----------|-------------------|
| `~/.gnupg/` | CRITICAL | Overlooked — previously only `.ssh/` was persisted |
| `~/.password-store/` | CRITICAL | Overlooked — necessary for pass users |
| `/root/.ssh/` | CRITICAL | Overlooked — root SSH for automation |
| `/root/.gnupg/` | CRITICAL | Overlooked — root GPG |
| `~/.local/state/nushell/` | RECOMMENDED | Shell history lost every boot |
| `~/.local/share/flatpak/` (full) | RECOMMENDED | Previously only partial config; full directory persisted now |
| `~/.local/share/mullvad-vpn/` | RECOMMENDED | VPN account state lost every boot |
| `~/.config/mpv/` | OPTIONAL | Missing — playlists, config, watch_later state |
| `~/.config/btop/` | OPTIONAL | Missing — theme config |
| `~/.config/VSCodium/` | OPTIONAL | Missing — editor state |
| `~/.local/share/fonts/` | OPTIONAL | User fonts lost every boot |
| `~/.cache/awww/` | OPTIONAL | Wallpaper cache — previously created at HM activation but immediately lost |
| `~/.direnv/` | OPTIONAL | direnv allow state lost |
| `~/.local/share/nvim/` | OPTIONAL | Neovim site extensions + state lost |

### 4.2 Already persisted (no change needed)

| Path | Priority | Status |
|------|----------|--------|
| `~/.ssh/` | CRITICAL | Already persisted with mode 0700 |
| `~/.local/state/nix/` | CRITICAL | Already persisted |
| `~/.local/state/home-manager/` | CRITICAL | Already persisted |
| `~/.local/share/keyrings/` | RECOMMENDED | Already persisted |
| `~/.steam/` | RECOMMENDED | Already persisted |
| `~/.var/` | RECOMMENDED | Already persisted |
| `~/.bash_history` | RECOMMENDED | Already persisted |
| Folder structure dirs | RECOMMENDED | Already persisted |
| `/etc/ssh/` | CRITICAL | Already persisted |
| `/etc/machine-id` | CRITICAL | Already persisted with inInitrd |
| `/etc/nixos/` | CRITICAL | Already persisted |

### 4.3 Removed from previous config

None — all previously persisted paths are retained.

---

## 5. Files Modified

| File | Change |
|------|--------|
| `files/core/preservation.nix` | Complete rewrite — added all missing persistence paths, organized by priority, added documentation of /var persistence and explicitly ephemeral paths |
| `test_config.sh` | Added section 25 — 47 new persistence validation tests |
| `tests/validate-persistence.sh` | NEW — runtime persistence validation script (run on live system after reboot) |

---

## 6. Validation

### 6.1 Static tests (test_config.sh)

```
PASS: 485  FAIL: 0  WARN: 21 (all from missing atlas-modules repo, not persistence-related)
```

### 6.2 Runtime validation (validate-persistence.sh)

Run after rebuild and reboot:
```bash
sudo bash tests/validate-persistence.sh
```

Checks performed:
1. Filesystem mount types (tmpfs vs btrfs verification)
2. Preservation bind-mount activity count
3. System identity persistence (SSH keys, machine-id)
4. Service state on `/var` (ClamAV, AIDE, NM, etc.)
5. User credential persistence (SSH, GPG, pass)
6. Application/Flatpak/gaming state
7. Permission verification (0700 on ~/.ssh, ~/.gnupg; 0600 on ssh host keys; 0444 on machine-id)

### 6.3 Rebuild safety

The `atlas-rebuild` script (in configuration.nix) stops tamper-detection services before rebuild:
```
snort-daemon, snort-monitor, snout-watcher, aide-check, 
firmware-version-check, tpm-attestation-check, secureboot-verify, mullvad-daemon
```

---

## 7. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| SSH host key changed after reboot | `/etc/ssh` bind-mount failed | Check `/persistent/etc/ssh/` exists; check `systemctl status` for preservation mount units |
| Home-manager activation fails | `~/.local/state/home-manager/` bind-mount failed | Check `/persistent/home/yusa/.local/state/home-manager/` exists |
| Flatpak apps missing after reboot | Flatpak dir not persisted | Check `~/.local/share/flatpak/` is listed in preservation config |
| GPG keys missing | `~/.gnupg/` bind-mount failed | Check `/persistent/home/yusa/.gnupg/` exists; copy keys from backup |
| No WiFi networks found | NetworkManager state on `/var` subvol corrupted | `sudo rm -rf /var/lib/NetworkManager/*` then reboot |
| AIDE check fails | AIDE database missing on `/var` | `sudo systemctl start aide-init` to regenerate |

---

## 8. Future Considerations

1. **Container state**: If Docker/Podman/libvirt are enabled in atlas-modules, their directories on `/var/lib/` are already persistent via the `/var` subvol. No additional config needed.

2. **Browser profiles**: If Firefox/Librewolf are added, `~/.mozilla/` or `~/.librewolf/` should be added to the persistence list.

3. **Development language caches**: If persistent build caches are desired (npm, cargo, go), they can be added to `userCacheDirs` but this increases disk usage.

4. **Machine-specific secrets**: Add sops-managed secrets to `files/secrets/secrets.yaml` using `sops files/secrets/secrets.yaml`. Never write plaintext secrets to Nix files.
