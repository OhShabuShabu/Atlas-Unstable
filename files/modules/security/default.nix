{ lib, pkgs, ... }:

# INFO: ============================================================================
# INFO: SECURITY MODULE - Main entry point
# INFO: ============================================================================
# INFO: Imports all security submodules and provides security tools

{
  imports = [
    ./kernel-sysctl.nix
    ./kernel-boot.nix
    ./process-accounting.nix

    ./firewall.nix
    ./banner.nix

    ./service-hardening.nix
    ./telemetry.nix

    ./password-policy.nix
    ./network-privacy.nix
    ./aide.nix
    ./clamav.nix
    ./auditd-config.nix
    ./quarantine.nix
    ./metadata-stripper.nix
    ./sops.nix
    # DISABLED: Firmware tinkering detection
    # ./tpm-sealing.nix
    ./luks-keyfile.nix
    # DISABLED: Secure Boot (firmware integrity)
    # ./secureboot.nix
    ./memory-wipe.nix
    ./ima-evm.nix
    # DISABLED: TPM/UEFI monitoring (firmware tamper detection)
    # ./tpm-monitoring.nix
    # DISABLED: Firmware version attestation
    # ./firmware-check.nix
    ./luks-test.nix
  ];

  # INFO: Security packages
  environment.systemPackages = with pkgs; [
    lynis         # INFO: Security auditing tool
    clamav        # INFO: Anti-virus scanner
    aide          # INFO: File integrity monitor
    lnav          # INFO: Log viewer TUI
    vulnix        # FIX: Package vulnerability scanner (PKGS-7398)
    sops          # INFO: Encrypted secret management (edit secrets with `sops`)
    ssh-to-age    # INFO: Convert SSH keys to age keys for sops-nix
  ];

}