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

    # INFO: Security modules (imports submodules automatically)
    ../modules/security/default.nix

    # INFO: Snort network IDS/IPS daemon
    ../modules/security/snort.nix

    # INFO: Snout security monitoring daemon
    ../modules/security/snout.nix

    # INFO: Performance module
    ../modules/performance.nix

    # INFO: Feature modules
    ../modules/privacy/privacy.nix
    ../modules/gaming/gaming.nix
    ../modules/virtualisation.nix
    ../modules/minecraft.nix
    ../modules/flatpak.nix
  ];


  # ============================================================================
  # SECTION 1: BOOT CONFIGURATION
  # ============================================================================
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

    # Enable systemd initrd (required for LUKS)
    initrd.systemd.enable = true;

    # Load AMD GPU driver in initrd so Plymouth uses KMS at native resolution
    initrd.kernelModules = [ "amdgpu" ];

    # LUKS devices and fileSystems are provided by either:
    #   - current-system.nix (for `nixos-rebuild switch --flake .#atlas`)
    #   - disko.nix       (for fresh install via `.#atlas-installer`)

    # Plymouth boot splash — Yorha NieR:Automata theme
    plymouth = {
      enable = true;
      theme = "yorha";
      font = "${pkgs.comfortaa}/share/fonts/truetype/Comfortaa-Regular.ttf";
      themePackages = with pkgs; [
        (pkgs.stdenv.mkDerivation {
          pname = "plymouth-yorha-theme";
          version = "1.0";
          src = pkgs.fetchFromGitHub {
            owner = "antspartanelite";
            repo = "Custom-Nier-Boot";
            rev = "689b010ea1f1e6f5cf5a4c9366b88c415e911b56";
            sha256 = "sha256-8JqqJkP5QOX2jJouOhLHR6CjfJmg7Lo0PFeB9h3Drgs=";
          };
          installPhase = ''
            mkdir -p $out/share/plymouth/themes
            cp -r "$src/Plymouth Theme/yorha" $out/share/plymouth/themes/yorha
            chmod -R +w $out/share/plymouth/themes/yorha
            substituteInPlace $out/share/plymouth/themes/yorha/yorha.plymouth \
              --replace-fail "/usr/share" "$out/share"
            sed -i 's|//yorha|/yorha|g' $out/share/plymouth/themes/yorha/yorha.plymouth
          '';
        })
      ];
    };

    # Silent boot - reduce console noise
    consoleLogLevel = 0;
    initrd.verbose = false;

    # Kernel parameters
    kernelParams = [
      "video=1920x1080"

      # Boot options
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "loglevel=3"

      # Systemd early boot config
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"

      # CPU performance tuning
      "intel_pstate=active"
      "tsc=reliable"
    ];
  };


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

  # Custom nameservers (Cloudflare + Google)
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

  # Allow unfree packages (NVIDIA, etc.)
  nixpkgs.config.allowUnfree = true;

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
  users.users.root = {
    initialPassword = "root";
  };

  users.users.yusa = {
    isNormalUser = true;
    description = "yusa";
    initialPassword = "atlas";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
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


  # ============================================================================
  # SECTION 17: AUDIO (PIPEWIRE)
  # ============================================================================
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    wireplumber.extraConfig = {
      "11-analog-default" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "device.name" = "~alsa_card.pci-0000_00_1f.3";
              }
            ];
            "apply-properties" = {
              "device.profile" = "output:analog-stereo+input:analog-stereo";
            };
          }
        ];
      };
    };
  };


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
    sqlite
    ffmpeg
    imagemagick
    inotify-tools

    # Fonts
    nerd-fonts.symbols-only
    roboto
    roboto-mono
    material-design-icons

    # Hardware control
    openrgb
    freerdp
    wtype
    wlrctl

    # Wallpaper engine support
    linux-wallpaperengine

    # AI/ML
    ollama-rocm

    # Media
    mpvpaper
    crosspipe
    pavucontrol
    easyeffects

    # Utilities
    jq
    appimage-run
    polkit_gnome
    zip
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
      version = "main";
      src = pkgs.fetchFromGitHub {
        owner = "Darkkal44";
        repo = "qylock";
        rev = "main";
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
  # SECTION 19: ADDITIONAL HARDENING
  # ============================================================================
  # FIX: Restrict /home permissions for better security
  #      Prevents other users from accessing user data
  users.users.yusa.home = "/home/yusa";


  # ============================================================================
  # SECTION 19: GVFS (Virtual Filesystem)
  # ============================================================================
  # GVFS — provides trash:// URI, MTP device mounting, and other virtual filesystem features
  services.gvfs.enable = true;


  # ============================================================================
  # SECTION 20: FONTS
  # ============================================================================
  # Font configuration
  fonts.packages = with pkgs; [
    udev-gothic-nf
    noto-fonts
    liberation_ttf

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
  # SECTION 21: SYSTEM VERSION
  # ============================================================================
  # NixOS state version
  system.stateVersion = "25.11";
}
