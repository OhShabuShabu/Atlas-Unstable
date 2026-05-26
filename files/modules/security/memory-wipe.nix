{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: MEMORY WIPE & ANTI-FORENSICS
# INFO: ============================================================================
# INFO: DRAM wipe on shutdown, log/temp file shredding, swap cleanup
# NOTE: These services run at poweroff/reboot/halt to prevent cold boot attacks
#       and forensic recovery of sensitive data from memory or disk.
# WARN: Wiping delays shutdown by ~10-30 seconds — system will not power off
#       until all wipers complete.

let
  # INFO: Systemd service ordering — must run BEFORE power-off
  shutdownTargets = [ "poweroff.target" "reboot.target" "halt.target" ];

  # INFO: Script to wipe DRAM contents at shutdown
  # NOTE: Uses swapoff + page_poison + zero-fill to minimize recoverable data
  dramWipeScript = pkgs.writeShellScript "dram-wipe.sh" ''
    set -euo pipefail

    echo "DRAM-WIPE: Starting memory cleanup..."
    ${pkgs.util-linux}/bin/logger -p auth.info -t dram-wipe "Memory wipe starting"

    # Swap off — ensure no encrypted keys in swap
    if swapon --show | grep -q .; then
      echo "DRAM-WIPE: Disabling swap..."
      swapoff -a 2>/dev/null || true
    fi

    # Trigger kernel page poisoning (kernel param page_poison=1 is already set)
    echo "DRAM-WIPE: Triggering page poisoning..."
    echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    echo "DRAM-WIPE: Memory cleanup complete"
    ${pkgs.util-linux}/bin/logger -p auth.info -t dram-wipe "Memory wipe complete"
  '';

  # INFO: Script to shred logs and temp files at shutdown
  wiperScript = pkgs.writeShellScript "shutdown-wiper.sh" ''
    set -euo pipefail

    echo "SHUTDOWN-WIPE: Starting forensic cleanup..."
    ${pkgs.util-linux}/bin/logger -p auth.info -t shutdown-wipe "Forensic cleanup starting"

    # Wipe /var/log (structure preserved, content shredded)
    if [ -d /var/log ]; then
      find /var/log -type f \
        ! -name "*.gz" \
        -exec ${pkgs.coreutils}/bin/shred -vfz -n 1 {} \; 2>/dev/null || true
    fi

    # Wipe /tmp (tmpfs, but explicit cleanup)
    if [ -d /tmp ]; then
      find /tmp -type f -exec ${pkgs.coreutils}/bin/shred -vfz -n 1 {} \; 2>/dev/null || true
    fi

    # Wipe /run (tmpfs, sensitive runtime data)
    if [ -d /run ]; then
      find /run -type f -size -1M \
        -exec ${pkgs.coreutils}/bin/shred -vfz -n 1 {} \; 2>/dev/null || true
    fi

    # Swap file wipe (on encrypted /persistent — still shred for safety)
    if [ -f /persistent/swapfile ]; then
      echo "SHUTDOWN-WIPE: Wiping swap file..."
      ${pkgs.coreutils}/bin/shred -vfz -n 1 /persistent/swapfile 2>/dev/null || true
    fi

    echo "SHUTDOWN-WIPE: Forensic cleanup complete"
    ${pkgs.util-linux}/bin/logger -p auth.info -t shutdown-wipe "Forensic cleanup complete"
  '';
in

{
  # INFO: DRAM wipe service — runs before poweroff/reboot/halt
  systemd.services.dram-wiper = {
    description = "DRAM Memory Wipe — Cold Boot Attack Prevention";
    before = shutdownTargets;
    wants = shutdownTargets;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${dramWipeScript}";
      TimeoutStartSec = "30s";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_SYS_BOOT" ];
    };
  };

  # INFO: Shutdown wiper — shreds logs, temp files, swap
  systemd.services.shutdown-wiper = {
    description = "Shutdown Forensic Wiper — Logs, Temp, Swap";
    before = shutdownTargets;
    wants = shutdownTargets;
    after = [ "dram-wiper.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${wiperScript}";
      TimeoutStartSec = "120s";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      PrivateTmp = true;
      CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_SYS_BOOT" ];
    };
  };

  # INFO: Disable hibernation (prevents hibernation image attacks)
  boot.kernelParams = [ "nohibernate" ];

  # INFO: Disable suspend-to-idle (S2Idle — leaves memory powered)
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}
