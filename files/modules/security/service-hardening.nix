{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: SYSTEMD SERVICE HARDENING (BOOT-5264)
# INFO: ============================================================================
# INFO: Enhanced systemd service hardening for security
# FIX: Service sandboxing to limit exposure (BOOT-5264)
# NOTE: Avoid aggressive hardening that can cause boot issues
# WARN: Some services may break if hardened too much

{
  # INFO: Disable core dumps at systemd level
  systemd.coredump.enable = false;

  # INFO: Disable core dumps at PAM level
  security.pam.loginLimits = [{
    domain = "*";
    type = "-";
    item = "core";
    value = "0";
  }];

  # FIX: Enhanced service hardening with sandbox options (BOOT-5264)
  # NOTE: Keep essential services working while adding protection
  systemd.services = {
    # INFO: Systemd timesyncd - network time sync
    systemd-timesyncd.serviceConfig = {
      PrivateTmp = true;
      PrivateNetwork = false;  # Needs network access
      # FIX: Sandboxing
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
    };

    # INFO: Systemd logind - login manager
    systemd-logind.serviceConfig = {
      PrivateTmp = true;
      NoNewPrivileges = true;
    };

    # INFO: Systemd hostnamed - hostname service
    systemd-hostnamed.serviceConfig = {
      PrivateTmp = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
    };

    # INFO: D-Bus broker - message bus
    "dbus-broker".serviceConfig = {
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
    
    # FIX: Harden systemd-udevd (device manager) (BOOT-5264)
    # WARN: DO NOT HARDEN UDEVd - it manages block device discovery
    # Including /boot's disk. Hardening breaks early boot mounting.
    # systemd-udevd.serviceConfig = {
    #   PrivateTmp = true;
    #   NoNewPrivileges = true;
    # };
    
    # FIX: Harden audit daemon (BOOT-5264)
    # WARN: Avoid strict ProtectSystem on auditd - can break early boot
    # auditd.serviceConfig = {
    #   PrivateTmp = true;
    #   ProtectSystem = "strict";
    #   ProtectHome = true;
    # };
  };

  # FIX: Harden NetworkManager
  # WARN: Do NOT add PrivateNetwork (needs to manage interfaces)
  systemd.services.NetworkManager.serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
  };

  # FIX: Harden polkit
  systemd.services.polkit.serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
  };

  # FIX: Harden cups (print service - minimal needed to run)
  systemd.services.cups.serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
  };

  # FIX: Harden OpenSSH if enabled
  systemd.services.sshd.serviceConfig = lib.mkIf (config.services.openssh.enable or false) {
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateNetwork = true;
    ProtectSystem = "strict";
    ProtectHome = true;
  };

  # FIX: Harden nginx if enabled
  systemd.services.nginx.serviceConfig = lib.mkIf (config.services.nginx.enable or false) {
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateNetwork = true;
    ProtectSystem = "strict";
    ProtectHome = true;
  };

  # FIX: Document service hardening best practices
  environment.etc."security/service-hardening-notes.txt".text = ''
    # Service Hardening Guidelines (Lynis BOOT-5264)
    
    Available hardening options for systemd services:
    
    - PrivateTmp: Separate /tmp for the service
    - PrivateNetwork: Isolated network namespace
    - ProtectSystem: Restrict filesystem access
      * "off" - No protection (default)
      * "strict" - Make most of / read-only
      * "full" - Make all of / read-only (except /dev, /proc, /sys, /run)
    - ProtectHome: Make /home read-only or inaccessible
    - NoNewPrivileges: Prevent privilege escalation
    - RestrictNamespaces: Limit available namespaces
    - RestrictRealtime: Disable real-time priority
    - LockPersonality: Prevent personality changes
    
    Use: systemd-analyze security SERVICE_NAME
    to check service hardening status
  '';
}