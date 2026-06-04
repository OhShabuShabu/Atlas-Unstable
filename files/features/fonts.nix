{ ... }: {
  flake.modules.nixos.fonts = { pkgs, lib, ... }: {
    fonts.packages = with pkgs; [
      udev-gothic-nf
      noto-fonts

      (pkgs.stdenv.mkDerivation {
        pname = "monocraft";
        version = "4.2.1";
        src = pkgs.fetchurl {
          url = "https://github.com/IdreesInc/Monocraft/releases/download/v4.2.1/Monocraft-otf.zip";
          hash = "sha256-5iO3LxAhBirQFWzEH1SxCOcL014rKVEnR1u1ctit5h0=";
        };
        nativeBuildInputs = [ pkgs.unzip ];
        installPhase = ''
          mkdir -p $out/share/fonts/otf
          unzip -j $src -d $out/share/fonts/otf "*.otf"
        '';
      })
    ];
  };
}
