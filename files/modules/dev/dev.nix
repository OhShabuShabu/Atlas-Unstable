{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    git
    bun
    opencode
    claude-code
    neovim
    vscodium
  ];
  home.file = {
    ".config/nvim".source = ./nvim;
  };
}