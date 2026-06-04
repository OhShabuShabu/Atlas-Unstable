{ inputs, config, ... }: let
  mkHomeManagerConfig = allInputs: {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inputs = allInputs; };
      users.yusa = { pkgs, inputs, ... }: {
        imports = [
          inputs.sops-nix.homeManagerModules.sops
          allInputs.noctalia.homeModules.default
          ./../files/core/home.nix
          ./../files/modules/optional/home
        ];
      };
    };
  };

  nixos = config.flake.modules.nixos;
in {
  flake.nixosConfigurations = {
    yorha = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; noctalia = inputs.noctalia; };
      modules = [
        nixos.nautilus-overlay
        nixos.boot
        nixos.network
        nixos.nix-config
        nixos.user
        nixos.desktop
        nixos.packages
        nixos.hardening
        nixos.fonts
        nixos.virtualisation
        inputs.preservation.nixosModules.default
        inputs.sops-nix.nixosModules.sops
        ./../files/core/configuration.nix
        ./../files/core/current-system.nix
        ./../files/core/preservation.nix
        ./../files/core/hardware-configuration.nix
        ./../files/hardware/default.nix
        ./../files/profiles/default.nix
        ./../files/modules/security/default.nix
        ./../files/modules/security/snort.nix
        ./../files/modules/security/snout.nix
        ./../files/modules/optional/nixos
        ./../files/modules/module-manager/default.nix
        inputs.home-manager.nixosModules.home-manager
        (mkHomeManagerConfig inputs)
      ];
    };

    yorha-installer = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; noctalia = inputs.noctalia; };
      modules = [
        nixos.nautilus-overlay
        nixos.boot
        nixos.network
        nixos.nix-config
        nixos.user
        nixos.desktop
        nixos.packages
        nixos.hardening
        nixos.fonts
        nixos.virtualisation
        inputs.disko.nixosModules.disko
        inputs.preservation.nixosModules.default
        inputs.sops-nix.nixosModules.sops
        ./../files/core/configuration.nix
        ./../files/core/disko.nix
        ./../files/core/preservation.nix
        ./../files/core/hardware-configuration.nix
        ./../files/hardware/default.nix
        ./../files/profiles/default.nix
        ./../files/modules/security/default.nix
        ./../files/modules/security/snort.nix
        ./../files/modules/security/snout.nix
        ./../files/modules/optional/nixos
        ./../files/modules/module-manager/default.nix
        inputs.home-manager.nixosModules.home-manager
        (mkHomeManagerConfig inputs)
      ];
    };
  };
}
