{ pkgs, ... }:

# INFO: ============================================================================
# INFO: AIDE FILE INTEGRITY MONITORING
# INFO: ============================================================================
# NOTE: AIDE (Advanced Intrusion Detection Environment) monitors file changes
# FIX: Added daily scheduled integrity check

let
  # INFO: AIDE database configuration with SHA512 (FINT-4402)
  aideConfig = ''
    database_in=file:/var/lib/aide/aide.db.gz
    database_out=file:/var/lib/aide/aide.db.new.gz
    gzip_dbout=yes
    report_url=stdout
    # FIX: Use SHA512 for strong checksums (FINT-4402)
    # FIX: Configure log file for audit trail (ACCT-9634)
    report_url=file:/var/log/aide/report.log
  '';

  # INFO: Directories to monitor with attributes - updated with SHA512
  # NOTE: p=permissions, i=inode, u=user, g=group, n=ACL, xattrs=xattrs, sha512=checksum
  monitoredDirs = ''
    /bin p+i+u+g+n+acl+xattrs+sha512
    /sbin p+i+u+g+n+acl+xattrs+sha512
    /usr/bin p+i+u+g+n+acl+xattrs+sha512
    /usr/sbin p+i+u+g+n+acl+xattrs+sha512
    /lib p+i+u+g+n+acl+xattrs+sha512
    /usr/lib p+i+u+g+n+acl+xattrs+sha512
    /var/lib p+i+u+g+n+acl+xattrs+sha512
    /etc p+i+u+g+n+acl+xattrs+sha512
  '';
in

{
  # INFO: AIDE configuration file
  environment.etc."aide.conf".text = aideConfig + monitoredDirs;

  # INFO: Create required directories
  systemd.tmpfiles.rules = [
    "d /var/log/aide 0750 root root -"
    "d /var/lib/aide 0750 root root -"
  ];

  # FIX: Initialize AIDE database on first boot (FINT-4316)
  # NOTE: Runs if database doesn't exist - auto-initializes at boot
  systemd.services."aide-init" = {
    description = "Initialize AIDE database";
    after = [ "network.target" ];
    before = [ "aide-check.timer" ];
    wantedBy = [ "multi-user.target" ];  # FIX: Enable at boot
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "aide-init.sh" ''
        #!/bin/bash
        set -e

        AIDE_DB="/var/lib/aide/aide.db.gz"
        
        # INFO: Only initialize if database doesn't exist
        if [ ! -f "$AIDE_DB" ]; then
          echo "Initializing AIDE database..."
          /run/current-system/sw/bin/aide --init
          
          if [ -f "/var/lib/aide/aide.db.new.gz" ]; then
            cp /var/lib/aide/aide.db.new.gz "$AIDE_DB"
            echo "AIDE database initialized successfully at $(date)"
          fi
        else
          echo "AIDE database already exists, skipping initialization"
        fi
      '';
    };
  };

  # FIX: Add daily scheduled integrity check
  # INFO: Runs AIDE check daily at 3pm via timer - not at boot
  systemd.services."aide-check" = {
    description = "AIDE file integrity check";
    after = [ "network.target" ];
    wantedBy = [ ];  # Only runs via timer, not at boot
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "aide-check.sh" ''
        #!/bin/bash
        set -e

        AIDE_DB="/var/lib/aide/aide.db.gz"
        LOG_FILE="/var/log/aide/check.log"
        
        # INFO: Only run check if database exists
        if [ -f "$AIDE_DB" ]; then
          echo "Running AIDE integrity check at $(date)" > "$LOG_FILE"
          /run/current-system/sw/bin/aide --check >> "$LOG_FILE" 2>&1
          
          if [ $? -eq 0 ]; then
            echo "No changes detected" >> "$LOG_FILE"
          else
            echo "WARNING: Changes detected! Review $LOG_FILE" | tee /dev/stderr
          fi
        else
          echo "AIDE database not found, skipping check"
        fi
      '';
    };
  };

  # INFO: Daily timer for AIDE check at 3pm
  systemd.timers."aide-check" = {
    description = "Daily AIDE integrity check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 15:00:00";
      Persistent = true;
    };
  };
}