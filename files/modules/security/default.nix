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
    ./strong-keyring.nix
    ./auditd-config.nix
    ./quarantine.nix
  ];

  # INFO: Security packages
  environment.systemPackages = with pkgs; [
    lynis         # INFO: Security auditing tool
    clamav        # INFO: Anti-virus scanner
    aide          # INFO: File integrity monitor
    audit         # INFO: Audit daemon
    lnav          # INFO: Log viewer TUI
    snort         # INFO: Network IDS/IPS
    vulnix        # FIX: Package vulnerability scanner (PKGS-7398)
  ];

  # INFO: Shell aliases for security tools
  environment.etc."profile.d/90-security.sh".text = ''
    # INFO: Security log viewer using lnav
    alias logs='sudo lnav /var/log/*.log'
    alias security-logs='sudo lnav /var/log/lynis.log /var/log/audit/*.log /var/log/clamav/*.log /var/log/snout/*.log'
    alias aide-check='sudo aide --check'
    alias lynis-scan='sudo lynis audit system --quick'
    alias snout-scan='sudo snout scan'
    alias snout-status='systemctl status snout-daemon'
    alias snort-status='systemctl status snort-daemon'
    alias snort-alerts='sudo tail -f /var/log/snort/alert_csv.txt'
    alias snortctl='sudo snortctl'
  '';
}