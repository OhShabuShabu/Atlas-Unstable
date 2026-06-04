{ ... }: {
  flake.modules.nixos.nix-config = { config, pkgs, lib, ... }: {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    nix.settings.auto-optimise-store = lib.mkDefault false;

    nix.settings.max-jobs = "auto";
    nix.settings.cores = 0;
    nix.settings.keep-derivations = false;

    nix.settings.min-free = let memMB = config.hardware.memory.totalMB;
      in if memMB < 4096 then 500000000
         else 1000000000;
    nix.settings.max-free = let memMB = config.hardware.memory.totalMB;
      in if memMB < 4096 then 2000000000
         else if memMB < 8192 then 3000000000
         else 5000000000;

    nix.gc.automatic = true;
    nix.gc.dates = "weekly";
    nix.gc.options = "--delete-older-than 30d";

    nixpkgs.config.allowUnfree = true;

    programs.nix-ld.enable = true;

    programs.git = {
      enable = true;
      config = {
        safe.directory = [ "*" ];
      };
    };
  };
}
