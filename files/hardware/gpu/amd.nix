{ config, lib, ... }:

lib.mkIf (config.hardware.gpu.vendor == "amd") {
  # RADV open-source Vulkan driver is enabled by default on AMD GPUs
  hardware.graphics.enable = true;

  # Load amdgpu in initrd for early KMS (Plymouth at native resolution)
  # mkBefore ensures amdgpu is the very first module loaded in initrd
  boot.initrd.kernelModules = lib.mkBefore [ "amdgpu" ];
  boot.initrd.availableKernelModules = lib.mkBefore [ "amdgpu" ];
}
