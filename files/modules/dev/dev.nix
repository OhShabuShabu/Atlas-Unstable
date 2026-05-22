{ config, pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    git
    gcc
    bun
    opencode
    claude-code
    neovim
    vscodium
  ];

  home.activation.setupNvim = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/.config/nvim" ]; then
      ${pkgs.git}/bin/git clone https://github.com/LazyVim/starter.git "$HOME/.config/nvim"
    else
      cd "$HOME/.config/nvim" && ${pkgs.git}/bin/git pull --ff-only
    fi
    # fix partial clone flag that breaks on some git versions
    ${pkgs.gnused}/bin/sed -i 's/--filter=blob:none //' "$HOME/.config/nvim/lua/config/lazy.lua"
  '';
}
