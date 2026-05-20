{ config, pkgs, ... }:
{
  services.flatpak.enable = true;

  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

      # GUI applications (moved from Nix packages for better sandboxing)
      flatpak install -y app/com.valvesoftware.Steam/x86_64/stable 2>/dev/null || true
      flatpak install -y app/com.discordapp.Discord/x86_64/stable 2>/dev/null || true
      flatpak install -y app/org.telegram.desktop/x86_64/stable 2>/dev/null || true
      flatpak install -y app/dev.vencord.Vesktop/x86_64/stable 2>/dev/null || true
      flatpak install -y app/com.usebottles.bottles/x86_64/stable 2>/dev/null || true
    '';
  };

}