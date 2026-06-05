{ pkgs, ... }: {
  perSystem = { pkgs, ... }: {
    formatter = pkgs.nixfmt-rfc-style;

    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        nixfmt-rfc-style
        statix
        deadnix
        nix-doc
      ];
    };

    checks = {
      lint = pkgs.runCommand "yorha-lint" {
        buildInputs = with pkgs; [ statix deadnix ];
      } ''
        statix check ${../.} 2>&1 | tee $out || true
        deadnix --no-lambda-pattern-names ${../.} 2>&1 | tee -a $out || true
        # Always succeed even if lints fail (warnings only)
        touch $out
      '';
    };
  };
}
