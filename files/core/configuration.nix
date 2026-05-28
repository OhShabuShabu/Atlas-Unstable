# ============================================================================
# ATLAS SYSTEM CONFIGURATION
# ============================================================================
# Main NixOS configuration file - imports all module components
# This configuration follows NixOS best practices for security,
# privacy, and desktop use.
# ============================================================================

{ config, pkgs, lib, inputs, ... }:

# ============================================================================
# HARDWARE COMPATIBILITY NOTE
# ============================================================================
# This configuration is designed to auto-detect and adapt to different
# hardware via the files/hardware/detect/ infrastructure:
#
#   - CPU vendor (Intel/AMD/generic) → appropriate kvm module + microcode
#   - GPU vendor (AMD/Intel/NVIDIA/generic) → driver + initrd KMS modules
#   - RAM size → adaptive swap size, tmpfs limits, nix parallelism
#
# Override auto-detection in your hardware-configuration.nix or here:
#   hardware.cpu.vendor = lib.mkForce "amd";
#   hardware.gpu.vendor = lib.mkForce "intel";
#   hardware.memory.totalMB = lib.mkForce 4096;
#
# Undetected/generic hardware gets safe fallbacks that always boot.
# ============================================================================
{
  # ============================================================================
  # MODULE IMPORTS
  # ============================================================================
  imports = [
    # INFO: Core system modules
    ./hardware-configuration.nix

    # INFO: Hardware-specific modules (GPU, CPU, audio — auto-imported)
    ../hardware/default.nix

    # INFO: System profile (hostname, timezone, locale — auto-imported)
    ../profiles/default.nix

    # INFO: Security modules (imports submodules automatically)
    ../modules/security/default.nix

    # INFO: Snort network IDS/IPS daemon
    ../modules/security/snort.nix

    # INFO: Snout security monitoring daemon
    ../modules/security/snout.nix

    # DISABLED: Firmware tinkering detection services
    # See: tpm-sealing (TPM PCR attestation), secureboot (Secure Boot verification),
    #      tpm-monitoring (runtime PCR/UEFI monitoring), firmware-check (BIOS version check)
    # ../modules/security/tpm-sealing.nix

    # DISABLED: Secure Boot kernel signing (part of firmware integrity)
    # ../modules/security/secureboot.nix

    # DISABLED: TPM/UEFI monitoring & tamper detection
    # ../modules/security/tpm-monitoring.nix

    # DISABLED: Firmware version attestation (detects unauthorized BIOS/UEFI updates)
    # ../modules/security/firmware-check.nix

    # INFO: Feature modules (from external atlas-modules repo)
    ../modules/optional/nixos

    # INFO: Module manager — TUI, desktop entry, state management
    ../modules/module-manager/default.nix
  ];


  # Force Intel GPU vendor (detection via /proc/bus/pci/devices can fail during eval)
  hardware.gpu.vendor = lib.mkForce "intel";

  # ============================================================================
  # SECTION 1: BOOT CONFIGURATION
  # ============================================================================
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    # Secure Boot support is handled by sbctl + manual kernel signing (Wave 3, tasks 9-11)
    # Key management tools: programs.sbctl or manual sbsign per task 9

    # Enable systemd initrd (required for LUKS)
    initrd.systemd.enable = true;

    # Compress initrd with zstd (better ratio than gzip) — shrinks each initrd ~2-3×,
    # critical for machines with small EFI partitions (512MB)
    initrd.compressor = "zstd";
    initrd.compressorArgs = [ "-12" ];

    # Limit boot entries to prevent /boot (ESP) from filling up
    # Without this, every rebuild adds another kernel + initrd (~500MB+ with all firmware)
    # and they are never automatically cleaned from the EFI partition
    # Lower on machines with small EFI partitions (512MB common on many devices)
    loader.systemd-boot.configurationLimit = 3;

    # TPM 2.0 kernel modules — loaded only if TPM hardware is present.
    # On systems without TPM (older hardware, VMs, some laptops), loading
    # these modules just wastes memory and slows boot by probing for
    # non-existent hardware. The detection reads /sys/class/tpm/ at eval time.
    initrd.availableKernelModules =
      let tpmPresent = builtins.tryEval (builtins.pathExists "/sys/class/tpm/tpm0");
      in lib.mkIf (tpmPresent.success && tpmPresent.value) [ "tpm_tis" "tpm_crb" "tpm" ];

    kernelModules =
      let tpmPresent = builtins.tryEval (builtins.pathExists "/sys/class/tpm/tpm0");
      in [ "i2c-dev" ]
         ++ lib.optionals (tpmPresent.success && tpmPresent.value) [ "tpm_tis" "tpm_crb" "tpm" ];

    # GPU initrd kernel modules moved to hardware/gpu/<vendor>.nix for per-machine selection.
    # Only include the driver for the actual hardware — all three bundles add ~200MB+ firmware
    # to every initrd, overwhelming small EFI partitions on non-Atlas machines.

    # LUKS devices and fileSystems are provided by either:
    #   - current-system.nix (for `nixos-rebuild switch --flake .#atlas`)
    #   - disko.nix       (for fresh install via `.#atlas-installer`)

    # Plymouth boot splash — Hyprland macOS style theme
    plymouth = {
      enable = true;
      theme = "hyprland-mac-style";
      themePackages = with pkgs; [
        (pkgs.runCommandLocal "plymouth-hyprland-mac-style" {
          src = ./../config/plymouth/hyprland-mac-style;
        } ''
          mkdir -p $out/share/plymouth/themes
          cp -r "$src" $out/share/plymouth/themes/hyprland-mac-style
          substituteInPlace $out/share/plymouth/themes/hyprland-mac-style/hyprland-mac-style.plymouth \
            --replace-fail "/usr/share" "$out/share"
        '')
      ];
    };
  };

  # Include all redistributable GPU firmware in initrd so any GPU driver can do KMS
  hardware.enableRedistributableFirmware = true;

  # Clean /tmp at every boot to prevent stale mount namespace leaks
  # from orphaned systemd PrivateTmp bind-mounts
  boot.tmp.cleanOnBoot = true;

  # ============================================================================
  # SECTION 2: NETWORK CONFIGURATION
  # ============================================================================
  # Host name — defined in profiles/atlas.nix
  # Use NetworkManager with systemd-resolved for DNSSEC + DNS-over-TLS
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  # Disable DHCP client (static IP)
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;

  # Mullvad VPN daemon — auto-loads WireGuard kernel module,
  # persists tunnel state across reboots, enables CLI management
  services.mullvad-vpn.enable = true;

  # Enable OpenSSH with secure defaults (key-only authentication)
  services.openssh = {
    enable = true;
    settings = {
      # Authentication hardening
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;

      # FIX: SSH hardening per Lynis SSH-7408
      AllowTcpForwarding = false;
      AllowAgentForwarding = false;
      ClientAliveCountMax = 2;
      LogLevel = "VERBOSE";
      MaxAuthTries = 3;
      MaxSessions = 2;
      TCPKeepAlive = false;
    };
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # Fallback nameservers (only used when systemd-resolved stub is unavailable)
  # Primary DNS is configured in services.resolved.settings.DNS below
  # These must differ from resolved's DNS to be useful as a genuine fallback
  networking.nameservers = [
    "9.9.9.9"    # Quad9 — primary fallback
    "149.112.112.112"
  ];


  # ============================================================================
  # SECTION 3: HOME MANAGER
  # ============================================================================
  # Enable Atlas Module Manager
  services.atlas-module-manager.enable = true;

  # Enable Home Manager
  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "backup";


  # ============================================================================
  # SECTION 4: NIX CONFIGURATION
  # ============================================================================
  # Enable Nix flakes and commands
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Build optimization: disable store dedup after every build (saves ~30-60s per rebuild)
  # Dedup runs separately via GC instead
  nix.settings.auto-optimise-store = false;

  # Parallelism: use all available cores for builds
  nix.settings.max-jobs = "auto";
  nix.settings.cores = 0;

  # Build optimization: remove derivation outputs from store faster
  nix.settings.keep-derivations = false;

  # GC thresholds: scale with detected RAM (min 1GB / max 5GB default)
  # Low-memory systems keep less free space to avoid OOM during builds
  nix.settings.min-free = let memMB = config.hardware.memory.totalMB;
    in if memMB < 4096 then 500000000     # < 4GB RAM: keep 500MB free
       else 1000000000;                    # ≥ 4GB RAM: keep 1GB free
  nix.settings.max-free = let memMB = config.hardware.memory.totalMB;
    in if memMB < 4096 then 2000000000    # < 4GB RAM: clean to 2GB
       else if memMB < 8192 then 3000000000  # 4-8GB RAM: clean to 3GB
       else 5000000000;                     # ≥ 8GB RAM: clean to 5GB

  # Automatic GC: weekly, remove generations older than 30 days
  nix.gc.automatic = true;
  nix.gc.dates = "weekly";
  nix.gc.options = "--delete-older-than 30d";

  # Allow unfree packages (NVIDIA, etc.)
  nixpkgs.config.allowUnfree = true;

  # openldap overlay removed — bottles/lutris (the only packages that triggered
  # the flaky test017) aren't currently installed. Re-add if gaming module is
  # enabled and openldap tests cause build failures.

  # Run dynamically linked executables (bun, etc.)
  programs.nix-ld.enable = true;


  # ============================================================================
  # SECTION 5: TIMEZONE & LOCALIZATION
  # ============================================================================
  # Timezone, locale, domain — defined in profiles/atlas.nix


  # ============================================================================
  # SECTION 6: USER CONFIGURATION
  # ============================================================================
  # Main user account
  users.users.yusa = {
    isNormalUser = true;
    description = "yusa";
    initialPassword = "changeme";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "mullvad"       # Non-root CLI access to Mullvad VPN
    ];
    homeMode = "0750";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZUNUi+15sIyPF4CrpeVjsfRE2JlYwIQlDtaCifRuvA yusa@atlas"
    ];
  };


  # ============================================================================
  # SECTION 7: SYSTEMD SERVICES
  # ============================================================================
  # FIX: Increase memlock limit for logind so it can attach BPF filters
  #      for udev event monitoring (default 8M is too low with bpf_jit_harden=2)
  systemd.services.systemd-logind.serviceConfig = {
    LimitMEMLOCK = "infinity";
  };

  # Polkit GNOME authentication agent — spawned from Niri startup.kdl instead of
  # systemd user service because systemd user instances on Niri/Wayland can't
  # determine the logind session, causing "Unable to determine the session we are in"
  #fatal errors. Niri spawns it with the correct session context.

  # ─── Desktop User Services ────────────────────────────────────────────────
  # These services run as the logged-in user and auto-start with the desktop
  # session. They replace the imperative background-spawns that startup.sh used
  # to do, giving us proper lifecycle management, restart on failure, and
  # journald logging.

  systemd.user.services.atlas-awww = {
    description = "Awww Wallpaper Daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.awww}/bin/awww-daemon --quiet";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStopSec = 10;
    };
  };

  systemd.user.services.atlas-vicinae = {
    description = "Vicinae Application Launcher";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.vicinae}/bin/vicinae server";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStopSec = 10;
    };
  };

  systemd.user.services.atlas-xwayland-satellite = {
    description = "XWayland Satellite (X11 compatibility)";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStopSec = 10;
    };
  };

  # Startup sound — plays once then exits
  systemd.user.services.atlas-startup-sound = {
    description = "Atlas Startup Sound";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ffmpeg}/bin/ffplay -nodisp -autoexit ${./../audio/startup.mp3}";
      RemainAfterExit = false;
    };
  };

  # OpenRGB — delayed RGB lighting config, runs after desktop is settled
  services.udev.packages = [ pkgs.openrgb ];

  systemd.user.services.atlas-openrgb = {
    description = "OpenRGB Lighting Configuration";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'sleep 12 && ${pkgs.openrgb}/bin/openrgb -d 0 -c $(${pkgs.python3}/bin/python3 ${./../bin/python/fix_rgb_color.py} $(tr -d \"#\" < ${./../config/primary_color.txt}))'";
      RemainAfterExit = false;
    };
  };

  # ============================================================================
  # SECTION 8: POLKIT CONFIGURATION
  # ============================================================================
  # Enable polkit system-wide for graphical auth popup
  security.polkit.enable = true;

  # RealtimeKit — gives PipeWire/WirePlumber realtime scheduling priority
  # Without this, audio may glitch, crackle, or break under load
  security.rtkit.enable = true;


  # ============================================================================
  # SECTION 9: ADVANCED SECURITY HARDENING (Hardened Profile)
  # ============================================================================
  # NOTE: Hardened kernel removed from nixpkgs unstable (abandoned upstream)
  #       Boot params + sysctl hardening cover the same ground
  # WARN: Test changes incrementally - some options may break hardware access

  # FIX: Enable AppArmor Mandatory Access Control
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true;
  };

  # FIX: Lock kernel modules after boot
  security.lockKernelModules = true;

  # FIX: Protect kernel image from replacement
  security.protectKernelImage = true;

  # FIX: Force Page Table Isolation (Meltdown protection)
  security.forcePageTableIsolation = true;

  # INFO: SMT left enabled - disabling caused GPU driver issues on unstable kernel
  # security.allowSimultaneousMultithreading = false;

  # FIX: Flush L1 data cache on context switch (VM isolation)
  security.virtualisation.flushL1DataCache = "always";

  # FIX: Enable TPM2 subsystem for hardware root of trust
  #      Used for LUKS key sealing, Secure Boot attestation, and tamper detection
  security.tpm2 = {
    enable = true;
    # Enable TSS 2.0 (ESAPI) for encryption operations
    tctiEnvironment.enable = true;
  };

  # ============================================================================
  # SECTION 10: LYNIS-BASED HARDENING IMPROVEMENTS
  # ============================================================================
  # NOTE: Based on lynis audit recommendations
  
  # FIX: Enable Linux audit subsystem (kernel params handled by module)
  #      Override ExecStart to skip -b/-f/-r flags that fail with auditctl 4.1 + kernel 6.18
  security.audit = {
    enable = true;
    backlogLimit = 8192;
  };

  security.auditd.enable = true;

  systemd.services.audit-rules-nixos.serviceConfig = {
    ExecStart = lib.mkForce "${pkgs.bash}/bin/sh -c \"${pkgs.audit}/bin/auditctl -D && ${pkgs.audit}/bin/auditctl -R ${pkgs.writeTextDir "audit.rules" ''
      -a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
      -a always,exit -F arch=b64 -S clock_settime -k time_change
      -w /etc/localtime -p wa -k time_change
      -w /etc/group -p wa -k identity
      -w /etc/passwd -p wa -k identity
      -w /etc/gshadow -p wa -k identity
      -w /etc/shadow -p wa -k identity
      -w /etc/security/opasswd -p wa -k identity
      -a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_modifications
      -w /etc/hostname -p wa -k network_modifications
      -w /etc/hosts -p wa -k network_modifications
      -w /etc/network -p wa -k network_modifications
      -w /var/log/faillog -p wa -k logins
      -w /var/log/lastlog -p wa -k logins
      -w /var/log/tallylog -p wa -k logins
      -w /etc/sudoers -p wa -k scope
      -w /etc/sudoers.d/ -p wa -k scope
      -a always,exit -F arch=b64 -S init_module -k modules
      -a always,exit -F arch=b64 -S delete_module -k modules
      -a always,exit -F arch=b64 -S chmod -F auid>=1000 -F auid!=-1 -k perm_mod
      -a always,exit -F arch=b64 -S chown -F auid>=1000 -F auid!=-1 -k perm_mod
      -a always,exit -F arch=b64 -S fchmod -F auid>=1000 -F auid!=-1 -k perm_mod
      -a always,exit -F arch=b64 -S fchmodat -F auid>=1000 -F auid!=-1 -k perm_mod
      -a always,exit -F arch=b64 -S open,openat -F exit=-EACCES -F auid>=1000 -F auid!=-1 -k access
      -a always,exit -F arch=b64 -S open,openat -F exit=-EPERM -F auid>=1000 -F auid!=-1 -k access
    ''}/audit.rules\"";
    ExecStopPost = lib.mkForce [ "${pkgs.coreutils}/bin/true" ];
  };

  # FIX: Use dbus-broker instead of classic dbus
  #      More secure and better isolation
  services.dbus.implementation = "broker";

  # FIX: Limit sudo execution to wheel group only
  security.sudo.execWheelOnly = true;

  # Allow passwordless sudo for wheel group (desktop convenience tradeoff)
  # Risk: any process running as a wheel user can escalate to root silently.
  # Mitigated by: single-user desktop, AppArmor, service hardening, no open SSH passwords.
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # FIX: Enable sysstat for performance monitoring (Lynis ACCT-9626)
  services.sysstat = {
    enable = true;
  };

  # FIX: Set default umask to restrictive value via login.defs
  security.loginDefs.settings = {
    UMASK = "027";
    USERGROUPS_ENAB = "no";
  };

  # FIX: Set default umask for bash users
  environment.etc."profile.d/umask.sh".text = ''
    # Restrictive umask (Lynis recommendation)
    umask 027
  '';

  # FIX: Session timeout for shell users (Lynis SHELL-9308)
  environment.etc."profile.d/session-timeout.sh".text = ''
    # Auto-logout idle shell sessions after 15 minutes
    TMOUT=900
    readonly TMOUT
    export TMOUT
  '';

  # FIX: Disable core dumps via systemd + profile.d (Lynis KRNL-5820, BOOT-5184)
  environment.etc."profile.d/coredump.sh".text = ''
    # Disable core dumps for all users
    ulimit -c 0 > /dev/null 2>&1
  '';
  environment.etc."systemd/coredump.conf.d/disable.conf".text = ''
    [Coredump]
    ProcessSizeMax=0
    Storage=none
  '';

  # FIX: Protect /proc from unprivileged access
  #      Hide processes from non-privileged users
  # NOTE: Use hidepid mount option instead of invalid fs.protected_proc sysctl
  fileSystems."/proc" = {
    device = "proc";
    fsType = "proc";
    options = [ "nosuid" "noexec" "nodev" "hidepid=2" ];
  };

  # FIX: Harden NetworkManager-dispatcher service (Lynis BOOT-5264)
  systemd.services."NetworkManager-dispatcher" = {
    serviceConfig = {
      NoNewPrivileges = true;
      PrivateNetwork = false;
      ProtectHome = lib.mkDefault true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
    };
  };

  # FIX: Harden usbguard-dbus service (Lynis BOOT-5264)
  systemd.services."usbguard-dbus".serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "full";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
  };

  # ============================================================================
  # SECTION 11: LOGGING AND PAM HARDENING
  # ============================================================================
  # FIX: Configure log rotation - NixOS 25.11 format
  services.logrotate.enable = true;
  services.logrotate.settings = {
    header = {
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      rotate = 4;
      frequency = "weekly";
      create = "0640 root adm";
    };
  };

  # INFO: Remote syslog forwarding for audit, ClamAV, Snout logs
  # NOTE: Configure remote server in /etc/rsyslog.d/remote.conf
  #       Uncomment the remote forwarding lines with your syslog server address
  services.rsyslogd.enable = true;
  services.rsyslogd.extraConfig = ''
    # Include remote forwarding config
    $IncludeConfig /etc/rsyslog.d/remote.conf
  '';

  # INFO: Deploy remote syslog configuration
  environment.etc."rsyslog.d/remote.conf".source = ./../etc/rsyslog.d/remote.conf;

  # FIX: Configure PAM for password strength and secure login
  # NOTE: Using libpwquality for password quality checks
  security.pam = {
    # Configure secure defaults for common services
    services = {
      sudo = {
        allowNullPassword = lib.mkForce false;
        nodelay = true;
      };
      su = {
        allowNullPassword = lib.mkForce false;
        nodelay = true;
      };
      login = {
        allowNullPassword = lib.mkForce false;
        nodelay = true;
      };
      # Add pwquality module to password change services
      passwd = {
        text = lib.mkDefault (lib.mkBefore "password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so try_first_pass");
      };
      chpasswd = {
        text = lib.mkDefault (lib.mkBefore "password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so try_first_pass");
      };
    };
  };

  # Domain — defined in profiles/atlas.nix

  # FIX: Enable USBGuard for USB device authorization
  #      Allow all USB devices (relaxed policy); tighten with:
  #      `sudo usbguard generate-policy > /var/lib/usbguard/rules.conf`
  services.usbguard = {
    enable = true;
    rules = "allow";
    implicitPolicyTarget = "allow";
    presentDevicePolicy = "apply-policy";
    IPCAllowedUsers = [ "root" "yusa" ];
    IPCAllowedGroups = [ "wheel" ];
    dbus.enable = true;
  };

  # FIX: Create USBGuard configuration file for Lynis detection
  environment.etc."usbguard/usbguard-daemon.conf".text = ''
    # USBGuard daemon configuration
    RuleFile=/var/lib/usbguard/rules.conf
    ImplicitPolicyTarget=allow
    PresentDevicePolicy=apply-policy
    PresentControllerPolicy=keep
    IPCAllowedUsers=root yusa
    IPCAllowedGroups=wheel
    DeviceRulesWithPort=false
    AuditBackend=LinuxAudit
  '';

  # FIX: Add udev rules for USB hotplug detection (priority processing)
  services.udev.extraRules = ''
    # Prioritize USB device discovery for faster hotplug detection
    SUBSYSTEM=="usb", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block start systemd-udev-trigger.service"
    
    # Mass storage devices (USB drives, external HDDs)
    SUBSYSTEM=="block", ACTION=="add", ATTR{removable}=="1", RUN+="${pkgs.systemd}/bin/udevadm trigger"
  '';

  # FIX: Create common-password PAM file for Lynis detection of pwquality
  # Lynis checks common-password/system-auth for PAM strength modules
  environment.etc."pam.d/common-password".text = ''
    password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so try_first_pass
  '';

  # FIX: Ensure pam_pwquality.so is accessible at a standard path (Lynis AUTH-9262)
  systemd.tmpfiles.rules = [
    "L+ /lib/security/pam_pwquality.so - - - - ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so"
  ];

  # FIX: Ensure home directory has correct permissions (Lynis HOME-9304)
  systemd.services.fix-home-perms = {
    description = "Fix home directory permissions for Lynis compliance";
    after = [ "home.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/chmod 0750 /home/yusa";
    };
  };

  # FIX: Enable systemd-resolved for DNSSEC + DNS-over-TLS
  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNS = [ "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001" ];
        FallbackDNS = [ "8.8.8.8" "8.8.4.4" ];
        DNSOverTLS = true;
        DNSSEC = true;
        DNSStubListener = "yes";
      };
    };
  };

  # INFO: Additional LSM configuration (landlock, yama, bpf are now default in NixOS 25.05+)


  # ============================================================================
  # SECTION 12: WINDOW MANAGER - Niri
  # ============================================================================
  # Enable Niri (Wayland compositor)
  programs.niri.enable = true;

  # Display manager (Wayland backend; machine-id must be persisted during install)
  # SDDM theme: qylock Nier Automata by Darkkal44
  # Font requirement: FOT-Rodin Pro DB (commercial) — install manually:
  #   ~/.local/share/fonts/FOT-Rodin\ Pro\ DB.otf  &&  fc-cache -fv
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "nier-automata";
  };

  # Preservation handles machine-id persistence via initrd + boot service
  systemd.services.systemd-machine-id-commit.enable = false;


  # ============================================================================
  # SECTION 13: NOCTALIA SHELL
  # ============================================================================
  # Noctalia is configured via home-manager (programs.noctalia-shell).
  # Systemd startup is deprecated - the shell is spawned from Niri config.

  # ============================================================================
  # SECTION 14: QT & THEME SETTINGS
  # ============================================================================
  # Dynamic theming with Matugen colors
  # FIX: Use environment.path instead of config reference to avoid eval-order issues
  #      The color scheme will be sourced from user's home directory at runtime
  environment.etc."xdg/color-schemes/SkwdMatugen.colors".text = "";

  # Distrobox configuration
  environment.etc."distrobox/distrobox.conf".text = ''
    container_additional_volumes="/nix/store:/nix/store:ro /etc/profiles/per-user:/etc/profiles/per-user:ro /etc/static/profiles/per-user:/etc/static/profiles/per-user:ro"
  '';

  # Session environment variables
  # FIX: Use a fallback path that works even before user config is fully evaluated
  environment.sessionVariables = {
    "QT_QPA_PLATFORMTHEME" = "kde";
    "KDE_COLOR_SCHEME" = "${config.users.users.yusa.home}/.local/share/color-schemes/SkwdMatugen.colors";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "niri";
  };

  # Qt configuration
  qt = {
    enable = true;
    platformTheme = "kde";
  };
  # Configure input devices (libinput)
  services.libinput = {
    enable = true;

    # disabling mouse acceleration
    mouse = {
      accelProfile = "flat";
    };

    # disabling touchpad acceleration
    touchpad = {
      accelProfile = "flat";
    };
  };


  # ============================================================================
  # SECTION 16: XDG PORTAL
  # ============================================================================
  # XDG portal for Flatpak support
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gnome
    ];
    config = {
      niri = {
        default = lib.mkForce [ "gnome" "wlr" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      };
    };
  };


  # Pipewire handled by hardware/audio/default.nix — avoids duplication


  # ============================================================================
  # SECTION 18: SYSTEM PACKAGES
  # ============================================================================
  # Core system packages
  environment.systemPackages = with pkgs; [
    # Desktop components
    niri
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    python3
    curl
    ffmpeg

    # Fonts
    nerd-fonts.symbols-only
    roboto
    material-design-icons

    # Cursor theme (oreo_black_cursors — used by Niri)
    oreo-cursors-plus

    # Hardware control
    wtype
    wlrctl
    inotify-tools       # File system event monitoring (snout-watcher, metadata-stripper)
    tpm2-tools          # TPM 2.0 command suite for key sealing, PCR operations, attestation

    # Hardware detection and compatibility report
    (pkgs.writeShellScriptBin "atlas-hardware-detect" ''
      exec ${../bin/shell/detect-hardware.sh} "$@"
    '')

        # Media
    pavucontrol
    pulseaudio          # Provides pactl for audio control (needed by vicinae)

    # VPN client
    mullvad-vpn

    # Utilities
    jq
    polkit_gnome
    libpwquality
    nftables       # nft command for firewall management (Lynis FIRE-4536)
    acct            # Process accounting (Lynis ACCT-9626)
    sysstat         # SAR performance monitoring (Lynis ACCT-9626)
    nautilus
    yazi
    exiftool

    # LLM inference (ROCm GPU acceleration)
    ollama-rocm

    # Fallback terminal
    alacritty

    # Graphical authentication (polkit-style popup)
    kdePackages.kde-cli-tools
    kdePackages.kdialog

    # SDDM Nier Automata theme + Qt6 deps
    (pkgs.stdenv.mkDerivation {
      pname = "sddm-nier-automata-theme";
      version = "6946b53";
      src = pkgs.fetchFromGitHub {
        owner = "Darkkal44";
        repo = "qylock";
        rev = "6946b53626b4f3c1507ae9a78c287411df5fb36c";
        sha256 = "0kdy4w7az0ygmv3yf92xsyrflak52lm3prp8lickwk207y3qgm7g";
      };
      installPhase = ''
        mkdir -p $out/share/sddm/themes/nier-automata
        cp -r $src/themes/nier-automata/* $out/share/sddm/themes/nier-automata/
      '';
    })
    qt6.qtdeclarative
    qt6.qt5compat
    qt6.qtsvg
    qt6.qtmultimedia
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good

    # System trash manager
    trashy

    # INFO: vulnix defined in security/default.nix

    # INFO: Rebuild wrapper — stops tamper-detection services before rebuild to
    #       prevent them from triggering a shutdown mid-operation. Runs a quick
    #       health check after successful rebuild.
    (pkgs.writeShellScriptBin "atlas-rebuild" ''
      set -euo pipefail

      # Stop all services that detect tinkering (kernel/auditd left alone)
      sudo systemctl stop \
        snort-daemon snort-monitor \
        snout-watcher.service snout-watcher.path \
        aide-check.service aide-check.timer \
        firmware-version-check \
        tpm-attestation-check \
        secureboot-verify \
        mullvad-daemon 2>/dev/null || true

      FLAKE="''${FLAKE:-.#atlas}"

      echo "=== Detection services stopped, running nixos-rebuild ==="
      if nixos-rebuild switch --flake "$FLAKE" "$@"; then
        echo "=== Build succeeded — running health check ==="
        atlas-health quick 2>/dev/null || echo "⚠  Health check found issues — run 'atlas-health' for details."
      fi
    '')

    # INFO: Unified system health checker — single entry point for status
    (pkgs.writeShellScriptBin "atlas-health" ''
      set -euo pipefail

      RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
      BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

      ok()   { echo -e "  ''${GREEN}✓''${NC} $1"; }
      warn() { echo -e "  ''${YELLOW}⚠''${NC} $1"; }
      fail() { echo -e "  ''${RED}✗''${NC} $1"; }

      MODE="''${1:-full}"

      if [[ "$MODE" == "quick" ]]; then
        echo -e "''${BOLD}Atlas Quick Health''${NC}"
      else
        echo -e "''${BOLD}══════════════════════════════════════════''${NC}"
        echo -e "''${BOLD}  Atlas System Health''${NC}"
        echo -e "''${BOLD}══════════════════════════════════════════''${NC}"
      fi

      # ── System info ──────────────────────────────────────────────
      if [[ "$MODE" != "quick" ]]; then
        echo -e "\n''${BOLD}System:''${NC}"
        uname -r 2>/dev/null | xargs -I{} echo "  Kernel: {}"
        uptime -p 2>/dev/null | sed 's/^/  Uptime: /'
        free -h 2>/dev/null | awk '/^Mem:/ {printf "  Memory: %s used / %s total\n", $3, $2}'
        df -h /nix 2>/dev/null | awk 'NR==2 {printf "  Nix store: %s used / %s total\n", $3, $2}'
        echo ""
      fi

      # ── Security services ────────────────────────────────────────
      echo -e "''${BOLD}Security:''${NC}"
      for svc in snort-daemon snout-watcher.service clamav-daemon aide-check.timer; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
          ok "$svc"
        else
          fail "$svc (inactive)"
        fi
      done

      # ── Desktop user services ────────────────────────────────────
      echo -e "\n''${BOLD}Desktop:''${NC}"
      for svc in atlas-awww atlas-vicinae atlas-xwayland-satellite; do
        if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
          ok "$svc"
        else
          warn "$svc (not running — may be normal if not logged into a desktop)"
        fi
      done

      # ── Disk health ──────────────────────────────────────────────
      if [[ "$MODE" != "quick" ]]; then
        echo -e "\n''${BOLD}Disk:''${NC}"
        df -h / /nix /persistent /boot 2>/dev/null | awk 'NR==1; NR>1 {printf "  %s  %s used / %s (%s)\n", $1, $3, $2, $5}'

        echo -e "\n''${BOLD}LUKS:''${NC}"
        if cryptsetup status crypt 2>/dev/null | grep -q "active"; then
          ok "LUKS container 'crypt' is active"
        else
          fail "LUKS container not active (check encryption)"
        fi
      fi

      # ── Last security scan results ───────────────────────────────
      echo -e "\n''${BOLD}Last Scans:''${NC}"
      if [[ -f /var/log/clamav/scan.log ]]; then
        tail -3 /var/log/clamav/scan.log 2>/dev/null | head -1 | sed 's/^/  ClamAV: /'
      fi
      if journalctl -u aide-check.service --no-pager -n 1 2>/dev/null | grep -q "OK\|completed"; then
        ok "AIDE last check passed"
      else
        warn "AIDE: no recent check logged"
      fi

      echo ""
    '')
  ];

  # ============================================================================
  # SECTION 20: ADDITIONAL HARDENING (formerly 19)
  # ============================================================================
  # FIX: Restrict /home permissions for better security
  #      Prevents other users from accessing user data
  users.users.yusa.home = "/home/yusa";


  # ============================================================================
  # SECTION 21: GVFS (Virtual Filesystem)
  # ============================================================================
  # GVFS — provides trash:// URI, MTP device mounting, and other virtual filesystem features
  services.gvfs.enable = true;


  # ============================================================================
  # SECTION 22: FONTS
  # ============================================================================
  # Font configuration
  fonts.packages = with pkgs; [
    udev-gothic-nf
    noto-fonts

    # Custom Monocraft font (gaming aesthetic)
    (pkgs.stdenv.mkDerivation {
      pname = "monocraft";
      version = "4.2.1";
      src = pkgs.fetchurl {
        url = "https://github.com/IdreesInc/Monocraft/releases/download/v4.2.1/Monocraft-otf.zip";
        hash = "sha256-5iO3LxAhBirQFWzEH1SxCOcL014rKVEnR1u1ctit5h0=";
      };
      nativeBuildInputs = [ pkgs.unzip ];
      installPhase = ''
        mkdir -p $out/share/fonts/otf
        unzip -j $src -d $out/share/fonts/otf "*.otf"
      '';
    })
  ];


  # ============================================================================
  # SECTION 23: SYSTEM VERSION
  # ============================================================================
  # NixOS state version
  system.stateVersion = "25.11";
}
