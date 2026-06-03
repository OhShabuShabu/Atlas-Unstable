# ============================================================================
# MODULE: fonts
# CATEGORY: system
# VERSION: 1.0.0
# TAGS: fonts typography nerd-fonts
# DEPS: none
# INFO: Essential fonts including Nerd Fonts for development
# ============================================================================
{ config, pkgs, lib, ... }:

let
  cfg = config.atlas.modules.fonts;
in {
  options.atlas.modules.fonts = {
    enable = lib.mkEnableOption "font configuration";
    nerdy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include Nerd Fonts patched fonts";
    };
  };

  config = lib.mkIf cfg.enable {
    fonts = {
      enableDefaultPackages = true;
      fontconfig = {
        enable = true;
        defaultFonts = {
          monospace = [ "JetBrainsMono Nerd Font" "FiraCode Nerd Font" ];
          sansSerif = [ "Inter" "Noto Sans" ];
          serif = [ "Noto Serif" ];
        };
      };
    };

    fonts.packages = with pkgs; [
      inter
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      jetbrains-mono
      fira-code
    ] ++ lib.optionals cfg.nerdy [
      (nerdfonts.override { fonts = [ "JetBrainsMono" "FiraCode" "NerdFontsSymbolsOnly" ]; })
    ];
  };
}
