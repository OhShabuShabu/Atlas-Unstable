{ config, pkgs, lib, ... }:
{
    # ============================================================================
    # SECTION 6: TELEMETRY DISABLING
    # ============================================================================
    # INFO: Disable services that may leak privacy data
    services = {
        # WARN: dbus-broker can break Noctalia/Niri desktop shell compatibility
        # dbus.implementation = "broker";
        logrotate.enable = true;
        journald = {
            # Store logs in memory (prevents disk-based forensics)
            # NOTE: Use RuntimeMaxUse/RuntimeMaxFileSize for volatile storage
            storage = "volatile";
            upload.enable = false;
            extraConfig = ''
                RuntimeMaxUse=500M
                RuntimeMaxFileSize=50M
            '';
        };

        # Disable telemetry services
        avahi.enable = false;
        geoclue2.enable = false;
        # NOTE: udisks2 needed for SDDM and desktop functionality
        # udisks2.enable = false;
        accounts-daemon.enable = false;
    };

    # INFO: Disable modem manager (WWAN/3G/4G not used)
    networking.modemmanager.enable = false;

    # INFO: Disable automatic system upgrades (manual control)
    system.autoUpgrade.enable = false;
}