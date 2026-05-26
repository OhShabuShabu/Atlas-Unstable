# ============================================================================
# ATLAS SYSTEM CONFIGURATION
# ============================================================================
# Main NixOS configuration file - imports all module components
# This configuration follows NixOS best practices for security,
# privacy, and desktop use.
# ============================================================================

{ config, pkgs, lib, inputs, ... }:
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

    # INFO: TPM sealing & attestation (LUKS key sealing, PCR integrity check)
    ../modules/security/tpm-sealing.nix

    # INFO: LUKS keyfile with TPM sealing (2FA unlock: passphrase + keyfile)
    ../modules/security/luks-keyfile.nix

    # INFO: Secure Boot kernel signing
    ../modules/security/secureboot.nix

    # INFO: Memory wipe & anti-forensics (DRAM wipe, log shredding)
    ../modules/security/memory-wipe.nix

    # INFO: IMA/EVM kernel-level file integrity
    ../modules/security/ima-evm.nix

    # INFO: TPM/UEFI monitoring & tamper detection
    ../modules/security/tpm-monitoring.nix

    # INFO: Firmware version attestation (detects unauthorized BIOS/UEFI updates)
    ../modules/security/firmware-check.nix

    # INFO: LUKS unlock method test suite (test-luks-methods command)
    ../modules/security/luks-test.nix

    # INFO: Feature modules (from external atlas-modules repo)
    ../modules/optional/nixos
  ];


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

    # TPM 2.0 kernel modules for hardware security module access
    # Required for LUKS key sealing, Secure Boot attestation, and tamper detection
    initrd.availableKernelModules = [ "tpm_tis" "tpm_crb" "tpm" ];

    # GPU initrd kernel modules moved to hardware/gpu/<vendor>.nix for per-machine selection.
    # Only include the driver for the actual hardware — all three bundles add ~200MB+ firmware
    # to every initrd, overwhelming small EFI partitions on non-Atlas machines.

    # Ensure Plymouth waits for udev to settle before showing the splash
    # This gives the GPU driver time to load firmware and set up KMS
    initrd.systemd.services."plymouth-start" = {
      after = [ "systemd-udev-settle.service" ];
      wants = [ "systemd-udev-settle.service" ];
    };

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

  # ============================================================================
  # SECTION 2: NETWORK CONFIGURATION
  # ============================================================================
  # Host name
  networking.hostName = "atlas";

  # Use NetworkManager with systemd-resolved for DNSSEC + DNS-over-TLS
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  # Disable DHCP client (static IP)
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;

  # Custom nameservers (fallback when systemd-resolved is unavailable)
  # Primary DNS set in services.resolved below
  networking.nameservers = [
    "1.1.1.1"
    "1.0.0.1"
    "8.8.8.8"
    "8.8.4.4"
  ];


  # ============================================================================
  # SECTION 3: HOME MANAGER
  # ============================================================================
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

  # GC thresholds: keep 1GB min free, clean up to 5GB
  nix.settings.min-free = 1000000000;
  nix.settings.max-free = 5000000000;

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
  # Set timezone
  time.timeZone = "Europe/Berlin";

  # Default locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Additional locale settings (German)
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };


  # ============================================================================
  # SECTION 6: USER CONFIGURATION
  # ============================================================================
  # Main user account
  users.users.yusa = {
    isNormalUser = true;
    description = "yusa";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
    # Prevent creating files directly in ~/ on tmpfs.
    # Persisted paths (bind-mounted from /persistent/home/yusa/) remain writable.
    # Subdirectories like .config/ and .local/ are pre-created via tmpfiles so
    # home-manager activation and applications can still write into them.
    homeMode = "0555";
  };


  # ============================================================================
  # SECTION 7: SYSTEMD SERVICES
  # ============================================================================
  # FIX: Increase memlock limit for logind so it can attach BPF filters
  #      for udev event monitoring (default 8M is too low with bpf_jit_harden=2)
  systemd.services.systemd-logind.serviceConfig = {
    LimitMEMLOCK = "infinity";
  };

  # Polkit GNOME authentication agent
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
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

  # FIX: Protect /proc from unprivileged access
  #      Hide processes from non-privileged users
  # NOTE: Use hidepid mount option instead of invalid fs.protected_proc sysctl
  fileSystems."/proc" = {
    device = "proc";
    fsType = "proc";
    options = [ "nosuid" "noexec" "nodev" "hidepid=2" ];
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
        text = lib.mkDefault (lib.mkBefore "password requisite ${pkgs.libpwquality}/lib/security/pam_pwquality.so try_first_pass");
      };
      chpasswd = {
        text = lib.mkDefault (lib.mkBefore "password requisite ${pkgs.libpwquality}/lib/security/pam_pwquality.so try_first_pass");
      };
    };
  };

  # FIX: Set domain for DNS
  networking.domain = "local";

  # FIX: Enable USBGuard for USB device authorization
  #      Allow all USB devices (relaxed policy); tighten with:
  #      `sudo usbguard generate-policy > /var/lib/usbguard/rules.conf`
  services.usbguard = {
    enable = true;
    rules = "allow";
    implicitPolicyTarget = "allow";
    presentDevicePolicy = "apply-policy";
    IPCAllowedUsers = [ "yusa" ];
    IPCAllowedGroups = [ "wheel" ];
    dbus.enable = true;
  };

  # FIX: Add udev rules for USB hotplug detection (priority processing)
  services.udev.extraRules = ''
    # Prioritize USB device discovery for faster hotplug detection
    SUBSYSTEM=="usb", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block start systemd-udev-trigger.service"
    
    # Mass storage devices (USB drives, external HDDs)
    SUBSYSTEM=="block", ACTION=="add", ATTR{removable}=="1", RUN+="${pkgs.systemd}/bin/udevadm trigger"
  '';

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
    "KDE_COLOR_SCHEME" = "/home/yusa/.local/share/color-schemes/SkwdMatugen.colors";
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
    tpm2-tools          # TPM 2.0 command suite for key sealing, PCR operations, attestation

    # Media
    pavucontrol

    # Utilities
    jq
    polkit_gnome
    libpwquality
    nautilus
    yazi
    exiftool

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
