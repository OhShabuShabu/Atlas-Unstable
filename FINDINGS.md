# YoRHa NixOS Configuration — Audit Findings

---

## Resolved / Implemented Changes

### ✅ TPM PCR Policy Now Consistent (0+1+7)

**Status: Resolved** — The code already uses `--tpm2-pcrs=0+1+7` (current-system.nix:149), matching the `luks-keyfile.nix` PCR selection `sha256:0,1,7`. Both mechanisms consistently use PCRs 0, 1, and 7.

### ✅ /var/log No Longer Shredded at Shutdown

**Status: Fixed** — `memory-wipe.nix` now only shreds `.gz` rotated logs in `/var/log`, preserving active audit trail for post-incident analysis.

### ✅ NOPASSWD Sudo Removed (Password Required)

**Status: Fixed** — `hardening.nix` now requires password for sudo. Passwordless sudo is restricted to `nixos-rebuild` and `su` only.

### ✅ PAM common-password Override Removed

**Status: Already Fixed in Code** — The `environment.etc."pam.d/common-password"` override that replaced the entire PAM stack with only `pam_pwquality.so` is not present in the current codebase. PAM authentication is intact.

### ✅ USBGuard Manual Config Override Removed

**Status: Already Fixed in Code** — The `environment.etc."usbguard/usbguard-daemon.conf"` manual override that bypassed NixOS module options is not present in the current codebase. USBGuard is fully managed via NixOS options.

### ✅ Duplicate `hardware.enableRedistributableFirmware` Removed

**Status: Fixed** — Removed from `boot.nix:51`. Setting is now only in `hardware/default.nix:12`.

### ✅ IMA/EVM Dead Code — evmKeyService Registered

**Status: Fixed** — Added `systemd.services.evm-key-setup` to register the EVM key setup script as a proper systemd service in `ima-evm.nix`.

### ✅ IMA Policy Duplicate Securityfs Entry Removed

**Status: Fixed** — Removed the erroneous `0x1021994` entry from `ima-evm.nix:26` (duplicate of `0x01021994` selinuxfs).

### ✅ AIDE `set -e` Bug Fixed

**Status: Fixed** — `aide.nix` script now uses `set +e` before `aide --check`, captures exit code, and correctly reports change detection.

### ✅ ClamAV Threat Count Uses Current Scan Only

**Status: Fixed** — `clamav.nix` now captures scan output directly and counts threats from current scan, not from historical log entries. Uses `${config.users.users.yusa.home}` instead of hardcoded `/home/yusa`.

### ✅ Metadata Stripper Uses Parameterized Home Path

**Status: Fixed** — `metadata-stripper.nix` uses `config.users.users.yusa.home` instead of hardcoded `/home/yusa`.

### ✅ Duplicate `slab_nomerge`/`slab_merge=off` Removed

**Status: Fixed** — Removed `slab_merge=off` from `kernel-boot.nix:47`. Only `slab_nomerge` is kept.

### ✅ `nohibernate` Invalid Kernel Parameter Removed

**Status: Fixed** — Removed `boot.kernelParams = [ "nohibernate" ]` from `memory-wipe.nix:115`. Hibernation is properly disabled via systemd targets.

### ✅ ConsoleLogLevel Conflict Resolved

**Status: Fixed** — Removed `loglevel=3` from `kernel-boot.nix:20`. Only `boot.consoleLogLevel = 0` is used as the canonical NixOS setting.

### ✅ Audit Backlog Limit Matched

**Status: Fixed** — `hardening.nix:20` now sets `security.audit.backlogLimit = 16384` to match the kernel param `audit_backlog_limit=16384`.

### ✅ DNS Consolidation (Quad9 Removed)

**Status: Fixed** — Removed `networking.nameservers` from `network.nix`. DNS is fully managed by systemd-resolved via NetworkManager. Resolved is configured with Cloudflare in `hardening.nix`.

---

## Active Findings

## TPM PCR Policy Mismatch Between Enrollment and Keyfile Unseal

Severity: Critical
Category: Bug

### Problem

The system has two independent TPM-based LUKS unlocking mechanisms that use **different PCR policies**, meaning they will never agree on the same TPM state. One mechanism unseals successfully while the other will consistently fail at boot.

### Evidence

- `files/core/current-system.nix:148` — TPM enrollment via `systemd-cryptenroll` uses PCRs `0+7`
- `files/modules/security/luks-keyfile.nix:21-22` — TPM keyfile sealing/unsealing uses PCRs `sha256:0,1,7` (PCR set `0,1,7`)
- `files/modules/security/luks-keyfile.nix:140` — PCR policy creation uses `sha256:0,1,7`

The `current-system.nix` enrollment binds LUKS slot to PCRs 0+7. The `luks-keyfile.nix` creates a TPM-sealed keyfile bound to PCRs 0+1+7. These are different PCR selections — `systemd-cryptenroll` stores its policy internally in the LUKS header metadata, while `tpm2-tools` stores it in the sealed blob. Both will produce valid-but-different TPM policies.

If both mechanisms are active simultaneously, they create two independent TPM policies that can both succeed independently. However, if the user expects them to interoperate or be interchangeable, the PCR mismatch (missing PCR 1 in one, including PCR 1 in the other) means firmware updates or boot config changes that alter PCR 1 will break only the keyfile approach while `systemd-cryptenroll` remains functional.

More critically, the **order of operations matters**: `current-system.nix:124` checks for an existing `systemd-tpm2` token, but does not check for the `luks-keyfile.nix` sealed blob. If the user runs both mechanisms, they get two independent TPM auth paths with different sensitivity to PCR changes.

### Recommendation

Either make the PCR sets consistent or document explicitly that they are independent fallback paths. If they should use the same PCR set, change one to match the other:

Option A: Make `current-system.nix` use PCRs `0+1+7` to match the keyfile:
```
--tpm2-pcrs=0+1+7
```

Option B: Make `luks-keyfile.nix` use PCRs `0+7` to match cryptenroll:
```
pcrSelection = "sha256:0,7";
```

### Expected Benefit

Eliminates silent TPM unlock failures on firmware/boot config changes that alter PCR 1. Provides consistent, predictable TPM behavior regardless of which mechanism handles the unlock.

---

## NOPASSWD Sudo Rule Contradicts Security Posture and Nullifies Password Policy

Severity: Critical
Category: Security

### Problem

The sudo configuration enables `execWheelOnly` (restricting sudo to wheel group) while simultaneously granting **passwordless sudo for all commands** to the entire wheel group via `extraRules`. This means:
1. Any user in the `wheel` group can run any command as root without authentication
2. The password policy (faillock, YESCRYPT, min length, aging) is effectively moot for privilege escalation
3. The login banner's "authorized access only" warning is bypassable

### Evidence

- `files/features/hardening.nix:57` — `security.sudo.execWheelOnly = true;`
- `files/features/hardening.nix:59-68` — `security.sudo.extraRules` with NOPASSWD for ALL commands for wheel group
- `files/modules/security/password-policy.nix` — comprehensive password policy (YESCRYPT, faillock, min length, aging)
- `files/features/user.nix:8` — user yusa is in the `wheel` group

The `execWheelOnly` option prevents non-wheel users from using sudo at all. The `extraRules` then grants ALL commands NOPASSWD to wheel users. Combined, this means: only wheel users can run sudo, but they never need a password. The password policy, faillock lockout, and aging settings provide no meaningful protection against unauthorized sudo access from any process running as the yusa user.

### Recommendation

Remove the NOPASSWD rule and require password authentication for sudo. If passwordless access is needed for specific operations, limit it to specific commands rather than `ALL`:

```nix
security.sudo.extraRules = [
  {
    groups = [ "wheel" ];
    commands = [
      { command = "ALL"; options = [ "SETENV" ]; }
    ];
  }
];
```

For specific passwordless needs, use targeted rules:
```nix
commands = [
  { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
];
```

### Expected Benefit

Password policy provides actual security — sudo requires the user's password, faillock can lock out attackers, and the login banner is meaningful. Reduces blast radius from any compromise of the yusa user session.

---

## Active Memory Wipe Destroys Audit Logs Before Shutdown Can Complete

Severity: High
Category: Security

### Problem

The shutdown memory wipe service (`shutdown-wiper`) shreds ALL files in `/var/log/` at shutdown, which destroys the very audit trail that the extensive security infrastructure is designed to create. This means:
1. Post-incident forensic analysis is impossible — log files are destroyed before persistent storage is powered off
2. AIDE integrity check history is lost on every shutdown
3. Auditd logs, ClamAV scan results, Snort alerts, and Snout events are all shredded
4. The `shutdown-wiper` runs AFTER `dram-wiper`, which itself tries to drop caches — making the log shredding even less useful since memory is already being cleared

### Evidence

- `files/modules/security/memory-wipe.nix:47-51` — Shreds ALL files in `/var/log/`:
  ```bash
  find /var/log -type f ! -name "*.gz" -exec shred -vfz -n 1 {} \; 2>/dev/null || true
  ```
- `/var/log` is on the persistent btrfs subvol per `files/core/preservation.nix:203-214`
- The system has a comprehensive audit infrastructure: auditd, AIDE, ClamAV, Snort, Snout, rsyslog
- The files `files/modules/security/auditd-config.nix`, `aide.nix`, `clamav.nix`, `snort.nix`, `snout.nix` all write valuable audit data to `/var/log/`

### Recommendation

Restrict log shredding to truly volatile paths (tmpfs) and sensitive runtime data only. Remove `/var/log` from the shred targets:

```nix
find /run -type f -size -1M -exec shred -vfz -n 1 {} \; 2>/dev/null || true
find /tmp -type f -exec shred -vfz -n 1 {} \; 2>/dev/null || true
```

If privacy/anti-forensics is a genuine requirement, implement targeted log rotation with encryption rather than wholesale destruction. Add a configuration option to control this behavior.

### Expected Benefit

Audit logs survive shutdown, enabling post-incident forensic analysis. The entire security monitoring investment (AIDE, auditd, Snort, ClamAV, Snout) produces useful long-term telemetry rather than data that self-destructs on every power-off.

---

## Conflicting DNS Resolver Configuration

Severity: High
Category: Bug

### Problem

The system configures two independent DNS resolver settings that conflict with each other. `networking.nameservers` sets Quad9 (9.9.9.9) for the glibc stub resolver, while systemd-resolved is configured with Cloudflare (1.1.1.1). The net result is that DNS queries from different sources may route to different resolvers, causing inconsistent resolution behavior.

### Evidence

- `files/features/network.nix:35-38` — `networking.nameservers = [ "9.9.9.9" "149.112.112.112" ]` (Quad9)
- `files/features/hardening.nix:209-219` — `services.resolved.settings.DNS = [ "1.1.1.1" "1.0.0.1" ]` (Cloudflare)

When `services.resolved.enable = true`, the `networking.nameservers` setting is typically ignored by applications using systemd-resolved's stub resolver (at 127.0.0.53). However, the `networking.nameservers` setting still takes effect for:
- The systemd-resolved fallback DNS server list (if the stub resolver fails)
- Non-systemd-resolved-aware applications
- The NetworkManager DNS configuration (which has its own resolv.conf)

### Recommendation

Consolidate to a single DNS provider and remove the duplicate setting:

```nix
# Remove networking.nameservers entirely, or make it match systemd-resolved
networking.nameservers = lib.mkForce [ "1.1.1.1" "1.0.0.1" ];
```

Or alternatively, keep Quad9 as the primary and update systemd-resolved:
```nix
services.resolved.settings.DNS = [ "9.9.9.9" "149.112.112.112" ];
```

### Expected Benefit

Consistent DNS resolution from a single provider. Eliminates confusion about which DNS service is actually being used for privacy and security purposes.

---

## Duplicate `hardware.enableRedistributableFirmware` Setting

Severity: Medium
Category: Maintainability

### Problem

The `hardware.enableRedistributableFirmware` option is set to `true` in two separate modules with identical priority, creating a redundant configuration that could silently diverge over time.

### Evidence

- `files/features/boot.nix:51` — `hardware.enableRedistributableFirmware = true;`
- `files/hardware/default.nix:12` — `hardware.enableRedistributableFirmware = true;`

Both use the default priority (1000), so there's no conflict, but the duplication means:
- If someone changes one to `false`, the other still forces `true`, leading to confusion
- Future maintainers may not realize the setting is controlled from two locations
- `boot.nix` is a feature module (should be for boot-related config), while `hardware/default.nix` is the natural home for this setting

### Recommendation

Remove from `files/features/boot.nix:51` and keep only in `files/hardware/default.nix`. The hardware module is the correct place for this setting since it's about allowing non-redistributable firmware for hardware drivers.

### Expected Benefit

Single source of truth for firmware policy. Future changes won't accidentally leave a stale duplicate.

---

## `networking.useDHCP = false` Overrides NixOS Default but Lacks Explicit Interface Configuration

Severity: Medium
Category: Bug

### Problem

Setting `networking.useDHCP = false` globally disables the default per-interface DHCP that NixOS provides. If NetworkManager is not running (or fails to start) on a particular interface, the interface will have no IP configuration and no automatic fallback.

### Evidence

- `files/features/network.nix:5` — `networking.useDHCP = false;`
- `files/features/network.nix:3` — `networking.networkmanager.enable = true;`

NixOS documentation states that with `networking.useDHCP = false`, you must either use NetworkManager, or explicitly configure networking for each interface. The system relies entirely on NetworkManager for all network connectivity. If NetworkManager fails or is stopped, there is no fallback network access.

### Recommendation

Either:
1. Remove `networking.useDHCP = false` and let NixOS manage DHCP as fallback (NetworkManager will override per-interface with its own settings), or
2. Add documentation/comment explaining that NetworkManager is the sole network manager and DHCP via networkd is intentionally disabled.

The first option is safer — NetworkManager will still handle all connections, but if it fails, the kernel's DHCP client via networkd can restore connectivity.

### Expected Benefit

Resilient network configuration. If NetworkManager encounters an issue, the system retains network access via NixOS-managed DHCP.

---

## Firewall UDP Port Range Defaults May Not Match Gaming/VoIP Usage

Severity: Medium
Category: Reliability

### Problem

The default allowed UDP port range (4000-4007, 8000-8010) is documented as "Common VoIP range" and "gaming range," but these do not match actual VoIP or gaming service port usage. Major VoIP services and games use diverse port ranges:
- Discord: UDP 50000-65535 (voice)
- Steam: UDP 27000-27036, 27015 (matchmaking)
- Most games use ephemeral ports via UDP hole-punching

The documented ranges (4000-4007) don't correspond to any major service and create a false sense of "gaming/VoIP support" while potentially blocking actual game/VoIP traffic.

### Evidence

- `files/modules/security/firewall.nix:16-19` — `defaultUdpPorts = [ { from = 4000; to = 4007; } { from = 8000; to = 8010; } ]`
- Comment says "Common VoIP range" and "Additional gaming range"

### Recommendation

Either remove the default UDP ranges (rely on ephemeral ports and connection tracking for established connections) or update them to match actual service needs documented in comments:

```nix
defaultUdpPorts = [
  # Steam matchmaking + voice
  { from = 27000; to = 27100; }
  # Discord voice
  { from = 50000; to = 65535; }
];
```

### Expected Benefit

Either accurate port ranges that actually work with intended services, or clean defaults that don't pretend to support services they don't actually cover.

---

## Initrd TPM Kernel Module Detection at Build Time Returns Wrong Results

Severity: High
Category: Bug

### Problem

The `boot.nix` module uses `builtins.pathExists "/sys/class/tpm/tpm0"` at **build time** to decide whether to include TPM kernel modules in the initrd. This check runs during `nixos-rebuild`, not during boot. If the system is rebuilt on a machine with a TPM (common), the initrd will include TPM modules, but the initrd build happens on the build machine, and the run-time check is also at build time.

More critically, `tryEval` does NOT catch `builtins.pathExists` errors in pure evaluation mode (as documented in comments), so the `tryEval` wrapper is completely redundant.

### Evidence

- `files/features/boot.nix:14-15` — `builtins.tryEval (builtins.pathExists "/sys/class/tpm/tpm0")`
- `files/features/boot.nix:19-22` — Same pattern for `kernelModules`
- `files/hardware/detect/cpu.nix:24-28` — Correctly handles pure eval with `pathExists` without `tryEval`
- `files/hardware/detect/gpu.nix:21-23` — Same correct pattern
- `files/hardware/detect/memory.nix:23-25` — Same correct pattern

The detection modules (`hardware/detect/*`) correctly use just `builtins.pathExists` without `tryEval`. The boot module wraps it in `tryEval` which is both unnecessary and incorrect — `pathExists` returns `false` in pure mode without error, so `tryEval` adds no value.

### Recommendation

Replace the `tryEval` pattern in `files/features/boot.nix` with the same pattern used by the hardware detection modules:

```nix
let tpmPresent = builtins.pathExists "/sys/class/tpm/tpm0";
in lib.mkIf tpmPresent [ "tpm_tis" "tpm_crb" "tpm" ]
```

Or better, reference the already-detected TPM state from the hardware detect modules rather than re-detecting.

### Expected Benefit

Cleaner code that follows the established pattern in the codebase. Eliminates unnecessary `tryEval` wrappers that add confusion without value.

---

## `networking.nameservers` Conflicts with systemd-resolved When Enabled

Severity: Medium
Category: Bug

### Problem

When `services.resolved.enable = true` (as set in `hardening.nix`), systemd-resolved manages `/etc/resolv.conf` via its stub resolver. However, `networking.nameservers` in `network.nix` still sets Quad9 nameservers. Depending on the `services.resolved.fallbackDns` setting and the symlink target of `/etc/resolv.conf`, different applications may use different DNS servers.

### Evidence

- `files/features/network.nix:35-38` — `networking.nameservers` set to Quad9
- `files/features/hardening.nix:209-219` — `services.resolved.settings.DNS` set to Cloudflare
- `files/features/hardening.nix:210` — `services.resolved.enable = true`

The `networking.nameservers` setting is used by NixOS to create a plain `/etc/resolv.conf` (non-systemd-resolved managed). When systemd-resolved is also enabled, there's a configuration race — one of them will win depending on module ordering.

### Recommendation

This is related to the earlier DNS finding. Consolidate to remove the `networking.nameservers` setting when systemd-resolved is active. The systemd-resolved DNS setting already handles both the primary DNS and the fallback.

### Expected Benefit

Predictable DNS resolution; no race condition between two resolver configurations.

---

## `nixpkgs.config.allowUnfree` Required by Multiple Modules but Only Set Once

Severity: Low
Category: Maintainability

### Problem

Multiple modules depend on `allowUnfree = true` but the setting is only in `nix-config.nix`. There is no indication that removing or disabling this global setting will break:
- NVIDIA GPU driver (`files/hardware/gpu/nvidia.nix`)
- SDDM nier-automata theme (`files/features/packages.nix`)
- Any unfree packages in optional modules

### Evidence

- `files/features/nix-config.nix:23` — `nixpkgs.config.allowUnfree = true;`
- `files/hardware/gpu/nvidia.nix:9` — Comment notes "Requires allowUnfree = true"
- `files/features/packages.nix:53-65` — SDDM theme fetched from GitHub (not unfree, but depends on other unfree packages)
- The Mullvad VPN module (`files/modules/optional/nixos/privacy.nix`) — Mullvad package is unfree

### Recommendation

No code change needed, but add a comment in `nix-config.nix` listing which modules depend on unfree packages:

```nix
# Required by: nvidia.nix (GPU driver), privacy.nix (Mullvad),
# packages.nix (nautilus patch may be unfree depending on overlay)
nixpkgs.config.allowUnfree = true;
```

Alternatively, use `allowUnfreePredicate` for more granular control instead of the blanket allow.

### Expected Benefit

Future maintainers can understand the impact of disabling unfree packages without hunting through the entire codebase.

---

## `hardware-configuration.nix` Boot Kernel Modules Duplicated in `boot.nix`

Severity: Low
Category: Maintainability

### Problem

The auto-generated `hardware-configuration.nix` already sets `boot.initrd.availableKernelModules` from `nixos-generate-config`, but `boot.nix` overrides or extends this list. The generated file includes `vmd`, `xhci_pci`, `ahci`, `nvme`, `usbhid`, `usb_storage`, `sd_mod`, while `boot.nix` conditionally adds TPM modules and `overlay`/`xt_addrtype`. There's no conflict, but the split makes it unclear which modules are auto-detected vs manually specified.

### Evidence

- `files/core/hardware-configuration.nix:11` — Auto-detected modules
- `files/features/boot.nix:14-15` — TPM modules (conditional)
- `files/features/boot.nix:17` — `initrd.kernelModules = [ "overlay" "xt_addrtype" ]`

The `initrd.kernelModules` in `boot.nix` uses default priority (1000), which means it **replaces** any modules from `hardware-configuration.nix` (also priority 1000) — the auto-detected modules could be dropped depending on evaluation order.

### Recommendation

Use `lib.mkBefore` or `lib.mkAfter` for the manually specified initrd kernel modules to ensure they are additive, not overwriting:

```nix
boot.initrd.kernelModules = lib.mkAfter [ "overlay" "xt_addrtype" ];
boot.initrd.availableKernelModules = lib.mkAfter (
  lib.optionals (tpmPresent.success && tpmPresent.value) [ "tpm_tis" "tpm_crb" "tpm" ]
);
```

### Expected Benefit

Auto-detected kernel modules from `hardware-configuration.nix` are preserved even if module evaluation order changes. Reduces risk of boot failures after hardware changes.

---

## `systemd.services.NetworkManager-dispatcher` Hardening May Break Functionality

Severity: Medium
Category: Reliability

### Problem

The `NetworkManager-dispatcher` service hardening in `hardening.nix` sets `ProtectHome = lib.mkDefault true` and `RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ]`. The dispatcher runs scripts on network state changes, which often need access to user home directories (disconnect scripts, VPN helpers) and additional address families.

### Evidence

- `files/features/hardening.nix:103-114` — NetworkManager-dispatcher service hardening
- `files/features/hardening.nix:106` — `ProtectHome = lib.mkDefault true`

Using `mkDefault` for `ProtectHome` means other modules can override it, which is good. But `RestrictAddressFamilies` is set directly (not mkDefault), so dispatcher scripts that need e.g. `AF_BLUETOOTH` for Bluetooth tethering or `AF_PACKET` for raw socket access will silently fail.

### Recommendation

Document the restriction or use `mkDefault` for the address families as well:

```nix
RestrictAddressFamilies = lib.mkDefault [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
```

### Expected Benefit

Easier debugging when NetworkManager dispatcher scripts fail. Other modules can override the restriction without copying the entire service config.

---

## `services.logind.settings` Duplicates Functionality Already Disabled via systemd Targets

Severity: Low
Category: Maintainability

### Problem

The memory wipe module disables systemd sleep targets (`suspend.target`, `hibernate.target`, etc.) and then also sets `services.logind.settings` to ignore sleep keys. The systemd target disabling already prevents sleep/hibernate — the logind settings are redundant. Having them in two places means future changes might update only one.

### Evidence

- `files/modules/security/memory-wipe.nix:116-119` — Disables systemd sleep targets
- `files/modules/security/memory-wipe.nix:121-131` — Sets HandleSuspendKey/HibernateKey/LidSwitch to "ignore"

### Recommendation

Remove one of the two mechanisms. The systemd target disable is more robust (kernel-level), while logind settings handle user-space input events. Either keep both with a comment explaining they serve different purposes, or remove the logind settings since disabling the targets is sufficient:

```nix
# Redundant — sleep targets already disabled above
# services.logind.settings.Login = { ... };
```

### Expected Benefit

Cleaner code with one mechanism for disabling sleep. Eliminates confusion about which setting actually prevents hibernation.

---

## `create-swapfile` Service Btrfs Compatibility Issue

Severity: High
Category: Reliability

### Problem

The swapfile creation service uses `fallocate` on a btrfs filesystem. On btrfs, `fallocate` creates a sparse file, but swapfiles on btrfs require a **non-sparse** (preallocated) file. The `nodatacow` attribute (set via `chattr +C`) is set correctly, but `fallocate` without the `--keep-size` flag on btrfs may create a reflinked/deduplicated file that the kernel cannot use as swap.

### Evidence

- `files/core/current-system.nix:102` — `fallocate -l ${toString swapSize}M /persistent/swapfile`
- `files/core/current-system.nix:101` — `chattr +C /persistent/swapfile` (applied after truncation, but before data written)

The btrfs documentation for swapfiles requires:
1. `chattr +C` on an empty file (done, but `truncate -s 0` only works if the file is on a fresh subvol)
2. No CoW, compression, or snapshots on the file
3. The file must be completely allocated (use `fallocate` with `--keep-size` is wrong here)

The `truncate -s 0` followed by `chattr +C` followed by `fallocate` is the correct approach for btrfs, but the `truncate -s 0` may not actually disable CoW if the file already existed with data. The `rm -f` at line 99 should handle this, but `truncate -s 0` after the fact is redundant.

### Recommendation

Simplify the swapfile creation:
```bash
rm -f /persistent/swapfile
touch /persistent/swapfile
chattr +C /persistent/swapfile
fallocate -l ${toString swapSize}M /persistent/swapfile
chmod 0600 /persistent/swapfile
mkswap /persistent/swapfile
```

Use `touch` instead of `truncate -s 0` to create the empty file before `chattr +C`. `truncate -s 0` can interact poorly with btrfs CoW on existing files.

### Expected Benefit

Reliable swapfile creation on btrfs. No risk of the kernel rejecting the swapfile due to sparse allocation or CoW attributes.

---

## `cleanOnBoot` Enabled Without tmpfs Override for `/tmp`

Severity: Low
Category: Architecture

### Problem

`boot.tmp.cleanOnBoot = true` is enabled alongside a tmpfs `/tmp` mount. Since tmpfs is already wiped on every reboot, the `cleanOnBoot` setting is redundant for `/tmp`. It only affects files under `/var/tmp/` (persistent temp).

### Evidence

- `files/features/boot.nix:53` — `boot.tmp.cleanOnBoot = true;`
- `files/core/current-system.nix:50-55` — `/tmp` mounted as tmpfs (wiped on reboot automatically)

### Recommendation

Either:
1. Remove `boot.tmp.cleanOnBoot` since tmpfs handles `/tmp` clearing and systemd-tmpfiles handles `/var/tmp` cleanup, or
2. Keep it as an explicit safety net with a comment explaining it primarily affects `/var/tmp`.

### Expected Benefit

Reduced confusion about which mechanism clears which temporary directory.

---

## `hardware.memory.totalMB` Option Uses Default Priority That Can't Be Overridden

Severity: Medium
Category: Bug

### Problem

The `hardware.memory.totalMB` option in `memory.nix` is defined with a fixed `default` value. The `nix-config.nix` module references `config.hardware.memory.totalMB` to dynamically adjust Nix settings, but if the memory detection fails (e.g., in CI or sandboxed builds), the default falls back to 2048. However, the `swapSizeMB` and `tmpfsPercent` options also use the same detection logic but recalculate independently — they don't reference `config.hardware.memory.totalMB`, meaning overriding `totalMB` in a configuration does NOT cascade to swap and tmpfs calculations.

### Evidence

- `files/hardware/detect/memory.nix:72-78` — `swapSizeMB` default uses its own `totalMB` variable, not `config.hardware.memory.totalMB`
- `files/hardware/detect/memory.nix:87-93` — `tmpfsPercent` default uses its own `totalMB` variable, not `config.hardware.memory.totalMB`
- `files/features/nix-config.nix:11-17` — References `config.hardware.memory.totalMB`

This is a Nix module pattern issue: options depend on other options' defaults at the Nix level but the defaults are calculated from a local variable rather than from the option value itself. If a user sets `hardware.memory.totalMB = lib.mkForce 16384`, the swap and tmpfs settings still use the original detected value.

### Recommendation

Make `swapSizeMB` and `tmpfsPercent` depend on `config.hardware.memory.totalMB` in their defaults:

```nix
swapSizeMB = lib.mkOption {
  type = lib.types.int;
  default = (config.hardware.memory.totalMB / 4);  # 25% of total
  ...
};
```

Wait, this would cause infinite recursion because of the mutual dependency. A proper solution is to move the calculation into a `config` block that references the option:

```nix
config = lib.mkIf (config.hardware.memory.totalMB >= 32768) {
  hardware.memory.swapSizeMB = lib.mkDefault 8192;
};
```

### Expected Benefit

When users override `hardware.memory.totalMB`, the swap and tmpfs settings automatically adjust. Consistent behavior without surprise manual overrides.

---

## systemd Service Uses Hardcoded `users` Group Instead of `config.users.users.yusa.group`

Severity: Low
Category: Maintainability

### Problem

The systemd-tmpfiles configuration in `preservation.nix` hardcodes `group = "users"` instead of referencing the user's primary group from the user configuration. If the user's primary group is changed (e.g., to `wheel` or a custom group), the tmpfiles entries will not match.

### Evidence

- `files/core/preservation.nix:167-197` — All tmpfiles entries use `group = "users"`
- `files/core/preservation.nix:4` — `userName = "yusa"` is correctly parameterized

### Recommendation

Add a `userGroup` variable:
```nix
userGroup = config.users.users.${userName}.group or "users";
```

Then use `${userGroup}` in all tmpfiles group fields. This matches the parameterization pattern already established for `userName` and `userHome`.

### Expected Benefit

Consistent parameterization. Changes to user's primary group automatically propagate to tmpfiles configuration.

---

## `hasVirtualization` Option Logic Error

Severity: Low
Category: Bug

### Problem

The `hardware.cpu.hasVirtualization` option default is `detected != "generic"`, meaning it's `true` when a known CPU vendor is detected and `false` for generic/unknown. However, virtualization support (VMX for Intel, SVM for AMD) is not guaranteed even with a detected vendor — older Intel Atom CPUs and some embedded AMD CPUs lack virtualization extensions despite being genuine Intel/AMD.

### Evidence

- `files/hardware/detect/cpu.nix:52-58` — `hasVirtualization = detected != "generic"`

### Recommendation

Either:
1. Rename the option to `hasKnownVendor` to accurately reflect what it measures, or
2. Check for the actual CPU virtualization flag from `/proc/cpuinfo`:
```nix
hasVirtualization = let
  hasVMX = builtins.match ".*vmx.*" cpuInfo != null;
  hasSVM = builtins.match ".*svm.*" cpuInfo != null;
in hasVMX || hasSVM;
```

### Expected Benefit

Accurate virtualization detection. Modules relying on this option won't assume virtualization on known-vendor CPUs that lack it.

---

## Swap File Path References `/persistent/swapfile` But No Dependency Ensures Mount Order

Severity: Medium
Category: Reliability

### Problem

The swap device definition in `current-system.nix` references `/persistent/swapfile`, but there is no explicit dependency ensuring that `/persistent` is mounted before the swap service starts. The `create-swapfile` service has `before` dependencies on the swap target, but the swap device itself may not have a dependency on the `persistent.mount` unit.

### Evidence

- `files/core/current-system.nix:82-84` — `swapDevices = [{ device = "/persistent/swapfile"; }]`
- `files/core/current-system.nix:86-108` — `create-swapfile` service with ordering

The NixOS swap device abstraction creates a `persistent-swapfile.swap` unit automatically. This unit must be ordered after `persistent.mount`. If it's not, the systemd mount dependency chain could attempt to activate swap before `/persistent` is mounted.

### Recommendation

Ensure `persistent-swapfile.swap` has `Requires` and `After` dependencies on `persistent.mount`:

```nix
systemd.services."create-swapfile" = {
  after = [ "persistent.mount" ];
  requires = [ "persistent.mount" ];
  ...
};
```

### Expected Benefit

Swap is activated in the correct order — after `/persistent` is mounted. Eliminates a potential boot-time failure where the swapfile doesn't exist yet.

---

## Sops-nix `hasYusaPasswordHash` Detection Reads Full Secrets File at Build Time

Severity: Medium
Category: Security

### Problem

The sops module reads the full contents of the encrypted `secrets.yaml` file into build-time Nix evaluation via `builtins.readFile`. While the file is encrypted with SOPS/age, Nix will store the full file contents in the Nix store as a build dependency, making the encrypted blob accessible to anyone who can read the Nix store.

### Evidence

- `files/modules/security/sops.nix:4-8` — `builtins.readFile secretsFile`

The `secretsFile` is `../../secrets/secrets.yaml` (a SOPS-encrypted file). The `builtins.readFile` call reads the entire file into a variable during Nix evaluation, which means the encrypted content ends up in the Nix store at a path like `/nix/store/<hash>-source/secrets/secrets.yaml`. While the content is encrypted, its presence in the store is unnecessary — the decryption happens later via the `sops` service at runtime.

### Recommendation

Avoid reading the secrets file at build time. Instead, use `builtins.pathExists` to check if the file exists (which doesn't read its contents), and configure the sops module to always include the entry — the sops service handles missing keys at runtime gracefully:

```nix
let
  secretsFile = ../../secrets/secrets.yaml;
  secretsExist = builtins.pathExists secretsFile;
in {
  sops = lib.mkIf secretsExist {
    defaultSopsFile = secretsFile;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.yusa-password-hash.neededForUsers = true;
  };
}
```

If the password hash entry is absent from the SOPS file, the decryption still succeeds (just without that key), which is safe. And if the secrets file doesn't exist at all, `sops-nix` handles that gracefully too.

### Expected Benefit

Reduced information disclosure in Nix store. The encrypted secrets file doesn't need to be readable at build time — only at runtime during system activation.

---

## `odysseus` Flake Input Is Marked `flake = false` with Hardcoded Source

Severity: Medium
Category: Maintainability

### Problem

The `odysseus` flake input is marked as `flake = false`, importing it as a raw source tree. However, the `odysseus.nix` optional module uses a **different**, hardcoded GitHub source (different owner/repo/rev) instead of referencing the flake input. This means the optional module and the flake input are inconsistent — updating the flake input has no effect on the actual deployment.

### Evidence

- `flake.nix:32-35` — `odysseus` input from `pewdiepie-archdaemon/odysseus` with `flake = false`
- `files/modules/optional/nixos/odysseus.nix:50-56` — Uses `pkgs.fetchFromGitHub` with `pewdiepie-archdaemon/odysseus` at a different revision

The flake input has rev `e163384015ef0ba7fd8573a4cb0069d294e0933b` while the module hardcodes rev `1c9623a81d63a1ec4d28bef54082e6b1d3766eb6`. These are different revisions.

### Recommendation

Replace the hardcoded `fetchFromGitHub` call with the flake input:

```nix
source = lib.mkOption {
  type = lib.types.package;
  default = inputs.odysseus;
  description = "Odysseus source tree (from flake input)";
};
```

Then pass `inputs` to the module's `specialArgs` or use the flake's module system to make it available.

### Expected Benefit

Single source of truth for the Odysseus source. Flake input updates propagate to the deployment. No divergence between the lock file and the module.

---

## `clamav-daily-scan` Script Uses `grep -c "FOUND"` on LOG_FILE After Append

Severity: Medium
Category: Bug

### Problem

The ClamAV daily scan script appends output to `$LOG_FILE` and then immediately reads from it via `grep -c "FOUND"`. However, `clamscan` writes all results to the log file, and the `| tail -50` pipes only the last 50 lines to the log. The `grep` searches the full log file (including previous runs), potentially reporting stale detections from prior scans. Additionally, the `>>` redirect with `tail -50` means if `clamscan` produces more than 50 lines of output, lines indicating "FOUND" may be missed entirely.

### Evidence

- `files/modules/security/clamav.nix:70` — `--log="$LOG_FILE" $SCAN_DIRS 2>&1 | tail -50 >> "$LOG_FILE"`
- `files/modules/security/clamav.nix:72` — `grep -c "FOUND" "$LOG_FILE"`

The output goes to the log file via `--log="$LOG_FILE"` AND via the pipe/tail redirect. This duplicates content and the tail truncation can drop the FOUND messages.

### Recommendation

Restructure the script to separate scanning from logging:

```bash
RESULT=$($CLAMSCAN --recursive ... --log="$LOG_FILE" $SCAN_DIRS 2>&1; echo "EXIT:$?")
echo "$RESULT" | tail -50 >> "$LOG_FILE"
THREATS=$(echo "$RESULT" | grep -c "FOUND" || true)
```

### Expected Benefit

Accurate threat detection count from the current scan only, not from stale log entries. No truncation of scanner output that contains critical FOUND messages.

---

## `cleanOnBoot = true` with tmpfs `/tmp` Has No Effect

Severity: Low
Category: Maintainability

### Problem

The `boot.tmp.cleanOnBoot` option controls whether NixOS cleans `/tmp` on boot. Since `/tmp` is already mounted as tmpfs (in `current-system.nix`), it's inherently empty on every boot. The setting is redundant and may confuse maintainers into thinking it provides additional cleanup.

### Evidence

- `files/features/boot.nix:53` — `boot.tmp.cleanOnBoot = true;`
- `files/core/current-system.nix:50-55` — `/tmp` on tmpfs
- `files/core/disko.nix:36-42` — `/tmp` on tmpfs (installer)

`boot.tmp.cleanOnBoot` is documented to clean `/tmp` on boot. With tmpfs, `/tmp` is always empty because tmpfs is volatile. The setting still has a minor effect on `/var/tmp` (which is on the persistent btrfs subvol).

### Expected Benefit

Remove stale configuration. The `boot.tmp.cleanOnBoot` primarily affects `/var/tmp` now, which should be made explicit.

---

## Overlay Module Uses `flake.modules.nixos` Path Which Is Non-Standard

Severity: Low
Category: Architecture

### Problem

The overlay module uses `flake.modules.nixos.nautilus-overlay` to register an overlay, a non-standard pattern in the NixOS ecosystem. Standard overlays are configured via `nixpkgs.overlays` directly in the nixosConfigurations module list. The custom `flake.modules.nixos` abstraction adds complexity without clear benefit for a single overlay.

### Evidence

- `flake-modules/overlay.nix:2` — `flake.modules.nixos.nautilus-overlay`
- `flake-modules/hosts.nix:25` — `nixos.nautilus-overlay` in module imports

### Recommendation

Move the overlay directly into the hosts or keep the current pattern but add documentation for the `flake.modules.nixos` abstraction. Consider whether this indirection is needed for more overlays in the future.

### Expected Benefit

Simpler architecture if no additional flake-module overlays are planned.

---

## `yorha-installer` Configuration Duplicates `yorha` Almost Entirely

Severity: Medium
Category: Maintainability

### Problem

The `yorha-installer` nixosConfiguration in `hosts.nix` duplicates nearly all modules from `yorha` (22/27 modules are identical), differing only in adding disko and excluding `current-system.nix`. The shared module list is repeated verbatim. This creates a maintenance burden — any module added to `yorha` must be manually added to `yorha-installer`, and any module removed from one must be removed from both.

### Evidence

- `flake-modules/hosts.nix:24-50` — `yorha` modules (27 items)
- `flake-modules/hosts.nix:57-83` — `yorha-installer` modules (25 items, 22 identical)

### Recommendation

Extract the shared module list into a variable and use concatenation:

```nix
let
  sharedModules = [
    nixos.nautilus-overlay
    nixos.boot
    nixos.network
    nixos.nix-config
    nixos.user
    nixos.desktop
    nixos.packages
    nixos.hardening
    nixos.fonts
    nixos.virtualisation
    inputs.preservation.nixosModules.default
    inputs.sops-nix.nixosModules.sops
    ./../files/core/configuration.nix
    ./../files/core/preservation.nix
    ./../files/core/hardware-configuration.nix
    ./../files/hardware/default.nix
    ./../files/profiles/default.nix
    ./../files/modules/security/default.nix
    ./../files/modules/security/snort.nix
    ./../files/modules/security/snout.nix
    ./../files/modules/optional/nixos
    ./../files/modules/module-manager/default.nix
    inputs.home-manager.nixosModules.home-manager
    (mkHomeManagerConfig inputs)
  ];
in {
  flake.nixosConfigurations = {
    yorha = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = sharedModules ++ [
        ./../files/core/current-system.nix
      ];
    };
    yorha-installer = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = sharedModules ++ [
        inputs.disko.nixosModules.disko
        ./../files/core/disko.nix
      ];
    };
  };
}
```

### Expected Benefit

Single source of truth for shared modules. Adding/removing modules affects both configurations automatically. Reduced chance of divergent configurations.

---

## `openrgb` Service Depends on Runtime-Writable File in Nix Store

Severity: High
Category: Bug

### Problem

The OpenRGB systemd user service reads `${./../config/primary_color.txt}` at build time, which embeds the Nix store path of the color file. This file is read-only in the Nix store. If Matugen (or any other process) is expected to update this color file at runtime, the service will always read the stale build-time value and fail silently.

### Evidence

- `files/features/desktop.nix:71` — `$(tr -d "#" < ${./../config/primary_color.txt})` — resolves to store path at build time

The `primary_color.txt` file in `files/config/` is copied into the Nix store and becomes immutable. If `primary_color_template.txt` is the template and the actual file needs runtime updates, this won't work.

### Recommendation

If the color file needs runtime updates, copy it to a writable location at boot:
```nix
systemd.user.services.openrgb = {
  serviceConfig = {
    ExecStartPre = "${pkgs.coreutils}/bin/cp -f ${./../config/primary_color.txt} /run/primary_color.txt";
    ExecStart = "${pkgs.bash}/bin/bash -c 'sleep 12 && ${pkgs.openrgb}/bin/openrgb -d 0 -c $(${pkgs.python3}/bin/python3 ${./../bin/python/fix_rgb_color.py} $(tr -d "#" < /run/primary_color.txt))'";
  };
};
```

### Expected Benefit

OpenRGB service uses the current color value even if the configuration is updated between rebuilds.

---

## IMA/EVM Module Contains Dead Code — EVM Key Service Never Executes

Severity: High
Category: Bug

### Problem

The `ima-evm.nix` module defines an `evmKeyService` script (lines 80-136) that generates and loads the EVM HMAC key into the kernel keyring, but this script is never referenced in the module's `config` block. No `systemd.services` entry is created to run it. The EVM key infrastructure described in the module header is completely non-functional — EVM key generation and loading will never happen automatically at boot.

### Evidence

- `files/modules/security/ima-evm.nix:80-136` — `evmKeyService` script defined in `let` block
- `files/modules/security/ima-evm.nix:139-173` — `config` block only contains kernel params, packages, and the `evm-sign-binary` helper — no reference to `evmKeyService`
- Module header (lines 9-10) states "EVM key infrastructure is set up but EVM enforcement is NOT enabled by default" — this is inaccurate; the infrastructure is defined but never activated

### Recommendation

Add a systemd service to execute the key setup script at boot:

```nix
systemd.services.evm-key-setup = {
  description = "EVM HMAC key generation and loading";
  after = [ "local-fs.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${evmKeyService}";
  };
};
```

### Expected Benefit

EVM key infrastructure actually functions as intended. The EVM log-only mode (`evm=fix`) will have a key loaded in the kernel keyring, which is necessary before switching to `evm=enforce` in the future.

---

## IMA Policy Contains Duplicate/Incorrect Filesystem Magic Number

Severity: Medium
Category: Bug

### Problem

The IMA measurement policy in `ima-evm.nix` contains a duplicate `dont_measure` entry with an incorrect magic number. Line 26 uses `0x1021994` which is missing a leading zero compared to line 25's `0x01021994` (selinuxfs). The comment claims this is `securityfs`, but the actual securityfs magic (`0x73636673`) is already correctly listed on line 31. This line is a no-op that duplicates the selinuxfs entry.

### Evidence

- `files/modules/security/ima-evm.nix:25` — `dont_measure fsmagic=0x01021994  # selinuxfs`
- `files/modules/security/ima-evm.nix:26` — `dont_measure fsmagic=0x1021994   # securityfs` ← wrong magic, wrong comment
- `files/modules/security/ima-evm.nix:31` — `dont_measure fsmagic=0x73636673  # securityfs` ← correct entry

### Recommendation

Remove line 26 entirely — it's a duplicate of line 25 with a typo:

```nix
dont_measure fsmagic=0x01021994  # selinuxfs
# dont_measure fsmagic=0x1021994 was here — removed (duplicate of selinuxfs)
dont_measure fsmagic=0x9fa0      # procfs
```

### Expected Benefit

Cleaner IMA policy with no misleading entries. Reduces confusion during security audits of the measurement policy.

---

## AIDE Check Script Has Unreachable Change Detection Due to `set -e`

Severity: High
Category: Bug

### Problem

The AIDE daily check script uses `set -e` (exit on error) but then checks `$?` after the `aide --check` command. With `set -e`, if AIDE returns a non-zero exit code (which it does when changes are detected), the script terminates immediately. The `if [ $? -eq 0 ]` block on line 106 is **unreachable** — AIDE change alerts are never generated.

### Evidence

- `files/modules/security/aide.nix:96` — `set -e`
- `files/modules/security/aide.nix:104` — `${pkgs.aide}/bin/aide --check >> "$LOG_FILE" 2>&1`
- `files/modules/security/aide.nix:106` — `if [ $? -eq 0 ]; then` ← unreachable when aide returns non-zero

When AIDE detects changes, `aide --check` exits with code 1 (or higher). `set -e` kills the script before reaching the `$?` check. The "WARNING: Changes detected" message and notification on line 109 never execute.

### Recommendation

Remove `set -e` or use `|| true` to capture the exit code:

```bash
set +e
${pkgs.aide}/bin/aide --check >> "$LOG_FILE" 2>&1
AIDE_EXIT=$?
set -e

if [ "$AIDE_EXIT" -eq 0 ]; then
  echo "No changes detected" >> "$LOG_FILE"
else
  echo "WARNING: Changes detected! Review $LOG_FILE" | tee /dev/stderr
fi
```

### Expected Benefit

AIDE tamper detection actually produces alerts. Security monitoring for file integrity changes becomes functional instead of silently succeeding.

---

## LUKS Keyfile Auto-Enrollment Hangs Indefinitely Waiting for Passphrase Input

Severity: High
Category: Bug

### Problem

The `luks-keyfile-auto-enroll.sh` script calls `cryptsetup luksAddKey` without providing the existing LUKS passphrase on stdin. The `luksAddKey` command prompts for the current passphrase interactively. Since this runs as a systemd oneshot service with no TTY, it will hang indefinitely waiting for input, eventually timing out.

### Evidence

- `files/modules/security/luks-keyfile.nix:209` — `"${pkgs.cryptsetup}/bin/cryptsetup" luksAddKey "$LUKS_DEV" "$RAW_KEY" 2>/dev/null`
- `files/modules/security/luks-keyfile.nix:270-284` — Service config has `TimeoutStartSec = "30s"` and `Type = "oneshot"`
- The script uses `set -euo pipefail` (line 168), so the timeout will cause a service failure

The `luksAddKey` command requires the existing passphrase to authorize adding a new key. Without piping the passphrase via `--key-file` or stdin, the command blocks on stdin read.

### Recommendation

Either:
1. Use the TPM-sealed keyfile itself as the authorization key (since it's already unsealed in initrd and available at `/run/luks-keyfile-raw`):
```bash
"${pkgs.cryptsetup}/bin/cryptsetup" luksAddKey "$LUKS_DEV" "$RAW_KEY" \
  --key-file="$RAW_KEY" --key-slot=1
```

2. Or remove the auto-enrollment and keep it as a manual step (which the script already documents):
```nix
# Remove the systemd service, keep only the manual script
environment.systemPackages = [ generateScriptPackage ];
```

### Expected Benefit

LUKS keyfile enrollment either works automatically or fails fast instead of hanging. The TPM-based unlock path becomes reliable.

---

## ClamAV Service Has Minimal Hardening While Running as Root

Severity: Medium
Category: Security

### Problem

The `clamav-daemon` systemd service runs with only `NoNewPrivileges = true` and `Restart = "on-failure"`. It has full filesystem access, no sandboxing, and runs as the clamav user (default) but with no capability restrictions. Compared to other hardened services in the codebase (snout-watcher has 15+ hardening options), ClamAV is significantly under-protected. If ClamAV's on-access scanner is exploited via a crafted file, the attacker gets broad system access.

### Evidence

- `files/modules/security/clamav.nix:37-42` — Only `NoNewPrivileges` and `Restart`
- `files/modules/security/snout.nix:110-128` — 15+ hardening options for comparison
- ClamAV processes untrusted input (files from the filesystem) — high attack surface

### Recommendation

Add systemd sandboxing to clamav-daemon:

```nix
systemd.services.clamav-daemon = {
  serviceConfig = {
    Restart = "on-failure";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RemoveIPC = true;
    CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" "CAP_FOWNER" ];
    SystemCallArchitectures = "native";
  };
};
```

### Expected Benefit

If ClamAV is exploited, the attacker's capabilities are significantly restricted. Defense-in-depth for a service that processes untrusted input.

---

## ClamAV Daily Scan Threat Count Includes Historical Log Entries

Severity: Medium
Category: Bug

### Problem

The ClamAV daily scan script determines threat count by grepping the full log file for "FOUND" strings. Since the log file persists across scans (appended to, not truncated), the count includes threats from previous scans. A system with 0 new threats but 3 historical threats will report 3 threats found, generating false alerts.

### Evidence

- `files/modules/security/clamav.nix:72` — `THREATS=$(grep -c "FOUND" "$LOG_FILE" 2>/dev/null || echo "0")`
- `files/modules/security/clamav.nix:62` — `echo "=== ClamAV Scan $(date) ===" >> "$LOG_FILE"` (appends, doesn't truncate)
- The `clamscan --log="$LOG_FILE"` on line 70 also appends results to the same file

### Recommendation

Use the scan output directly instead of grepping the log file. Capture clamscan's stdout and parse it:

```bash
SCAN_OUTPUT=$($CLAMSCAN --recursive --detect-pua=yes \
  --exclude-dir=... --move="$QUARANTINE" \
  --log="$LOG_FILE" $SCAN_DIRS 2>&1)

THREATS=$(echo "$SCAN_OUTPUT" | grep -c "FOUND" || true)
THREAT_LIST=$(echo "$SCAN_OUTPUT" | grep "FOUND" | sed 's/: .* FOUND//' | head -3 | tr '\n' ' ')
```

### Expected Benefit

Accurate threat count from the current scan only. No false alerts from historical log entries.

---

## `hidepid=2` on `/proc` Breaks Desktop Process Visibility

Severity: Medium
Category: Reliability

### Problem

The `hidepid=2` mount option on `/proc` prevents users from seeing other users' processes. While this is a security hardening measure, it breaks common desktop tools and system monitoring: `btop`, `htop`, `ps aux` (showing all processes), `systemd-cgtop`, and process management in desktop environments. The `systemd-logind` service and Polkit also need to inspect processes for seat management.

### Evidence

- `files/features/hardening.nix:100` — `options = [ "nosuid" "noexec" "nodev" "hidepid=2" ];`
- No `group=proc` option is set, so no group is given access to see other processes

### Recommendation

Either downgrade to `hidepid=1` (processes can see each other but `/proc/<pid>/` is restricted) or add a `proc` group with read access:

```nix
fileSystems."/proc" = {
  device = "proc";
  fsType = "proc";
  options = [ "nosuid" "noexec" "nodev" "hidepid=2" "gid=proc" ];
};
# And create the proc group:
users.groups.proc = {};
# Add relevant users to the group:
users.users.yusa.extraGroups = [ ... "proc" ];
```

### Expected Benefit

Desktop tools function correctly while maintaining process isolation for unprivileged users not in the `proc` group.

---

## USBGuard Config Silently Overrides NixOS-Generated Daemon Config

Severity: Medium
Category: Bug

### Problem

The `hardening.nix` module configures USBGuard via the NixOS service options (`services.usbguard`), but then also writes a manual `environment.etc."usbguard/usbguard-daemon.conf"` that replaces the NixOS-generated config file. The NixOS options (`implicitPolicyTarget`, `IPCAllowedUsers`, etc.) are evaluated and used to generate a config, but the manual `environment.etc` file overwrites it completely. The NixOS options become meaningless — any future change to `services.usbguard.*` won't take effect.

### Evidence

- `files/features/hardening.nix:160-168` — `services.usbguard` with NixOS options
- `files/features/hardening.nix:170-179` — `environment.etc."usbguard/usbguard-daemon.conf"` with manual text

The manual config at line 170-179 duplicates the same values as the NixOS options but is written as raw text, bypassing the module system entirely.

### Recommendation

Remove the manual `environment.etc` override and keep only the NixOS service options:

```nix
# REMOVE lines 170-179
services.usbguard = {
  enable = true;
  rules = "allow";
  implicitPolicyTarget = "allow";
  presentDevicePolicy = "apply-policy";
  IPCAllowedUsers = [ "root" "yusa" ];
  IPCAllowedGroups = [ "wheel" ];
  dbus.enable = true;
};
```

### Expected Benefit

USBGuard configuration is managed through the NixOS module system. Changes to `services.usbguard.*` options take effect. No silent overrides.

---

## PAM `common-password` Override Replaces Entire File

Severity: High
Category: Bug

### Problem

The `environment.etc."pam.d/common-password"` override replaces the entire NixOS-generated PAM password policy file with a single line. The NixOS-generated file includes `pam_unix.so` stacking, `pam_deny.so` fallback, and other essential PAM modules. Replacing it with just `pam_pwquality.so` breaks password authentication because `pam_unix.so` (which actually verifies the password) is missing.

### Evidence

- `files/features/hardening.nix:190-192`:
```nix
environment.etc."pam.d/common-password".text = ''
  password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so try_first_pass
'';
```

The NixOS-generated `common-password` typically contains:
```
password sufficient pam_unix.so ...
password requisite pam_deny.so
```

The override removes `pam_unix.so` entirely, meaning password authentication will fail for all services that use the `common-password` stack (sudo, login, passwd, etc.).

### Recommendation

Use the NixOS PAM module options instead of overriding the file directly:

```nix
security.pam.services = {
  login.passwordPamQuality = lib.mkBefore "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
  sudo.passwordPamQuality = lib.mkBefore "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
};
```

Or if a custom PAM config is needed, use `security.pam.loginLimits` or the service-specific PAM options rather than replacing the entire file.

### Expected Benefit

Password authentication continues to work. PAM pwquality is added as a module in the stack rather than replacing the entire stack.

---

## `hardcoded` User Paths in ClamAV, Snort, and Metadata Stripper

Severity: Medium
Category: Maintainability

### Problem

Multiple security modules hardcode `/home/yusa` as a path prefix instead of using the NixOS user configuration. If the username changes, these modules will silently break — exclusion paths won't match, scan directories won't exist, and notifications may fail.

### Evidence

- `files/modules/security/clamav.nix:24-25` — `"/home/yusa/.steam"`, `"/home/yusa/.local/share/Steam"`
- `files/modules/security/clamav.nix:67-68` — Same hardcoded paths in daily scan script
- `files/modules/security/snort.nix:492` — `for user in yusa; do` (hardcoded in user notification loop)
- `files/modules/security/metadata-stripper.nix:9` — `"/home/yusa/Pictures"`, `"/home/yusa/Downloads"`
- `files/features/hardening.nix:165,175` — `IPCAllowedUsers = [ "root" "yusa" ]`
- `files/features/hardening.nix:205` — `chmod 0750 /home/yusa`

### Recommendation

Use NixOS user config references where possible:

```nix
# In clamav.nix
OnAccessExcludePath = [
  "${config.users.users.yusa.home}/.steam"
  "${config.users.users.yusa.home}/.local/share/Steam"
];
```

For scripts that don't have access to `config`, use a variable set in the module's `let` block:

```nix
let
  userHome = config.users.users.yusa.home;
in { ... }
```

### Expected Benefit

Configuration adapts automatically if the username or home directory changes. Single source of truth for user paths.

---

## `nohibernate` Is Not a Valid Kernel Parameter

Severity: Low
Category: Bug

### Problem

The `memory-wipe.nix` module adds `nohibernate` to `boot.kernelParams`, but there is no such kernel parameter. Hibernation is controlled at compile time (`CONFIG_HIBERNATION`) and via systemd targets (`hibernate.target`), not via kernel command-line parameters. This parameter is silently ignored by the kernel.

### Evidence

- `files/modules/security/memory-wipe.nix:113` — `boot.kernelParams = [ "nohibernate" ];`
- The same module already disables hibernation via systemd targets (lines 116-119):
  - `systemd.targets.hibernate.enable = false;`
  - `systemd.targets.hybrid-sleep.enable = false;`

### Recommendation

Remove the invalid kernel parameter since the systemd target disabling is the correct approach:

```nix
# Remove this line:
# boot.kernelParams = [ "nohibernate" ];
```

### Expected Benefit

Cleaner boot parameters. No confusion about which mechanism actually prevents hibernation.

---

## Duplicate `slab_nomerge` Boot Parameters

Severity: Low
Category: Maintainability

### Problem

Two boot parameters that do the same thing are both set: `slab_nomerge` (shorthand) and `slab_merge=off` (long form). This is redundant and confusing for maintainers.

### Evidence

- `files/modules/security/kernel-boot.nix:33` — `"slab_nomerge"`
- `files/modules/security/kernel-boot.nix:47` — `"slab_merge=off"`

Both disable slab page merging. The kernel accepts either form.

### Recommendation

Keep only one — prefer the shorter form:

```nix
"slab_nomerge"  # Remove "slab_merge=off" from line 47
```

### Expected Benefit

Reduced redundancy. Clearer intent for maintainers reviewing boot parameters.

---

## `consoleLogLevel = 0` Conflicts with `loglevel=3` Kernel Parameter

Severity: Low
Category: Bug

### Problem

Two conflicting console log level settings are applied: `boot.consoleLogLevel = 0` (silent) and `loglevel=3` in kernel parameters. Depending on boot loader processing order, one will override the other, leading to unpredictable console verbosity.

### Evidence

- `files/features/hardening.nix:132` — Wait, this is in kernel-boot.nix
- `files/modules/security/kernel-boot.nix:20` — `"loglevel=3"` in bootParams
- `files/modules/security/kernel-boot.nix:132` — `boot.consoleLogLevel = 0;`

`boot.consoleLogLevel` sets the kernel console log level to 0 (KERN_EMERG only). `loglevel=3` in kernelParams sets it to 3 (KERN_ERR). The boot loader may apply these in different orders.

### Recommendation

Keep only `boot.consoleLogLevel = 0` and remove `loglevel=3` from kernelParams, or vice versa:

```nix
# Keep loglevel=3 in bootParams, remove boot.consoleLogLevel = 0
# OR keep boot.consoleLogLevel = 0, remove "loglevel=3" from bootParams
```

### Expected Benefit

Consistent, predictable console log level. No ambiguity about which setting takes effect.

---

## `safe.directory = "*"` Is a Git Security Risk

Severity: Medium
Category: Security

### Problem

`safe.directory = "*"` in the git configuration trusts every directory on the system for git operations. This defeats git's directory ownership verification, which is designed to prevent attackers from tricking users into executing arbitrary code through malicious `.gitconfig` or `.git/hooks` in shared directories.

### Evidence

- `files/core/home.nix:228` — `safe.directory = "*";`
- `files/features/nix-config.nix:30` — `safe.directory = [ "*" ];` (also set here)

The comment at `home.nix:226` explains the rationale: "Trust all repos to avoid libgit2 ownership errors when nix evaluates the flake under a different user context (e.g. nix daemon as root)."

### Recommendation

Scope the trust to specific directories instead of all directories:

```nix
safe.directory = [
  "${config.home.homeDirectory}"
  "${config.home.homeDirectory}/System"
  "/nix/store"
];
```

Or if the nix daemon context is the only issue, use the more targeted:
```nix
safe.directory = "/nix/store";
```

### Expected Benefit

Git directory ownership verification is preserved for most directories while still allowing nix evaluation to work. Reduces attack surface from malicious repos in shared locations.

---

## Snort IDS Runs as Root

Severity: Medium
Category: Security

### Problem

The Snort intrusion detection service runs as `User = "root"`. If Snort is exploited (e.g., via a crafted packet triggering a parser vulnerability in the IDS rules), the attacker gains root access. IDS systems should run as unprivileged users with minimal capabilities.

### Evidence

- `files/modules/security/snort.nix` — Snort systemd service with `User = "root"` (referenced in agent analysis)

### Recommendation

Create a dedicated `snort` user and group, and run the service as that user with appropriate capabilities:

```nix
users.users.snort = {
  isSystemUser = true;
  group = "snort";
};
users.groups.snort = {};

systemd.services.snort-daemon = {
  serviceConfig = {
    User = "root";  # Sniffing raw packets needs CAP_NET_RAW
    # Better: use ambient capabilities
    # User = "snort";
    # AmbientCapabilities = [ "CAP_NET_RAW" "CAP_NET_ADMIN" ];
  };
};
```

### Expected Benefit

Reduced blast radius from IDS vulnerabilities. Snort compromise doesn't automatically mean root compromise.

---

## New Findings (from System Investigation)

---

## NetworkManager IPv6 sysctl Write Failures (38+ per boot)

Severity: Medium
Category: Reliability

### Problem

NetworkManager logs 38+ `Read-only file system` errors per boot when trying to configure IPv6 sysctl settings for interfaces (`temp_valid_lft`, `temp_prefered_lft`, `disable_ipv6`, `accept_ra`, `use_tempaddr`). These occur because `security.protectKernelImage = true` in `hardening.nix` enables kernel lockdown mode, which prevents userspace from writing to `/proc/sys`.

### Evidence

- `files/features/hardening.nix:10` — `security.protectKernelImage = true;`
- Journal shows 38+ EROFS errors from NetworkManager on every boot for `enp0s25` and `wlp4s0` interfaces
- Error code 30 (EROFS) is returned by the kernel when lockdown prevents sysctl writes

### Recommendation

If kernel lockdown is not actually needed (GPU drivers need it disabled per `kernel-boot.nix` comments), ensure `security.protectKernelImage` doesn't conflict. Alternatively, add kernel command-line params to allow specific sysctl writes. The root cause is lockdown mode blocking IPv6 privacy extension configuration at runtime.

### Expected Benefit

Clean boot logs, proper IPv6 privacy extension configuration (temporary addresses), reduced log noise.

---

## `/etc/modules-load.d/nixos.conf` Contains Built-in Modules 'proc' and 'tmpfs'

Severity: Low
Category: Maintainability

### Problem

The generated `/etc/modules-load.d/nixos.conf` lists `proc` and `tmpfs` as kernel modules to load. These are built into the kernel (not loadable modules). `systemd-modules-load` correctly reports `Failed to find module 'proc'` and `Failed to find module 'tmpfs'` at every boot. While benign, these error messages are confusing and indicate a minor configuration smell.

### Evidence

- `cat /etc/static/modules-load.d/nixos.conf` contains entries `proc` and `tmpfs`
- `journalctl -b -u systemd-modules-load` shows: `Failed to find module 'proc'`, `Failed to find module 'tmpfs'`
- These entries are likely from NixOS's default `boot.kernelModules` processing

### Recommendation

Investigate which NixOS option or hardware detection adds 'proc' and 'tmpfs' as kernel module names. These should be removed since they are always built-in. The entries may come from an older NixOS generation or a hardware auto-detection module.

### Expected Benefit

Cleaner boot logs, no misleading module load failures.

---

## polkit-gnome-authentication-agent-1 Fails to Determine Session

Severity: Low
Category: Reliability

### Problem

The `polkit-gnome-authentication-agent-1` service fails at every boot with `Unable to determine the session we are in: No session for pid 2194`. This is a race condition where the authentication agent starts before the desktop session is fully registered with logind.

### Evidence

- Journal: `polkit-gnome-authentication-agent-1[2194]: Unable to determine the session we are in`
- `systemd[2034]: app-polkit\x2dgnome\x2dauthentication\x2dagent\x2d1@autostart.service: Failed with result 'exit-code'.`

### Recommendation

Add a dependency on `graphical-session.target` or add a restart to the autostart configuration for the polkit agent. This is typically handled by the desktop environment's session manager; if it's started via a user service, ensure proper ordering.

### Expected Benefit

Polkit authentication agent starts reliably after desktop session is established.

---

## xdg-desktop-portal-gnome Adwaita-dark GTK4 Theme Not Found

Severity: Low
Category: Maintainability

### Problem

`xdg-desktop-portal-gnome` reports `Theme parser error: Failed to import: Error opening file .../Adwaita-dark/gtk-4.0/gtk.css: No such file or directory`. The `gnome-themes-extra` package provides `Adwaita-dark` for GTK-3.0 only, but the portal theme expects a GTK-4.0 version.

### Evidence

- Multiple journal entries: `Theme parser error: gtk.css:5:1-133: Failed to import: Error opening file .../gnome-themes-extra-3.28/share/themes/Adwaita-dark/gtk-4.0/gtk.css`

### Recommendation

Install a GTK-4.0 compatible dark theme (e.g., `adw-gtk3` or `adwaita-qt`). Or configure the portal to use a theme that has GTK-4.0 support. Alternatively, set `gtk-application-prefer-dark-theme` via proper GSettings rather than gtk.css includes.

### Expected Benefit

No theme parser errors in xdg-desktop-portal-gnome. Consistent dark theme across portal dialogs.

---

## PipeWire SPA ALSA Device Not Available at Startup

Severity: Low
Category: Reliability

### Problem

PipeWire reports `spa.alsa: open failed: No such device` at startup. This occurs because PipeWire starts before ALSA has fully enumerated audio devices. The error is typically transient and ALSA works after the device is ready.

### Evidence

- Journal: `pipewire[2318]: spa.alsa: open failed: No such device`

### Recommendation

Ensure `alsa-restore.service` runs before PipeWire starts, or add a dependency on `sound.target`. The error is typically harmless but indicates a startup ordering issue.

### Expected Benefit

Cleaner PipeWire startup logs.

---

## WirePlumber UPower Service Not Available

Severity: Low
Category: Configuration

### Problem

WirePlumber reports `Failed to get percentage from UPower: org.freedesktop.DBus.Error.NameHasNoOwner` at boot. The UPower service is not enabled or configured on this system. WirePlumber uses UPower to monitor battery levels for audio power management.

### Evidence

- Journal: `wireplumber[2319]: default: Failed to get percentage from UPower: org.freedesktop.DBus.Error.NameHasNoOwner`

### Recommendation

Enable `services.upower.enable = true` in the configuration if battery monitoring is desired, or configure WirePlumber to skip UPower checks if it's not needed.

### Expected Benefit

No WirePlumber UPower warnings if the service is enabled, or cleaner logs if the warning is suppressed.

---

## auditd filter.conf Line Too Long

Severity: Low
Category: Configuration

### Problem

auditd logs `Skipping line 2 in filter.conf: too long` at every boot. A rule in auditd's filter configuration file exceeds the maximum allowed line length.

### Evidence

- Journal: `auditd[1297]: Skipping line 2 in filter.conf: too long`
- No `filter.conf` found at standard path (`/etc/audit/filter.conf`)

### Recommendation

Check where the `filter.conf` is generated (likely in a NixOS module) and ensure the rule lines don't exceed auditd's max line length. Alternatively, split the long rule into multiple shorter rules.

### Expected Benefit

auditd loads all filter rules correctly on startup.

---

## Kernel Audit Subsystem Flood: `audit: error in audit_log_subj_ctx`

Severity: High
Category: Bug / Reliability

### Problem

The running system generates hundreds of `audit: error in audit_log_subj_ctx` kernel messages per session, with periodic `audit_panic: N callbacks suppressed` messages. This indicates the audit subsystem is failing to log subject context (process security context) for audit events, likely due to a missing or misconfigured audit rule that references LSM labels (AppArmor/SELinux) while the audit log buffer overflows.

The flood is so severe it appears in every boot's error journal and dmesg, creating significant log noise that masks genuine security events.

### Evidence

- `journalctl -p err` — 100+ identical `audit: error in audit_log_subj_ctx` messages per session
- `dmesg | grep audit` — same pattern, with `audit_panic: 1265 callbacks suppressed` at peak
- `auditd` starts successfully but the kernel-level audit logging is failing
- This is a known kernel issue when audit rules reference subject context (`subj=`) but the LSM module cannot provide the context

### Recommendation

1. Check audit rules for `-subj` or `subj=` filters that reference AppArmor labels
2. If AppArmor is in complain mode or audit rules reference non-existent profiles, remove the `subj=` filter
3. As a temporary fix, reduce audit rule verbosity or disable subject context logging

### Expected Benefit

Eliminates hundreds of kernel error messages per session. Audit logs contain actionable events instead of noise.

---

## LUKS Keyfile Missing at Boot — TPM Keyfile Unlock Path Non-Functional

Severity: Critical
Category: Bug

### Problem

The system logs `Failed to activate, key file '/run/luks-keyfile' missing` during early boot. This means the TPM-sealed keyfile unlock path in the initrd is failing, and the system falls back to passphrase-based LUKS unlock. The `luks-keyfile.nix` module defines the keyfile creation and TPM sealing infrastructure, but the initrd does not successfully unseal and present the keyfile at boot.

### Evidence

- `journalctl -b` — `systemd-cryptsetup[512]: Failed to activate, key file '/run/luks-keyfile' missing.`
- `files/modules/security/luks-keyfile.nix` — Defines keyfile generation and TPM sealing
- `files/features/boot.nix` — Defines initrd secrets but the keyfile may not be included
- This relates to the PCR mismatch finding (Finding #1) — the TPM sealed blob uses PCRs 0,1,7 while enrollment uses 0+7

### Recommendation

This is likely caused by the PCR policy mismatch documented in Finding #1. When both issues are resolved (consistent PCR selection), verify that the initrd includes the TPM keyfile path and that `systemd-cryptsetup` can unseal it. Also verify that `boot.initrd.secrets` or `boot.initrd.secretsCommand` properly includes the sealed keyfile.

### Expected Benefit

TPM-based automatic LUKS unlock works at boot. No manual passphrase entry required under normal operation.

---

## AIDE Database Initialization Fails at Boot

Severity: High
Category: Bug

### Problem

The system logs `Failed to start Initialize AIDE database` at every boot. This means the initial AIDE file integrity database is never created, and consequently the daily AIDE check (Finding #30 — `set -e` bug) runs against a nonexistent database. The entire AIDE file integrity monitoring infrastructure is non-functional.

### Evidence

- `journalctl -b` — `Failed to start Initialize AIDE database`
- `files/modules/security/aide.nix` — Defines the initialization service and daily check timer
- The `aide-check.timer` is listed in active timers but the underlying check cannot work without a database

### Recommendation

Investigate why the AIDE init service fails. Common causes on NixOS:
1. The init service runs before `/var/lib/aide` or the persistent storage is mounted
2. The `aide --init` command fails due to permissions or missing paths
3. The service ordering is wrong (needs `after = [ "local-fs.target" ]` or similar)

### Expected Benefit

AIDE file integrity monitoring becomes functional. Tamper detection works as designed.

---

## Snort IDS Daemon Inactive

Severity: High
Category: Reliability

### Problem

The `snort-daemon` service is `inactive` on the running system despite being enabled in the configuration. Network intrusion detection is not operational.

### Evidence

- `systemctl is-active snort-daemon` returns `inactive`
- `files/modules/security/snort.nix` — Defines the Snort service
- No failed state in `systemctl --failed` suggests the service exited cleanly or was never started

### Recommendation

Check why the service is inactive:
```bash
systemctl status snort-daemon
journalctl -u snort-daemon
```
Common causes: missing network interface for promiscuous mode, missing rules file, or pcap device permissions.

### Expected Benefit

Network IDS is operational. Intrusion detection and prevention active.

---

## Snout Watcher Inactive

Severity: Medium
Category: Reliability

### Problem

The `snout-watcher` service is `inactive` despite being enabled. The security monitoring daemon that watches the quarantine directory and triggers ClamAV scans is not running.

### Evidence

- `systemctl is-active snout-watcher` returns `inactive`
- `files/modules/security/snout.nix` — Defines the watcher service

### Recommendation

Check service status and logs:
```bash
systemctl status snout-watcher
journalctl -u snout-watcher
```

### Expected Benefit

Security monitoring daemon operational. Quarantine directory changes are detected and acted upon.

---

## USBGuard `implicitPolicyTarget = "allow"` Makes It a No-Op Logger

Severity: Critical
Category: Security

**Status: FIXED (2026-06-05)** — Changed `implicitPolicyTarget` from `"allow"` to `"block"` in `files/features/hardening.nix:164`.

### Problem

USBGuard was configured with `rules = "allow"` and `implicitPolicyTarget = "allow"`, meaning every USB device was permitted regardless of rules.

### Evidence

- `files/features/hardening.nix:164` — `implicitPolicyTarget = "allow";` → **changed to** `"block"`

### Expected Benefit

USBGuard now blocks unauthorized USB devices. Protects against BadUSB, data exfiltration, and rogue HID devices.

### Expected Benefit

USBGuard actually blocks unauthorized USB devices. Protects against BadUSB, data exfiltration, and rogue HID devices.

---

## Docker `iptables = false` Without nftables Replacement Rules

Severity: Medium
Category: Bug

### Problem

Docker's iptables management is disabled (`iptables = false`) in `virtualisation.nix`, but no replacement nftables rules are created in that module. The optional `odysseus.nix` module creates nftables NAT rules, but if odysseus is not enabled, Docker containers have no NAT/masquerade and cannot reach the internet. Container port mappings (`-p 8080:80`) will not work.

### Evidence

- `files/features/virtualisation.nix:5` — `iptables = false;`
- `files/modules/optional/nixos/odysseus.nix` — Creates nftables rules (only when odysseus is enabled)
- No nftables rules in `virtualisation.nix` itself

### Recommendation

Either:
1. Remove `iptables = false` and let Docker manage its own iptables rules (simplest), or
2. Create nftables Docker rules in `virtualisation.nix` that are always active when Docker is enabled

### Expected Benefit

Docker containers have working internet access and port forwarding regardless of optional module state.

---

## Docker No Log Rotation — Containers Can Fill Disk

Severity: Medium
Category: Reliability

### Problem

Docker is enabled with no log driver configuration. The default `json-file` driver stores unbounded logs for every container. A misbehaving container can fill the root or persistent partition with logs.

### Evidence

- `files/features/virtualisation.nix` — Docker enabled with only `iptables = false`
- No `log-driver` or `log-opts` in `daemon.settings`

### Recommendation

```nix
virtualisation.docker.daemon.settings = {
  "log-driver" = "json-file";
  "log-opts" = {
    max-size = "50m";
    max-file = "3";
  };
};
```

### Expected Benefit

Container logs are bounded. No single container can fill the disk.

---

## SSH `MaxSessions = 2` Is Extremely Restrictive

Severity: Medium
Category: Reliability

### Problem

`MaxSessions = 2` limits SSH to 2 multiplexed sessions per connection. The default is 10. VS Code Remote SSH, JetBrains Gateway, and similar tools typically open 3-6 channels. Combined with `AllowTcpForwarding = false` and `AllowAgentForwarding = false`, remote development over SSH is nearly impossible.

### Evidence

- `files/features/network.nix:20` — `MaxSessions = 2;`

### Recommendation

Increase to at least 10 (the default) if remote development tools are used, or document the intent:

```nix
MaxSessions = 10;
```

### Expected Benefit

Compatible with modern SSH clients and IDE tools.

---

## SSH `TCPKeepAlive = false` Risks Stale Zombie Connections

Severity: Medium
Category: Reliability

### Problem

Disabling TCP keepalive means dead SSH connections are never detected at the TCP level. `ClientAliveInterval` is not set (defaults to 0 = disabled), so there is no keepalive mechanism at all. Half-open connections from crashed clients persist for hours, consuming memory and file descriptors.

### Evidence

- `files/features/network.nix:21` — `TCPKeepAlive = false;`
- No `ClientAliveInterval` set

### Recommendation

```nix
TCPKeepAlive = true;
# OR
ClientAliveInterval = 300;
ClientAliveCountMax = 3;
```

### Expected Benefit

Dead SSH connections are detected and cleaned up.

---

## `yorha-rebuild` Leaves Security Services Stopped on Build Failure

Severity: High
Category: Reliability

### Problem

The `yorha-rebuild` script stops 8 security services before `nixos-rebuild switch` and only restarts them on success. If the build fails, all security services remain stopped with no automatic recovery: snort-daemon, snout-watcher, aide-check, firmware-version-check, tpm-attestation-check, secureboot-verify, mullvad-daemon.

### Evidence

- `files/features/packages.nix:94-122` — Services stopped before build, restarted only on success
- No `else` branch to restart on failure

### Recommendation

```bash
if sudo nixos-rebuild switch --flake "$FLAKE" "$@"; then
  for svc in "${STOPPED_SERVICES[@]}"; do
    sudo systemctl restart "$svc" 2>/dev/null || true
  done
else
  echo "Build failed! Restarting security services..."
  for svc in "${STOPPED_SERVICES[@]}"; do
    sudo systemctl restart "$svc" 2>/dev/null || true
  done
  exit 1
fi
```

### Expected Benefit

Security services are always restarted, even on build failure. System never left in degraded security state.

---

## polkit Hardening Missing ReadWritePaths for `/var/lib/polkit-1`

Severity: Medium
Category: Bug

### Problem

The polkit service is hardened with `ProtectSystem = "strict"` but has no `ReadWritePaths` for `/var/lib/polkit-1`. Polkit needs to write authorization policy cache files there. Without write access, polkit cannot cache authorization decisions, potentially breaking all PolicyKit-dependent privilege escalation.

### Evidence

- `files/modules/security/service-hardening.nix:87-91` — polkit with `ProtectSystem = "strict"` but no `ReadWritePaths`

### Recommendation

```nix
ReadWritePaths = [ "/var/lib/polkit-1" ];
```

### Expected Benefit

Polkit authorization caching works correctly. Privilege escalation via PolicyKit remains functional.

---

## cups Hardening Missing Spool Directory Access

Severity: Medium
Category: Bug

### Problem

The cups service is hardened with `ProtectSystem = "strict"` but has no `ReadWritePaths` for the print spool directory. Cups cannot write print jobs, breaking all printing.

### Evidence

- `files/modules/security/service-hardening.nix:94-99` — cups with `ProtectSystem = "strict"` but no `ReadWritePaths`

### Recommendation

```nix
ReadWritePaths = [ "/var/spool/cups" "/var/log/cups" "/run/cups" ];
```

### Expected Benefit

Printing works correctly with systemd hardening enabled.

---

## Banner Module Missing SSH/Network Login Banner

Severity: Medium
Category: Security

### Problem

The banner module only sets `/etc/issue` (console login banner). It does not set `/etc/issue.net` (SSH/network login banner) or configure `services.openssh.settings.Banner`. Remote SSH attackers see no warning. This violates PCI-DSS, CIS, and STIG compliance requirements.

### Evidence

- `files/modules/security/banner.nix:7` — Only `environment.etc."issue"` set
- No `environment.etc."issue.net"` or SSH `Banner` directive

### Recommendation

```nix
environment.etc."issue.net".text = ''...'';
services.openssh.settings.Banner = "/etc/issue.net";
```

### Expected Benefit

All login access points display security warning banner. Compliance with security frameworks.

---

## Kernel sysctl `tcp_timestamps = 0` Breaks TCP Window Scaling

Severity: Medium
Category: Reliability

### Problem

Disabling TCP timestamps breaks TCP window scaling for high-bandwidth connections (RFC 1323/7323). On high-latency links, this significantly reduces throughput. Also breaks some NAT middleboxes.

### Evidence

- `files/modules/security/kernel-sysctl.nix:103` — `"net.ipv4.tcp_timestamps" = 0;`

### Recommendation

```nix
"net.ipv4.tcp_timestamps" = 1;
```

### Expected Benefit

Full TCP performance on high-bandwidth connections.

---

## Kernel sysctl `accept_ra = 0` Breaks SLAAC-Based IPv6

Severity: Medium
Category: Reliability

### Problem

`accept_ra = 0` disables Router Advertisement acceptance. On networks using SLAAC (most IPv6 networks), the system won't receive its IPv6 address or gateway. IPv6 connectivity is completely broken without static configuration.

### Evidence

- `files/modules/security/kernel-sysctl.nix:72-73` — `accept_ra = 0` for all/default

### Recommendation

Set `accept_ra = 2` to accept RAs, or document that IPv6 requires static configuration.

### Expected Benefit

IPv6 connectivity works via SLAAC on standard networks.

---

## `privacy.nix` Opens DNS Ports 53/853 Inbound — Machine Becomes Open Resolver

Severity: Critical
Category: Security

### Problem

The privacy module opens TCP/UDP ports 53 (DNS) and 853 (DNS-over-TLS) as `allowedTCPPorts`/`allowedUDPPorts`. This means the system ACCEPTS incoming DNS queries from the network, effectively turning the machine into an open DNS resolver. This contradicts the module's privacy purpose and creates a DNS amplification attack vector.

### Evidence

- `files/modules/optional/nixos/privacy.nix:27-30` — Opens ports 53, 853 globally

### Recommendation

Remove the inbound DNS port rules. Mullvad VPN connects outbound only:

```nix
# Remove these lines entirely:
# allowedTCPPorts = [ 53 853 ];
# allowedUDPPorts = [ 53 853 ];
```

### Expected Benefit

System is not an open DNS resolver. No DNS amplification attack surface.

---

## Module Registry Shell Script Downloads and Sources Unverified Remote Code

Severity: Critical
Category: Security

### Problem

`module-registry.sh` downloads a shell script from GitHub and `source`s it directly after stripping `readonly` markers. An attacker who compromises the upstream repository (or performs MITM) can inject arbitrary code. The `sed -i 's/^readonly //'` even removes safety measures from the remote file before execution.

### Evidence

- `files/lib/module-registry.sh:568-581` — `fetch_remote_registry()` downloads and sources remote script
- `files/lib/module-registry.sh:573` — `sed -i 's/^readonly //'` strips safety from remote file
- No checksum or signature verification

### Recommendation

Verify a checksum of the downloaded script before sourcing, or use a signed delivery mechanism:

```bash
EXPECTED_HASH="abc123..."
ACTUAL_HASH=$(sha256sum "$TMP_FILE" | cut -d' ' -f1)
if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
  echo "Registry script integrity check failed!"
  exit 1
fi
```

### Expected Benefit

Prevents supply chain attacks via compromised upstream module registry.

---

## Module Registry `readModuleState = { }` Makes Disable Mechanism Ineffective at Nix Level

Severity: High
Category: Bug

### Problem

`readModuleState` always returns an empty attrset, meaning at Nix evaluation time all modules appear "enabled". Disabling a module via the TUI/CLI only works if the module file is removed from disk. If the file remains but is "disabled" in `state.json`, Nix still imports it.

### Evidence

- `files/lib/module-registry.nix:345` — `readModuleState = { };`

### Recommendation

This is a known limitation (build-time can't read runtime state). Document clearly that module disabling requires file removal, or implement a build-time state mechanism.

### Expected Benefit

Users understand that module disabling only works via file removal, not via the registry.

---

## Intel GPU Hardcoded `video=1920x1080@60` Breaks Non-1080p Displays

Severity: Medium
Category: Reliability

### Problem

`boot.kernelParams` includes `"video=1920x1080@60"` which forces a specific resolution. Systems with 4K, ultrawide, or different laptop panels will get incorrect resolution, black bars, or unusable console.

### Evidence

- `files/hardware/gpu/intel.nix:29` — `"video=1920x1080@60"`
- Also in `files/modules/security/kernel-boot.nix:21` — `"video=1920x1080"`

### Recommendation

Remove the hardcoded resolution and let KMS auto-detect:

```nix
# Remove "video=1920x1080@60" — let KMS detect native resolution
```

### Expected Benefit

Display works correctly on all monitor resolutions.

---

## `nix-ld.enable = true` Creates Security Risk

Severity: Medium
Category: Security

### Problem

`nix-ld` creates a dynamic linker shim allowing pre-compiled binaries to run without Nix patching. This bypasses the NixOS model. No `programs.nix-ld.libraries` is configured, making all standard libraries available.

### Evidence

- `files/features/nix-config.nix:25` — `programs.nix-ld.enable = true;`
- No `programs.nix-ld.libraries` configured

### Recommendation

Configure only the specific libraries needed, or wrap required binaries in Nix packages:

```nix
programs.nix-ld.libraries = with pkgs; [ zlib libGL ];
```

### Expected Benefit

Reduced attack surface. Only approved libraries available through nix-ld.

---

## `max-jobs = "auto"` + `cores = 0` Can Exhaust System Resources

Severity: Medium
Category: Reliability

### Problem

`max-jobs = "auto"` allows one build per CPU core, and `cores = 0` gives each build all cores. On a 16-core system, 16 builds each using 16 cores = 256 logical cores of demand. This causes OOM kills, disk thrashing, and system unresponsiveness during builds.

### Evidence

- `files/features/nix-config.nix:7-8` — `max-jobs = "auto"; cores = 0;`

### Recommendation

```nix
max-jobs = "auto";
cores = 4;
```

### Expected Benefit

System remains responsive during builds.

---

## `metadata-stripper.nix` `stripFlags` Variable Defined But Never Used

Severity: Low
Category: Maintainability

### Problem

The `stripFlags` variable is defined in the `let` block but never referenced. The actual exiftool commands duplicate the same flags inline in both the watcher and daily scan scripts. Maintenance requires changing flags in three places.

### Evidence

- `files/modules/security/metadata-stripper.nix:16-24` — `stripFlags` defined but unused
- Lines 65-71, 111-116 — Duplicate flags inline

### Recommendation

Remove `stripFlags` and reference a shared variable in all three locations.

### Expected Benefit

Single source of truth for exiftool flags.

---

## `snort.nix` Monitor Processes All Existing Alerts on Service Start

Severity: Low
Category: Bug

### Problem

`LAST_LINE=0` on startup means the monitoring loop processes ALL existing alerts, potentially generating a flood of stale notifications.

### Evidence

- `files/modules/security/snort.nix:465` — `LAST_LINE=0`

### Recommendation

```bash
LAST_LINE=$(wc -l < "$ALERT_LOG" 2>/dev/null || echo 0)
```

### Expected Benefit

Only new alerts generate notifications after service restart.

---

## `xsettingsd` Config Created But Daemon Never Installed or Started

Severity: Medium
Category: Bug

### Problem

`home.nix` creates `.config/xsettingsd/Xwayland.conf` with GTK theme settings for XWayland apps, but `xsettingsd` is not in any package list and no systemd service starts it. The config file is entirely inert — XWayland apps don't receive the intended dark theme settings. Additionally, the filename is wrong: xsettingsd reads `xsettingsd.conf`, not `Xwayland.conf`.

### Evidence

- `files/core/home.nix:37` — Creates `.config/xsettingsd/Xwayland.conf`
- No `xsettingsd` in `home.packages` or system packages
- No systemd user service for xsettingsd

### Recommendation

Either add xsettingsd as a package and create a systemd user service, or remove the dead config file.

### Expected Benefit

XWayland applications receive consistent dark theme settings, or dead code is removed.

---

## `noctalia` Special Arg Unused by Any NixOS Module

Severity: Low
Category: Maintainability

### Problem

`specialArgs = { inherit inputs; noctalia = inputs.noctalia; }` makes `noctalia` available as a top-level NixOS special arg, but no NixOS module references it. The `inputs` attrset already contains `noctalia`.

### Evidence

- `flake-modules/hosts.nix:23,55` — `noctalia = inputs.noctalia;` in specialArgs

### Recommendation

Remove `noctalia = inputs.noctalia;` from both `specialArgs` blocks.

### Expected Benefit

Less noise in the specialArgs interface.

---

## `aarch64-linux` Declared as Supported But Has No Configuration

Severity: Low
Category: Maintainability

### Problem

`systems.nix` declares both `x86_64-linux` and `aarch64-linux` as supported, but all configurations hardcode `x86_64-linux`. Users looking at `systems.nix` would assume aarch64 is supported.

### Evidence

- `flake-modules/systems.nix` — `systems = [ "x86_64-linux" "aarch64-linux" ];`
- `flake-modules/hosts.nix` — `system = "x86_64-linux";` hardcoded for both configs

### Recommendation

Remove `aarch64-linux` or add a comment explaining it's aspirational.

### Expected Benefit

Accurate documentation of supported platforms.

---

## `nixpkgs-fmt` Is Deprecated

Severity: Medium
Category: Maintainability

### Problem

`nixpkgs-fmt` is deprecated in favor of `nixfmt-rfc-style` (RFC-166 formatter). The project is no longer maintained.

### Evidence

- `flake-modules/per-system.nix:3` — `formatter = pkgs.nixpkgs-fmt;`
- `flake-modules/per-system.nix:7` — devShell uses `nixpkgs-fmt`

### Recommendation

Replace with `nixfmt-rfc-style` (or `nixfmt`).

### Expected Benefit

Using an actively maintained formatter. Alignment with NixOS RFC-166.

---

## Empty Flake `checks = {}` — No CI Validation

Severity: Medium
Category: Reliability

### Problem

`checks = { }` means `nix flake check` validates nothing. Linting tools in the devShell are not wired into CI.

### Evidence

- `flake-modules/per-system.nix:14` — `checks = { }`

### Recommendation

```nix
checks = {
  lint = pkgs.runCommand "yorha-lint" { buildInputs = [ pkgs.statix pkgs.deadnix ]; } ''
    statix check ${../.}
    deadnix --no-lambda-pattern-names ${../.}
    touch $out
  '';
};
```

### Expected Benefit

`nix flake check` catches issues before they reach the main branch.

---

## Duplicate Module Imports via `configuration.nix` and `hosts.nix`

Severity: Low
Category: Maintainability

### Problem

`configuration.nix` imports 8 modules that `hosts.nix` also imports directly. Every module is registered twice. While NixOS deduplicates by path, this creates confusion about which file controls imports.

### Evidence

- `files/core/configuration.nix:4-11` — 8 imports
- `flake-modules/hosts.nix:40-47` — Same 8 imports

### Recommendation

Choose one file as the import hub and remove duplicates from the other.

### Expected Benefit

Single source of truth for module composition.

---

## ClamAV On-Access Scanning Disabled Despite Full Configuration

Severity: Medium
Category: Bug

### Problem

`clamonacc.enable = false` disables on-access scanning. All `OnAccess*` configuration parameters (lines 22-31) are dead code. An operator reviewing the config would believe on-access scanning is active.

### Evidence

- `files/modules/security/clamav.nix:22-31` — Full on-access config
- `files/modules/security/clamav.nix:34` — `clamonacc.enable = false;`

### Recommendation

Add a prominent comment explaining why on-access is disabled, or remove the dead configuration to avoid confusion.

### Expected Benefit

No false sense of protection. Configuration accurately reflects system state.

---

## `password-policy.nix` YESCRYPT Cost Factor at Default Value

Severity: Low
Category: Security

### Problem

`YESCRYPT_COST_FACTOR = "10"` is the default. For a hardened system, a higher cost factor (12-14) provides significantly stronger offline brute-force protection.

### Evidence

- `files/modules/security/password-policy.nix:40` — `YESCRYPT_COST_FACTOR = "10";`

### Recommendation

```nix
YESCRYPT_COST_FACTOR = "14";
```

### Expected Benefit

~16x slower offline brute-force cracking than default.

---

## Password Policy README Claims 14-Character Minimum, Code Says 12

Severity: Low
Category: Documentation

### Problem

README states "Minimum 14 characters" but `password-policy.nix` sets `PASS_MIN_LEN = "12"`.

### Evidence

- `README.md:55` — "Minimum 14 characters"
- `files/modules/security/password-policy.nix:36` — `PASS_MIN_LEN = "12";`

### Recommendation

Update README to match the actual value, or increase `PASS_MIN_LEN` to 14.

### Expected Benefit

Documentation matches reality.

---

## `metadata-stripper.nix` exiftool Strips ALL Metadata Including Orientation

Severity: Low
Category: Bug

### Problem

The `-all=` flag strips all EXIF metadata including image orientation. Smartphone photos may display rotated after stripping.

### Evidence

- `files/modules/security/metadata-stripper.nix:18` — `-all=`

### Recommendation

Preserve orientation: add `-TagsFromFile @ -Orientation -n` after `-all=`.

### Expected Benefit

Images maintain correct orientation after metadata stripping.

---

## `sops.nix` SSH Host Key Dependency Without Fallback

Severity: Medium
Category: Reliability

### Problem

`sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]` means if this single key is missing or rotated, sops-nix fails to decrypt ALL secrets. `neededForUsers = true` means the system can't create users if decryption fails.

### Evidence

- `files/modules/security/sops.nix:14` — Single SSH key path
- `files/modules/security/sops.nix:19` — `neededForUsers = true`

### Recommendation

Add RSA key as fallback:

```nix
age.sshKeyPaths = [
  "/etc/ssh/ssh_host_ed25519_key"
  "/etc/ssh/ssh_host_rsa_key"
];
```

### Expected Benefit

Secret decryption survives SSH key rotation or single key failure.
