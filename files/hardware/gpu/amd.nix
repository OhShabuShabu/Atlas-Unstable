{ lib, ... }:

{
  imports = [ ];

  # RADV open-source Vulkan driver is enabled by default on AMD GPUs
  hardware.graphics.enable = true;

  # Load amdgpu in initrd so Plymouth shows KMS at native resolution during LUKS prompt.
  # Kept per-vendor instead of blanket-importing all GPU drivers (~200MB+ firmware saved).
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.initrd.availableKernelModules = [ "amdgpu" ];

  # ollama-rocm moved to optional extras.nix module (atlas-modules)
}
