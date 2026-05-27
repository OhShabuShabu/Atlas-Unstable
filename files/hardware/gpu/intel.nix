{ config, pkgs, lib, ... }:

# ============================================================================
# INTEL GPU CONFIGURATION
# ============================================================================
# Intel integrated graphics with full VA-API hardware acceleration.
# Works on Intel HD Graphics 2000+ through Arc/Xe.
# Guarded by mkIf so it only activates when hardware.gpu.vendor == "intel".
# ============================================================================

lib.mkIf (config.hardware.gpu.vendor == "intel") {
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver       # VA-API driver for HD Graphics 5000+ / UHD / Iris / Arc
      vaapiIntel               # Legacy VA-API driver for older GPUs
      vaapiVdpau               # VDPAU wrapper for VA-API
      libvdpau-va-gl           # VDPAU-to-VA-API bridge
    ];
  };

  # Load i915 in initrd for early KMS (Plymouth at native resolution)
  boot.initrd.kernelModules = [ "i915" ];
  boot.initrd.availableKernelModules = [ "i915" ];

  environment.systemPackages = with pkgs; [
    intel-gpu-tools            # intel_gpu_top, intel_gpu_time
  ];
}
