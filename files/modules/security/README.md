# Security Module Reference

This directory contains 17 specialized security hardening modules for the Atlas system.

## Modules Overview

### Kernel Hardening
- **kernel-boot.nix** — Kernel command-line parameters and module blocking
  - Disables dangerous kernel modules (firewire, raw1394, etc.)
  - Enables kernel hardening boot parameters (ASLR, slab_nomerge, etc.)
  - **Impact**: Moderate attack surface reduction

- **kernel-sysctl.nix** — Runtime kernel parameters via sysctl
  - Core dumps disabled, pointer leaks protected
  - eBPF restrictions, SysRq disabled
  - **Impact**: Prevents info leaks from kernel crashes

### Service Hardening
- **service-hardening.nix** — Systemd service sandboxing
  - Network Manager, polkit, cups, SSH hardened
  - **Impact**: Limits damage if a service is compromised

### Threat Detection
- **clamav.nix** — ClamAV antivirus daemon
  - Daily scans with auto-quarantine
  - **Impact**: Detects known malware patterns

- **snout.nix** — Security monitoring daemon
  - Watches quarantine directory for new threats
  - Triggers alerts and integrations
  - **Impact**: Immediate threat response

- **quarantine.nix** — Sandboxed threat storage
  - Isolated directory with 0000 permissions
  - Noexec, nosuid, nodev bind mount
  - **Impact**: Contained threat isolation

- **aide.nix** — File integrity monitoring
  - Daily checks for unauthorized file changes
  - **Impact**: Detects rootkit/malware modifications

### Network Security
- **firewall.nix** — nftables firewall configuration
  - Minimal open ports, restrictive ingress
  - ICMP, source routing protections
  - **Impact**: Blocks network attacks

- **network-privacy.nix** — DNS hardening
  - systemd-resolved with DNSSEC, DNS-over-TLS
  - **Impact**: Prevents DNS spoofing/hijacking

### Access Control & Audit
- **password-policy.nix** — Strong password requirements
  - Minimum 14 characters, complexity rules
  - **Impact**: Resists brute-force attacks

- **process-accounting.nix** — Process audit logging
  - Full process lifecycle logging
  - **Impact**: Forensic visibility

- **auditd-config.nix** — Detailed auditd rules
  - File access, system call monitoring
  - **Impact**: Comprehensive audit trail

### Miscellaneous
- **telemetry.nix** — Disable telemetry/tracking
- **banner.nix** — Login banner
- **strong-keyring.nix** — Hardware security token support

## Enabling/Disabling Modules

All modules are enabled by default. To disable a module:

1. Edit `files/core/configuration.nix`
2. Find the module import you want to disable
3. Comment it out: `# ../modules/security/module-name.nix`
4. Rebuild: `sudo nixos-rebuild switch --flake .#atlas`

**WARNING**: Disabling security modules reduces system hardening. Only disable if:
- A module causes compatibility issues
- You understand the security implications
- You have a specific reason documented

## Lynis Security Audit Mapping

Module addresses these Lynis findings:
- **BOOT-5264** (Service hardening) → service-hardening.nix
- **KMOD-5820** (Kernel module loading) → kernel-boot.nix
- **FILE-6310** (File integrity) → aide.nix
- **PROC-3814** (Process accounting) → process-accounting.nix
- **AUTH-9288** (Password policy) → password-policy.nix
- **NETW-3032** (Firewall) → firewall.nix

## Troubleshooting

**Issue**: System won't boot after security module changes
- Solution: Revert the module in configuration.nix and rebuild

**Issue**: Network connectivity problems
- Check: firewall.nix — may need to whitelist ports

**Issue**: External drives not mounting
- Check: kernel-boot.nix — usb-storage module may be blocked

**Issue**: Services failing to start
- Check: service-hardening.nix — sandboxing may be too strict
