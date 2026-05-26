{ pkgs, lib, ... }:

# ============================================================================
# AMD CPU CONFIGURATION
# ============================================================================
# AMD-specific kernel parameters and microcode updates.
# Imported automatically when hardware.cpu.vendor == "amd".
# ============================================================================

{
  imports = [ ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  boot.kernelParams = [
    "amd_iommu=on"            # AMD IOMMU for DMA protection + VFIO
    "amd_pstate=guided"       # Guided autonomous frequency selection
    "tsc=reliable"            # TSC is invariant on modern AMD CPUs
  ];
}
