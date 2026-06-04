{
  description = "YoRHa — NixOS configuration with Noctalia shell, security hardening, and gaming focus";

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    preservation.url = "github:nix-community/preservation";
    yorha-modules = {
      url = "github:OhShabuShabu/Atlas-Modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    odysseus = {
      url = "github:pewdiepie-archdaemon/odysseus";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake-modules/systems.nix
        ./flake-modules/flake-parts.nix
        ./flake-modules/per-system.nix
        ./flake-modules/overlay.nix
        ./flake-modules/defaults.nix
        ./flake-modules/lib.nix
        ./flake-modules/hosts.nix
        ./files/features/boot.nix
        ./files/features/network.nix
        ./files/features/nix-config.nix
        ./files/features/user.nix
        ./files/features/desktop.nix
        ./files/features/hardening.nix
        ./files/features/packages.nix
        ./files/features/fonts.nix
        ./files/features/virtualisation.nix
      ];
    };
}
