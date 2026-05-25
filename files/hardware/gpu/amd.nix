{ ... }:

{
  imports = [ ];

  # RADV open-source Vulkan driver is enabled by default on AMD GPUs
  hardware.graphics.enable = true;

  # GPU initrd kernel modules moved to atlas-modules (gpu-amd.nix / gpu-intel.nix / gpu-nvidia.nix).
  # The installer auto-detects GPU hardware and downloads only the matching module to
  # files/modules/optional/nixos/, keeping initrd small by bundling only one GPU's firmware.
  # See: ~/atlas-modules/gpu-*.nix

  # ollama-rocm moved to optional extras.nix module (atlas-modules)
}
