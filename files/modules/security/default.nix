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
  ];

  # INFO: Security packages
  environment.systemPackages = with pkgs; [
    lynis         # INFO: Security auditing tool
    clamav        # INFO: Anti-virus scanner
    aide          # INFO: File integrity monitor
    lnav          # INFO: Log viewer TUI
    vulnix        # FIX: Package vulnerability scanner (PKGS-7398)
  ];

}