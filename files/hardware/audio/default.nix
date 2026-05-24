{ lib, pkgs, ... }:

let
  audioDevice = "~alsa_card.pci-0000_00_1f.3";
in
{
  imports = [ ];

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
                "device.name" = audioDevice;
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
}
