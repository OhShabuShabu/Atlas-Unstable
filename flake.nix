{
  description = "Atlas — NixOS configuration with Noctalia shell, security hardening, and gaming focus";
  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    preservation = {
      url = "github:nix-community/preservation";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    atlas-modules = {
      url = "github:OhShabuShabu/Atlas-Modules";
    };
  };
  outputs = inputs @ { self, nixpkgs, home-manager, noctalia, disko, preservation, ... }: {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

    nixosConfigurations = {
      # Current running system — uses existing ext4 layout
      atlas = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs noctalia; };
        modules = [
          preservation.nixosModules.default
          ./files/core/configuration.nix
          ./files/core/current-system.nix
          ./files/core/preservation.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.yusa = { pkgs, inputs, ... }: {
                imports = [
                  noctalia.homeModules.default
                  ./files/core/home.nix
                  ./files/modules/optional/home
                ];
              };
            };
          }
        ];
      };

      # Fresh install target — uses disko (wipes disk)
      atlas-installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs noctalia; };
        modules = [
          disko.nixosModules.disko
          preservation.nixosModules.default
          ./files/core/configuration.nix
          ./files/core/disko.nix
          ./files/core/preservation.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.yusa = { pkgs, inputs, ... }: {
                imports = [
                  noctalia.homeModules.default
                  ./files/core/home.nix
                  ./files/modules/optional/home
                ];
              };
            };
          }
        ];
      };
    };
  };
}
