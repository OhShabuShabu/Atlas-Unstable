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

    gtk3.extraConfig = { Settings = ''gtk-application-prefer-dark-theme=1''; };
    gtk4 = {
      theme = config.gtk.theme;
      extraConfig = { Settings = ''gtk-application-prefer-dark-theme=1''; };
    };
  };
  #dconf.settings = {
  #"org/virt-manager/virt-manager/connections" = {
  #  autoconnect = ["qemu:///system"];
  #  uris = ["qemu:///system"];
  #  };
  #};



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
    nushell
    fzf
    btop
    vicinae
    ghostty
    xwayland-satellite
    lua
    adwaita-icon-theme
    papirus-icon-theme
    gnome-themes-extra
    libnotify
    wl-clipboard
    xdg-utils
    tty-clock
    matugen
    flatpak-builder
  ];

# INFO: Files
  home.file = {
    ".icons".source                               = ../config/.icons;
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

    # Mullvad browser profile (from external atlas-modules repo)
    ".local/share/mullvad-browser/profiles.ini".source          = "${inputs.atlas-modules}/privacy/mullvadbrowser/profiles.ini";
    ".local/share/mullvad-browser/installs.ini".source          = "${inputs.atlas-modules}/privacy/mullvadbrowser/installs.ini";
    ".local/share/mullvad-browser/ipg7sh9x.default-release-1".source = "${inputs.atlas-modules}/privacy/mullvadbrowser/ipg7sh9x.default-release-1";

  };
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "OhShabuShabu";
        email = "greens2acc@gmail.com";
      };
    };
  };
  
  programs.noctalia-shell = {
    enable = true;
    settings = {
      bar = {
        position = "top";
        widgets = {
          left = [
            { id = "Launcher"; }
            { id = "Clock"; }
          ];
          center = [
            { id = "Workspace"; }
          ];
          right = [
            { id = "Tray"; }
            { id = "Volume"; }
            { id = "ControlCenter"; }
          ];
        };
      };
      general.avatarImage = "";
      notifications.enabled = true;
      osd.enabled = true;
      colorSchemes.predefinedScheme = "Catppuccin Mocha";
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
