{ config, pkgs, lib, ... }:

# ============================================================================
# CPU MODULE — AUTO-IMPORT BY VENDOR
# ============================================================================
# Imports all CPU vendor modules unconditionally; each uses lib.mkIf to
# activate only for its own vendor. This avoids referencing `config` in
# `imports`, which would cause infinite recursion in Nix.
#
# Detection flow:
#   1. hardware.detect.cpu auto-detects Intel/AMD from /proc/cpuinfo
#   2. This module imports all vendor files (safe — guarded by mkIf)
#   3. Fallback to generic.nix if unknown or detection unavailable
#   4. Manual override via hardware.cpu.vendor option
# ============================================================================

let
  cpuVendor = config.hardware.cpu.vendor;
in {
  imports = [
    ./intel.nix
    ./amd.nix
    ./generic.nix
  ];

  # kvm kernel module: enable the right one for virtualization
  boot.kernelModules = lib.mkDefault (
    if cpuVendor == "intel" then [ "kvm-intel" ]
    else if cpuVendor == "amd" then [ "kvm-amd" ]
    else [ "kvm" ]  # Generic kvm works too
  );

  # Microcode: link to enabledRedistributableFirmware status
  hardware.cpu.intel.updateMicrocode = lib.mkDefault (
    cpuVendor == "intel" && config.hardware.enableRedistributableFirmware
  );
  hardware.cpu.amd.updateMicrocode = lib.mkDefault (
    cpuVendor == "amd" && config.hardware.enableRedistributableFirmware
  );
}
