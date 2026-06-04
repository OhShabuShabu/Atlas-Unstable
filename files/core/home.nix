{ config, pkgs, lib, inputs, ... }:
{

  home.username = "yusa";
  home.homeDirectory = "/home/yusa";

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    colorScheme = "dark";
    gtk4 = {
      theme = config.gtk.theme;
    };
  };

  # dconf — required by Nautilus to persist settings
  dconf.enable = true;
  dconf.settings = {
    "org/gnome/desktop/media-handling" = {
      automount = true;
      automount-open = true;
    };
    # REMOVED: show-mounts-for-internal-drives was removed in Nautilus 50.x
    # System mount filtering is now handled via patched nautilus-sidebar.c
    # (see files/patches/nautilus-hide-system-mounts.patch (overlay in flake.nix))
  };


  # Force dark mode for X11/XWayland apps via xsettings
  xdg.configFile."xsettingsd/Xwayland.conf".text = ''
    Net/ThemeName "Adwaita-dark"
    Net/IconThemeName "Papirus-Dark"
    Gtk/ApplicationPreferDarkTheme 1
  '';
  home.sessionVariables = {
    GTK_THEME = "Adwaita-dark";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };

  # FIX: Use sessionPath to properly prepend to PATH
  # home.sessionPath prepends to $PATH at shell startup
  # NOTE: Concatenate with home.homeDirectory to avoid literal $HOME expansion
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  # Enable fontconfig for fonts
  fonts.fontconfig.enable = true;
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Roboto" ];
    serif = [ "Noto Serif" ];
    monospace = [ "Monocraft" ];
  };
  
  xdg.mimeApps.enable = true;

  # Desktop entries for YoRHa system tools — shows up in vicinae/Noctalia app launcher
  xdg.desktopEntries."yorha-health" = {
    name = "YoRHa Health";
    comment = "Run system health check (security, services, storage)";
    exec = "yorha-health";
    terminal = true;
    categories = [ "System" "Utility" ];
  };
  xdg.desktopEntries."encrypted-storage" = {
    name = "Encrypted Storage";
    comment = "Mount or manage the gocryptfs encrypted storage folder";
    exec = "encrypted-storage";
    terminal = true;
    categories = [ "System" "Utility" ];
  };
  xdg.desktopEntries."snout-scan" = {
    name = "Security Scan";
    comment = "Run Snout quarantine scan and check security posture";
    exec = "snout scan";
    terminal = true;
    categories = [ "System" "Security" ];
  };
  xdg.desktopEntries."yorha-hardware-detect" = {
    name = "Hardware Report";
    comment = "Detect and report CPU, GPU, and system hardware";
    exec = "yorha-hardware-detect";
    terminal = true;
    categories = [ "System" "Utility" ];
  };
  xdg.desktopEntries."odysseus-logs" = {
    name = "Odysseus Logs";
    comment = "View real-time Odysseus container logs";
    exec = "odysseus-logs";
    terminal = true;
    categories = [ "System" "Utility" ];
  };

  xdg.mimeApps.defaultApplications = {
  "text/plain" = "vscodium.desktop";
  "text/css" = "vscodium.desktop";
  "application/x-shellscript" = "vscodium.desktop";
  "application/x-zerosize" = "vscodium.desktop";
  "text/html" = "firefox.desktop";
  "x-scheme-handler/http" = "firefox.desktop";
  "x-scheme-handler/https" = "firefox.desktop";
  "application/pdf" = "firefox.desktop";
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "libreoffice.desktop";
  "image/jpeg" = "imv.desktop";
  "image/png" = "imv.desktop";
  "image/gif" = "firefox.desktop";
  "image/webp" = "org.gnome.eog.desktop";
  "image/heif" = "imv.desktop";
  "audio/mpeg" = "org.gnome.Decibels.desktop";
  "inode/directory" = "org.gnome.Nautilus.desktop";
  "video/mp4" = "mpv.desktop";
  "video/x-matroska" = "mpv.desktop";
  "video/webm" = "mpv.desktop";
  "video/ogg" = "mpv.desktop";
  "video/quicktime" = "mpv.desktop";
  "video/x-flv" = "mpv.desktop";
  "video/x-msvideo" = "mpv.desktop";
  "video/x-ms-wmv" = "mpv.desktop";
  "video/mpeg" = "mpv.desktop";
  };

  # FIX: Updated to match system stateVersion for consistency
  #      Home Manager release that your configuration is compatible with
  home.stateVersion = "25.11";
  
# INFO: Packages
  # NOTE: libnotify is required for notify-send in ClamAV and other notifications
  home.packages = with pkgs; [
    # Shell & tools
    nushell
    fzf
    btop
    tty-clock

    # Desktop
    vicinae
    ghostty
    xwayland-satellite
    adwaita-icon-theme
    libnotify
    wl-clipboard
    xdg-utils

    # Theming (Matugen color generation)
    matugen

    # Development
    flatpak-builder

    # NOTE: papirus-icon-theme and gnome-themes-extra are auto-installed
    # by gtk config above — no need to duplicate here.
    # NOTE: vscodium is expected for MIME associations below; add it to
    # system packages or dev module if not already present.
  ];

# INFO: Files
  home.file = {
    ".config/niri".source                         = ../config/niri;
    ".config/nushell/shellrc.nu".source           = ./config/shellrc.nu;
    ".config/nix".source                          = ./config/nix;

    # Alacritty fallback terminal configuration
    ".config/alacritty/alacritty.toml".text = ''
      [window]
      opacity = 0.95
      padding = { x = 10, y = 10 }

      [font]
      normal = { family = "Monocraft", style = "Regular" }
      size = 13

      [cursor]
      style = { shape = "Bar", blinking = "On" }

      [shell]
      program = "${pkgs.nushell}/bin/nu"
    '';

    # Ghostty terminal configuration
    ".config/ghostty/config".text = ''
      font-family = Monocraft
      font-size = 13
      command = ${pkgs.nushell}/bin/nu
      background-opacity = 0.95
      background-blur = 1
      window-padding-x = 10
      window-padding-y = 10
      cursor-style = bar
      cursor-style-blink = true
      confirm-close-surface = false
      resize-overlay = never
    '';

  };
  programs.home-manager.enable = true;

  # Seed Mullvad browser profile from yorha-modules on first activation.
  # MOZ_APP_NAME is "mullvadbrowser", so the profile dir is ~/.mozilla/mullvadbrowser/.
  # home.file symlinks won't work because the Nix store is read-only at runtime.
  home.activation.mullvadBrowserProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
    SRC="${inputs.yorha-modules}/privacy/mullvadbrowser"
    if [ ! -f "$HOME/.mozilla/mullvadbrowser/profiles.ini" ]; then
      if [ -d "$SRC" ]; then
        mkdir -p "$HOME/.mozilla/mullvadbrowser"
        cp -r --no-preserve=ownership "$SRC/." "$HOME/.mozilla/mullvadbrowser/"
      else
        echo "WARNING: Mullvad browser profile seed not found at $SRC — skipping (this is expected after garbage collection)"
      fi
    fi
  '';

  # Git identity is not secret - update per-machine.
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "yusa";
        email = "local@YoRHa.os";
      };
      # Trust all repos to avoid libgit2 ownership errors when nix evaluates
      # the flake under a different user context (e.g. nix daemon as root).
      safe.directory = "*";
    };
  };
  
  programs.noctalia-shell = {
    enable = true;

    settings = {
      settingsVersion = 59;

      bar = {
        barType = "floating";
        position = "top";
        monitors = [ ];
        density = "default";
        showOutline = false;
        showCapsule = true;
        capsuleOpacity = 1;
        capsuleColorKey = "none";
        widgetSpacing = 5;
        contentPadding = 8;
        fontScale = 1;
        enableExclusionZoneInset = true;
        backgroundOpacity = 0.93;
        useSeparateOpacity = false;
        marginVertical = 4;
        marginHorizontal = 308;
        frameThickness = 8;
        frameRadius = 12;
        outerCorners = true;
        hideOnOverview = false;
        displayMode = "always_visible";
        autoHideDelay = 500;
        autoShowDelay = 150;
        showOnWorkspaceSwitch = true;

        widgets = {
          left = [
            {
              id = "Clock";
              clockColor = "none";
              customFont = "";
              formatHorizontal = "HH:mm ddd, MMM dd";
              formatVertical = "HH mm - dd MM";
              tooltipFormat = "HH:mm ddd, MMM dd";
              useCustomFont = false;
            }
          ];
          center = [
            {
              id = "Workspace";
              characterCount = 2;
              colorizeIcons = false;
              emptyColor = "primary";
              enableScrollWheel = true;
              focusedColor = "primary";
              followFocusedScreen = false;
              fontWeight = "bold";
              groupedBorderOpacity = 1;
              hideUnoccupied = false;
              iconScale = 0.8;
              labelMode = "index";
              occupiedColor = "primary";
              pillSize = 0.6;
              showApplications = false;
              showApplicationsHover = false;
              showBadge = true;
              showLabelsOnlyWhenOccupied = true;
              unfocusedIconsOpacity = 1;
            }
          ];
          right = [
            {
              id = "Tray";
              blacklist = [ ];
              chevronColor = "none";
              colorizeIcons = false;
              drawerEnabled = true;
              hidePassive = false;
              pinned = [ ];
            }
            {
              id = "Volume";
              displayMode = "onhover";
              iconColor = "none";
              middleClickCommand = "pwvucontrol || pavucontrol";
              textColor = "none";
            }
            {
              id = "ControlCenter";
              colorizeDistroLogo = false;
              colorizeSystemIcon = "tertiary";
              colorizeSystemText = "none";
              customIconPath = "";
              enableColorization = true;
              icon = "noctalia";
              useDistroLogo = true;
            }
            {
              id = "Battery";
              deviceNativePath = "__default__";
              displayMode = "graphic";
              hideIfIdle = true;
              hideIfNotDetected = true;
              showNoctaliaPerformance = true;
              showPowerProfiles = true;
            }
          ];
        };

        mouseWheelAction = "none";
        reverseScroll = false;
        mouseWheelWrap = true;
        middleClickAction = "none";
        middleClickFollowMouse = false;
        middleClickCommand = "";
        rightClickAction = "controlCenter";
        rightClickFollowMouse = true;
        rightClickCommand = "";
        screenOverrides = [ ];
      };

      general = {
        avatarImage = "";
        dimmerOpacity = 0.2;
        showScreenCorners = false;
        forceBlackScreenCorners = false;
        scaleRatio = 1;
        radiusRatio = 1;
        iRadiusRatio = 1;
        boxRadiusRatio = 1;
        screenRadiusRatio = 1;
        animationSpeed = 1;
        animationDisabled = false;
        compactLockScreen = false;
        lockScreenAnimations = false;
        lockOnSuspend = true;
        showSessionButtonsOnLockScreen = true;
        showHibernateOnLockScreen = false;
        enableLockScreenMediaControls = false;
        enableShadows = true;
        enableBlurBehind = true;
        shadowDirection = "bottom_right";
        shadowOffsetX = 2;
        shadowOffsetY = 3;
        language = "";
        allowPanelsOnScreenWithoutBar = true;
        showChangelogOnStartup = true;
        telemetryEnabled = false;
        enableLockScreenCountdown = true;
        lockScreenCountdownDuration = 10000;
        autoStartAuth = false;
        allowPasswordWithFprintd = false;
        clockStyle = "custom";
        clockFormat = "hh\nmm";
        passwordChars = true;
        lockScreenMonitors = [ ];
        lockScreenBlur = 0;
        lockScreenTint = 0;
        keybinds = {
          keyUp = [ "K" ];
          keyDown = [ "J" ];
          keyLeft = [ "H" ];
          keyRight = [ "L" ];
          keyEnter = [ "Return" "Enter" ];
          keyEscape = [ "Esc" ];
          keyRemove = [ "Del" ];
        };
        reverseScroll = false;
        smoothScrollEnabled = true;
      };

      location = {
        name = "Berlin";
        weatherEnabled = true;
        weatherShowEffects = true;
        weatherTaliaMascotAlways = false;
        useFahrenheit = false;
        use12hourFormat = false;
        showWeekNumberInCalendar = false;
        showCalendarEvents = true;
        showCalendarWeather = true;
        analogClockInCalendar = false;
        firstDayOfWeek = -1;
        hideWeatherTimezone = false;
        hideWeatherCityName = false;
        autoLocate = false;
      };

      noctaliaPerformance = {
        disableWallpaper = false;
        disableDesktopWidgets = true;
      };

      dock = {
        enabled = false;
      };
    };
  };

  programs.opencode.enable = true;
  programs.nushell = {
    enable = true;
    settings = {
      show_banner = false;
    };
    extraConfig = ''
      source ~/.config/nushell/shellrc.nu
    '';
  };
  programs.zoxide = {
    enable = true;
    enableNushellIntegration = true;
    options = ["--cmd cd"];
  };
  systemd.user.startServices = true;

  # Create awww cache directory to prevent cache warnings
  home.activation.createAwwwCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p $HOME/.cache/awww
  '';
}
