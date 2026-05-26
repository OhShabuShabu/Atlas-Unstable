{ config, pkgs, lib, ... }:

# ============================================================================
# CPU MODULE — AUTO-IMPORT BY VENDOR
# ============================================================================
# Conditionally imports the correct CPU vendor module based on
# hardware.cpu.vendor (auto-detected or manually set).
#
# Detection flow:
#   1. hardware.detect.cpu auto-detects Intel/AMD from /proc/cpuinfo
#   2. This module imports the matching vendor file
#   3. Fallback to generic.nix if unknown or detection unavailable
#   4. Manual override via hardware.cpu.vendor option
# ============================================================================

let
  cpuVendor = config.hardware.cpu.vendor;
in {
  imports = [
    # Import vendor-specific module based on detection
    (if cpuVendor == "intel" then ./intel.nix
    else if cpuVendor == "amd" then ./amd.nix
    else ./generic.nix)
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
