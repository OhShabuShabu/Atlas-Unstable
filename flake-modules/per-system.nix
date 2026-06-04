{ pkgs, ... }: {
  perSystem = { pkgs, ... }: {
    formatter = pkgs.nixpkgs-fmt;

    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        nixpkgs-fmt
        statix
        deadnix
        nix-doc
      ];
    };

    checks = { };
  };
}
