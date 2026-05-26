{ config, pkgs, lib, ... }:

# ============================================================================
# AUDIO (PIPEWIRE / WIREPLUMBER)
# ============================================================================
# PipeWire + WirePlumber for modern audio on Linux.
# ALSA default profile is auto-detected at runtime by WirePlumber —
# no hardcoded PCI address needed.
#
# The old approach used a specific ALSA device name (pci-0000_00_1f.3)
# which only worked on one Intel HDA controller. WirePlumber can now
# auto-detect the default device from its own policy.
# ============================================================================

let
  cfg = config.hardware.audio;
in
{
  imports = [ ];

  options.hardware.audio = {
    alsaDevice = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        `hardware.audio.alsaDevice` — ALSA device name for WirePlumber default
        analog profile. Leave empty ("") to let WirePlumber auto-detect the
        default device. Override only if auto-detection picks the wrong device:
        Example: "~alsa_card.pci-0000_00_1f.3"  (Intel HDA)
        Example: "~alsa_card.usb-USBaudio-DAC-01" (USB DAC)
      '';
    };

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit ALSA support (needed for Steam/Wine audio).";
    };
  };

  config = {
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = cfg.enable32Bit;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    # Only set the default ALSA profile in WirePlumber if a specific device is configured
    services.pipewire.wireplumber.extraConfig = lib.mkIf (cfg.alsaDevice != "") {
      "11-analog-default" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.name" = cfg.alsaDevice; }
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
