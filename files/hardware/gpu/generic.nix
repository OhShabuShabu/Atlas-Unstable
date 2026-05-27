{ config, pkgs, lib, ... }:

# ============================================================================
# GENERIC GPU CONFIGURATION
# ============================================================================
# Safe fallback for unknown or unsupported GPUs.
# Uses modesetting driver (kernel built-in), no vendor-specific firmware,
# no hardware acceleration.
#
# This is a GRACEFUL DEGRADATION path — the system boots and runs a desktop,
# but without GPU acceleration. Users should install the correct GPU module
# for their hardware.
# Guarded by mkIf so it only activates when hardware.gpu.vendor == "generic".
# ============================================================================

lib.mkIf (config.hardware.gpu.vendor == "generic") {
  hardware.graphics = {
    enable = true;
    # No vendor-specific VA-API or Vulkan packages
    extraPackages = [ ];
    extraPackages32 = [ ];
  };

  # No vendor-specific initrd kernel modules for KMS
  # Kernel modesetting works out-of-the-box with simplefb/efifb
  boot.initrd.kernelModules = lib.mkDefault [ ];
  boot.initrd.availableKernelModules = lib.mkDefault [ ];
}
