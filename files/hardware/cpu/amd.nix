{ config, pkgs, lib, ... }:

# ============================================================================
# AMD CPU CONFIGURATION
# ============================================================================
# AMD-specific kernel parameters and microcode updates.
# Guarded by mkIf so it only activates when hardware.cpu.vendor == "amd".
# ============================================================================

lib.mkIf (config.hardware.cpu.vendor == "amd") {
  boot.kernelParams = [
    "amd_iommu=on"            # AMD IOMMU for DMA protection + VFIO
    "amd_pstate=guided"       # Guided autonomous frequency selection
    "tsc=reliable"            # TSC is invariant on modern AMD CPUs
  ];
}
