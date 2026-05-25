{ config, lib, ... }:

{
  imports = [ ];

  # RADV open-source Vulkan driver is enabled by default on AMD GPUs
  hardware.graphics.enable = true;

  # Load amdgpu in initrd so Plymouth shows KMS at native resolution during LUKS prompt.
  # Conditioned on hostname: Atlas has AMD, other machines would bundle ~100MB+ firmware
  # for hardware they don't have. Create hardware/gpu/<vendor>.nix for your GPU.
  boot.initrd.kernelModules = lib.mkIf (config.networking.hostName == "atlas") [ "amdgpu" ];
  boot.initrd.availableKernelModules = lib.mkIf (config.networking.hostName == "atlas") [ "amdgpu" ];

  # ollama-rocm moved to optional extras.nix module (atlas-modules)
}
