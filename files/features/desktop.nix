{ ... }: {
  flake.modules.nixos.desktop = { pkgs, lib, config, ... }: {
    systemd.services.systemd-logind.serviceConfig = {
      LimitMEMLOCK = "infinity";
    };

    systemd.user.services.awww = {
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

    systemd.user.services.vicinae = {
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
        Environment = "PATH=/etc/profiles/per-user/yusa/bin:/run/current-system/sw/bin:/run/wrappers/bin";
      };
    };

    systemd.user.services.xwayland-satellite = {
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

    systemd.user.services.startup-sound = {
      description = "YoRHa Startup Sound";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.ffmpeg}/bin/ffplay -nodisp -autoexit ${./../audio/startup.mp3}";
        RemainAfterExit = false;
      };
    };

    services.udev.packages = [ pkgs.openrgb ];

    systemd.user.services.openrgb = {
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

    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id.indexOf("org.freedesktop.udisks2.") === 0 && subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';

    security.rtkit.enable = true;

    programs.niri.enable = true;

    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
      theme = "nier-automata";
    };

    systemd.services.systemd-machine-id-commit.enable = false;

    environment.etc."xdg/color-schemes/SkwdMatugen.colors".text = "";

    environment.etc."distrobox/distrobox.conf".text = ''
      container_additional_volumes="/nix/store:/nix/store:ro /etc/profiles/per-user:/etc/profiles/per-user:ro /etc/static/profiles/per-user:/etc/static/profiles/per-user:ro"
    '';

    environment.sessionVariables = {
      "QT_QPA_PLATFORMTHEME" = "kde";
      "KDE_COLOR_SCHEME" = "${config.users.users.yusa.home}/.local/share/color-schemes/SkwdMatugen.colors";
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "niri";
    };

    qt = {
      enable = true;
      platformTheme = "kde";
    };

    services.libinput = {
      enable = true;
      mouse = { accelProfile = "flat"; };
      touchpad = { accelProfile = "flat"; };
    };

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

    services.gvfs.enable = true;

    programs.dconf.enable = true;
  };
}
