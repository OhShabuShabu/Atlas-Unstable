{ ... }:

{
  imports = [ ];

  # RADV open-source Vulkan driver is enabled by default on AMD GPUs
  hardware.graphics.enable = true;

  # ollama-rocm moved to optional extras.nix module (atlas-modules)
}
