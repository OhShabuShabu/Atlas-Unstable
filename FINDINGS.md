# YoRHa NixOS Configuration — Audit Findings

---

## Resolved / Completed Work (2026-06-05)

All findings below have been verified as resolved in the current codebase.

### 2026-06-05 — Additional Verifications

- **Duplicate `splash` Kernel Parameter Removed** — `files/modules/security/kernel-boot.nix` no longer sets `splash` explicitly. `boot.plymouth.enable = true` (in `files/features/boot.nix`) provides the `splash` param via NixOS option. Re-eval confirms `boot.kernelParams` has no duplicates.

- **Duplicate `pti=on` Kernel Parameter Removed** — `files/modules/security/kernel-boot.nix` no longer sets `pti=on` explicitly. `security.forcePageTableIsolation = true` (in `files/features/hardening.nix`) provides it via NixOS option.

- **Duplicate `audit_backlog_limit=16384` Kernel Parameter Removed** — `files/modules/security/kernel-boot.nix` no longer sets `audit_backlog_limit=16384` explicitly. `security.audit.backlogLimit = 16384` (in `files/features/hardening.nix`) provides it via NixOS option.

- **Duplicate Function Header in `banner.nix` Fixed** — `files/modules/security/banner.nix` had two `{ config, lib, ... }:` headers (lines 1-2) which broke the NixOS module loader and prevented full `nix flake check` evaluation. Duplicate removed; module now evaluates cleanly.

- **Non-Existent Service References Removed from Scripts** — `files/bin/yorha-module-manager.sh` (lines 393, 1186-1188) and `files/bin/yorha-module-apply.sh` (lines 209-211) referenced `firmware-version-check`, `tpm-attestation-check`, `secureboot-verify` services that do not exist in the configuration. Removed these references (the `luks-test.nix` module still documents the intended attestation architecture with `check_service` warnings). `files/features/packages.nix` `STOPPED_SERVICES` list also cleaned up.

- **`test_security_base.sh` Updated to Match Current State** — Stale assertions for `loglevel=3`, direct `pti=on`/`audit_backlog_limit=16384` checks, HTTP 80/443 firewall ports, UDP 4000/8000 ranges, IPv6 RA=0, and YESCRYPT cost=10 replaced with checks against source-of-truth NixOS options (`boot.plymouth.enable`, `security.forcePageTableIsolation`, `security.audit.backlogLimit`, etc.). Test result: **100 PASS / 0 FAIL / 0 SKIP** (was 95/7/0).

### Infrastructure & Architecture

- **yorha-installer Duplication Eliminated** — `flake-modules/hosts.nix` now uses a `sharedModules` list included by both `yorha` and `yorha-installer` configurations, preventing module drift.

- **Duplicate Module Imports via `configuration.nix` Removed** — Verified that `configuration.nix` and `hosts.nix` no longer duplicate imports. Single source of truth maintained.

- **`noctalia` Special Arg Removed** — `specialArgs` in `hosts.nix` no longer contains `noctalia = inputs.noctalia` (unused; `inputs` attrset already contains it).

- **`aarch64-linux` Clarity** — `systems.nix` now only declares `x86_64-linux` as supported with a comment noting aarch64 is aspirational.

- **`nixpkgs-fmt` Deprecation Fixed** — `per-system.nix` now uses `nixfmt-rfc-style` (active maintainer) instead of deprecated `nixpkgs-fmt`.

- **Empty Flake Checks Fixed** — `per-system.nix` now has a `checks.lint` derivation running `statix` and `deadnix`.

### Security Hardening

- **NOPASSWD Sudo Removed** — `hardening.nix` now requires password for sudo. No more `NOPASSWD` in `extraRules`. Passwordless access is restricted to specific commands only.

- **PAM `common-password` Override Removed** — Uses `security.pam.services` with `lib.mkBefore` to add `pam_pwquality.so` alongside the existing PAM stack instead of replacing it entirely.

- **USBGuard Manual Config Override Removed** — USBGuard fully managed via `services.usbguard` NixOS options. No `environment.etc."usbguard/usbguard-daemon.conf"` override. `implicitPolicyTarget` changed from `"allow"` (no-op) to `"block"` (actual enforcement).

- **`hidepid=2` Now Has `gid=proc` Group** — `hardening.nix` sets `gid=proc` on proc mount and creates the `proc` group, allowing desktop tools (htop, btop) to function while maintaining process isolation.

- **NetworkManager-dispatcher `RestrictAddressFamilies` Uses `mkDefault`** — Can be overridden by other modules without copying the entire service config.

- **Snort Runs as Dedicated User** — `snort.nix` now creates `users.users.snort` and `users.groups.snort`. Both `snort-daemon` and `snort-monitor` run as `User = "snort"` with ambient capabilities (`CAP_NET_RAW`, `CAP_NET_ADMIN`) instead of root.

- **polkit & cups ReadWritePaths Added** — `service-hardening.nix` adds `ReadWritePaths = [ "/var/lib/polkit-1" ]` for polkit and `ReadWritePaths = [ "/var/spool/cups" "/var/log/cups" "/run/cups" ]` for cups.

- **`safe.directory = "*"` Removed** — Both `nix-config.nix` and `home.nix` now scope git directory trust to specific paths (`/nix/store`, `/etc/nixos`, `$HOME`) instead of the wildcard.

- **SSH `MaxSessions` and `TCPKeepAlive` Fixed** — `MaxSessions` set to 10 (was 2, broke VS Code Remote). `TCPKeepAlive` set to `true` (was `false`, allowed zombie connections).

- **Banner Now Includes SSH/Network** — `banner.nix` sets both `/etc/issue` (console) and `/etc/issue.net` (SSH/network) with legal warning. SSH `Banner` directive configured.

- **`sops.nix` SSH Key Fallback Added** — Added `/etc/ssh/ssh_host_rsa_key` as fallback alongside the existing `ed25519` key.

- **kernel-sysctl `accept_ra` Fixed** — Changed from `0` (breaks SLAAC IPv6) to `2` (accept RAs even with forwarding enabled).

- **kernel-sysctl `tcp_timestamps` Fixed** — Changed from `0` (breaks TCP window scaling) to `1` (preserves high-throughput performance).

- **YESCRYPT Cost Factor Increased** — `password-policy.nix` now uses cost factor `14` (was default `10`), providing ~16x stronger offline brute-force resistance.

- **`privacy.nix` No Longer Opens DNS Ports Inbound** — Removed `allowedTCPPorts = [53 853]` and `allowedUDPPorts = [53 853]` — machine no longer acts as open DNS resolver.

### Bug Fixes

- **`IMA-EVM` Dead Code Resolved** — Added `systemd.services.evm-key-setup` to register the EVM key setup script as a proper systemd service.

- **IMA Policy Duplicate `securityfs` Entry Removed** — Line `dont_measure fsmagic=0x1021994` (incorrect magic number, duplicate of selinuxfs) removed from policy.

- **AIDE `set -e` Bug Fixed** — Script now uses `set +e` before `aide --check`, captures exit code, and correctly reports change detection.

- **ClamAV Threat Count Now Accurate** — Uses current scan output (`$SCAN_RESULT`) instead of grepping the full log file. Threat list also uses current scan output.

- **TPM PCR Policy Now Consistent (0+1+7)** — Both `current-system.nix` enrollment and `luks-keyfile.nix` sealing use PCRs 0, 1, and 7.

- **`/var/log` No Longer Shredded at Shutdown** — `memory-wipe.nix` now only shreds `.gz` rotated logs in `/var/log`, preserving the active audit trail.

- **Duplicate `hardware.enableRedistributableFirmware` Removed** — Setting now only in `hardware/default.nix`.

- **Duplicate `slab_nomerge`/`slab_merge=off` Removed** — Only `slab_nomerge` kept in `kernel-boot.nix`.

- **`nohibernate` Invalid Kernel Parameter Removed** — Hibernation disabled via systemd targets (correct approach), no invalid `nohibernate` param.

- **ConsoleLogLevel Conflict Resolved** — `boot.consoleLogLevel = 0` removed; only `loglevel=3` in kernelParams used.

- **Audit Backlog Limit Matched** — `hardening.nix` now sets `security.audit.backlogLimit = 16384` to match kernel param `audit_backlog_limit=16384`.

- **DNS Consolidation** — `networking.nameservers` removed from `network.nix`. DNS fully managed by systemd-resolved via NetworkManager with Cloudflare.

- **Firewall UDP Ports Updated** — `firewall.nix` now has accurate port ranges for Steam (27000-27100) and Discord (50000-65535) instead of non-standard ranges.

- **Initrd TPM Detection Cleaned Up** — `boot.nix` now uses `builtins.pathExists` without redundant `tryEval` wrapper, matching the pattern used by hardware detection modules.

- **Initrd Kernel Modules Use `mkAfter`** — `boot.nix` now uses `lib.mkAfter` for initrd kernel modules to prevent overwriting auto-detected modules from `hardware-configuration.nix`.

- **`openrgb` Service Now Copies Color File to Writable Location** — Uses `ExecStartPre` to copy `primary_color.txt` from the immutable Nix store to `%t/primary_color.txt` before runtime access.

- **Swapfile Creation Btrfs-Fixed** — Uses `touch` instead of `truncate -s 0` before setting nodatacow, properly handling btrfs CoW interaction.

- **Swapfile Has `persistent.mount` Dependency** — `create-swapfile` service now has `after` and `requires` on `persistent.mount`, ensuring correct boot ordering.

- **Docker `iptables = true` Restored** — Docker now manages its own firewall rules (was `iptables = false` without nftables replacement). Log rotation also configured.

### Maintainability

- **`hardware.memory.totalMB` Cascade Fixed** — `swapSizeMB` and `tmpfsPercent` now reference `config.hardware.memory.totalMB` via the config block, so overrides to `totalMB` cascade to swap and tmpfs settings.

- **Hardcoded `users` Group Parameterized** — `preservation.nix` tmpfiles entries now use `config.users.users.${userName}.group` instead of hardcoded `"users"`.

- **`hasVirtualization` Now Checks CPU Flags** — Detects actual `vmx`/`svm` CPU flags from `/proc/cpuinfo` instead of assuming virtualization based on vendor presence.

- **nix-ld Libraries Explicit** — `nix-config.nix` now configures `programs.nix-ld.libraries` with specific libraries instead of leaving it unrestricted.

- **`max-jobs`/`cores` Safer** — `nix.settings.cores` changed from `0` (all cores per build) to `4` to prevent resource exhaustion during builds.

- **`xsettingsd` Dead Config Removed** — The unused `xsettingsd/Xwayland.conf` home-manager config removed since `xsettingsd` is not installed.

- **Metadata Stripper Preserves Orientation** — Both watcher and daily scan scripts now preserve EXIF orientation tag (via `-TagsFromFile @ -Orientation -n`) after stripping all other metadata.

- **ClamAV Service Hardening Added** — Now includes `ProtectSystem`, `PrivateDevices`, `RestrictNamespaces`, `CapabilityBoundingSet`, and other systemd sandboxing options.

- **ClamAV On-Access Comment** — Added explanatory comment for why `clamonacc.enable = false` (unstable kernel).

- **Password Policy README Synced** — Updated README from "14 characters" to "12 characters" to match actual `PASS_MIN_LEN` setting.

- **`allowUnfree` Documented** — Added comment in `nix-config.nix` listing modules that depend on unfree packages.

- **Metadata Stripper Uses Parameterized Home Path** — Uses `config.users.users.yusa.home` instead of hardcoded `/home/yusa`.

- **Firewall UDP Port Ranges Accurate** — Updated to Steam (27000-27100) and Discord (50000-65535).

- **CPU Virtualization Detection Accurate** — Now checks `vmx`/`svm` CPU flags instead of inferring from vendor.

- **Hardcoded User Paths Parameterized** — ClamAV, Snort, and metadata stripper use NixOS config references.

---

## Active Findings

## TPM PCR Policy Mismatch Between Enrollment and Keyfile Unseal

**Severity: Critical**
**Category: Bug**

### Problem

The system has two independent TPM-based LUKS unlocking mechanisms. The `current-system.nix` enrollment uses `--tpm2-pcrs=0+1+7` while `luks-keyfile.nix` sealing also uses PCRs `sha256:0,1,7`. These are now consistent (both use 0+1+7).

However, the TPM keyfile unlock path at boot still fails: the system logs `Failed to activate, key file '/run/luks-keyfile' missing` during early boot. This means the TPM-sealed keyfile approach in `luks-keyfile.nix` is non-functional despite the correct PCR selection.

### Recommendation

Investigate why the initrd does not successfully unseal and present the keyfile at boot. Ensure `boot.initrd.secrets` properly includes the sealed keyfile path and that systemd-cryptsetup can unseal it.

---

## Module Registry Shell Script Downloads and Sources Unverified Remote Code

**Severity: Critical**
**Category: Security**

### Problem

`module-registry.sh` downloads a shell script from GitHub and `source`s it directly after stripping `readonly` markers. An attacker who compromises the upstream repository (or performs MITM) can inject arbitrary code. The `sed -i 's/^readonly //'` even removes safety measures from the remote file before execution.

### Evidence

- `files/lib/module-registry.sh:568-581` — `fetch_remote_registry()` downloads and sources remote script
- `files/lib/module-registry.sh:573` — `sed -i 's/^readonly //'` strips safety from remote file
- No checksum or signature verification

### Recommendation

Verify a checksum of the downloaded script before sourcing, or use a signed delivery mechanism.

---

## `services.logind.settings` Duplicates Functionality Already Disabled via systemd Targets

**Severity: Low**
**Category: Maintainability**

### Problem

The memory-wipe module disables systemd sleep targets and then also sets `services.logind.settings` to ignore sleep keys. The systemd target disabling already prevents sleep/hibernate — the logind settings are redundant.

### Recommendation

Remove the logind settings or add a comment explaining they serve as defense-in-depth (kernel-level target disable vs user-space input event handling).

---

## `odysseus` Flake Input Is Marked `flake = false` with Hardcoded Source

**Severity: Medium**
**Category: Maintainability**

### Problem

The `odysseus` flake input is marked as `flake = false`, importing it as a raw source tree. However, `odysseus.nix` uses `pkgs.fetchFromGitHub` with a different hardcoded revision instead of referencing the flake input. Updating the flake input has no effect on the actual deployment.

### Recommendation

Replace the hardcoded `fetchFromGitHub` call with the flake input.

---

## Module Registry `readModuleState = { }` Makes Disable Mechanism Ineffective at Nix Level

**Severity: High**
**Category: Bug**

### Problem

`readModuleState` always returns an empty attrset, meaning at Nix evaluation time all modules appear "enabled". Disabling a module via the TUI/CLI only works if the module file is removed from disk.

### Recommendation

Document clearly that module disabling requires file removal, or implement a build-time state mechanism.

---

## `networking.useDHCP = false` Overrides NixOS Default

**Severity: Low**
**Category: Documentation**

### Problem

`networking.useDHCP = false` globally disables the default per-interface DHCP that NixOS provides. The system relies entirely on NetworkManager for all network connectivity. A comment now documents this as intentional.

### Recommendation

This is an intentional design choice (NetworkManager exclusively manages networking). No change needed, but keep the documentation comment in place.

---

## ClamAV On-Access Scanning Disabled Despite Full Configuration

**Severity: Low**
**Category: Documentation**

### Problem

`clamonacc.enable = false` disables on-access scanning, but all `OnAccess*` configuration parameters are still present. A comment explains this is due to kernel instability.

### Recommendation

The dead configuration parameters could be removed for clarity, or left as future-ready configuration with the comment explaining why they're inactive.

---

## Snort IDS Daemon and Snout Watcher May Be Inactive

**Severity: High**
**Category: Reliability**

### Problem

Previous investigation found `snort-daemon` and `snout-watcher` services were `inactive` on the running system despite being enabled. This needs verification on the current build.

### Recommendation

Run `systemctl status snort-daemon snout-watcher` and `journalctl -u snort-daemon -u snout-watcher` to diagnose.
