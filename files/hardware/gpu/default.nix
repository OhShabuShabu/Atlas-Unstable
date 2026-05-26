{ config, pkgs, lib, ... }:

# ============================================================================
# GPU MODULE — AUTO-IMPORT BY VENDOR
# ============================================================================
# Conditionally imports the correct GPU vendor module based on
# hardware.gpu.vendor (auto-detected or manually set).
#
# Detection flow:
#   1. hardware.detect.gpu auto-detects AMD/Intel/NVIDIA from /sys/class/drm/
#   2. This module imports the matching vendor file
#   3. Fallback to generic.nix if unknown or detection unavailable
#   4. Manual override via hardware.gpu.vendor option
# ============================================================================

let
  gpuVendor = config.hardware.gpu.vendor;
in {
  imports = [
    # Import vendor-specific module based on detection
    (if gpuVendor == "amd" then ./amd.nix
    else if gpuVendor == "intel" then ./intel.nix
    else if gpuVendor == "nvidia" then ./nvidia.nix
    else ./generic.nix)
  ];
}
