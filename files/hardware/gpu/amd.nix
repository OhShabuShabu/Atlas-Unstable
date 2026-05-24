{ pkgs, lib, ... }:

{
  imports = [ ];

  # RADV open-source Vulkan driver is enabled by default on AMD GPUs
  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    ollama-rocm
  ];
}
