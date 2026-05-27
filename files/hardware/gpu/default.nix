{ config, pkgs, lib, ... }:

# ============================================================================
# GPU MODULE — AUTO-IMPORT BY VENDOR
# ============================================================================
# Imports all GPU vendor modules unconditionally; each uses lib.mkIf to
# activate only for its own vendor. This avoids referencing `config` in
# `imports`, which would cause infinite recursion in Nix.
#
# Detection flow:
#   1. hardware.detect.gpu auto-detects AMD/Intel/NVIDIA from /sys/class/drm/
#   2. This module imports all vendor files (safe — guarded by mkIf)
#   3. Fallback to generic.nix if unknown or detection unavailable
#   4. Manual override via hardware.gpu.vendor option
# ============================================================================

let
  gpuVendor = config.hardware.gpu.vendor;
in {
  imports = [
    ./amd.nix
    ./intel.nix
    ./nvidia.nix
    ./generic.nix
  ];
}
