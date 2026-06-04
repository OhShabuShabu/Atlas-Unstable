{ ... }: {
  flake.modules.nixos.boot = { pkgs, lib, config, ... }: {
    boot = {
      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;

      initrd.systemd.enable = true;
      initrd.compressor = "zstd";
      initrd.compressorArgs = [ "-12" ];

      loader.systemd-boot.configurationLimit = 3;

      initrd.availableKernelModules =
        let tpmPresent = builtins.tryEval (builtins.pathExists "/sys/class/tpm/tpm0");
        in lib.mkIf (tpmPresent.success && tpmPresent.value) [ "tpm_tis" "tpm_crb" "tpm" ];

      initrd.kernelModules = [ "overlay" "xt_addrtype" ];

      kernelModules =
        let tpmPresent = builtins.tryEval (builtins.pathExists "/sys/class/tpm/tpm0");
        in [ "xt_addrtype" "i2c-dev" ]
           ++ lib.optionals (tpmPresent.success && tpmPresent.value) [ "tpm_tis" "tpm_crb" "tpm" ]
           ++ [
             "nft_ct" "nft_fib" "nft_fib_inet" "nft_nat" "nft_reject" "nft_reject_inet"
             "nft_chain_nat" "nft_connlimit" "nft_dup_ipv4" "nft_dup_ipv6"
             "nft_dup_netdev" "nft_fib_ipv4" "nft_fib_ipv6" "nft_flow_offload"
             "nft_fwd_netdev" "nft_hash" "nft_limit" "nft_log" "nft_masq"
             "nft_meta_bridge" "nft_numgen" "nft_osf" "nft_queue" "nft_quota"
             "nft_redir" "nft_reject_bridge" "nft_reject_ipv4" "nft_reject_ipv6"
             "nft_reject_netdev" "nft_socket" "nft_synproxy" "nft_tproxy"
             "nft_tunnel" "nft_xfrm"
             "xt_addrtype"
           ];

      plymouth = {
        enable = true;
        theme = "hyprland-mac-style";
        themePackages = with pkgs; [
          (pkgs.runCommandLocal "plymouth-hyprland-mac-style" {
            src = ./../config/plymouth/hyprland-mac-style;
          } ''
            mkdir -p $out/share/plymouth/themes
            cp -r "$src" $out/share/plymouth/themes/hyprland-mac-style
            substituteInPlace $out/share/plymouth/themes/hyprland-mac-style/hyprland-mac-style.plymouth \
              --replace-fail "/usr/share" "$out/share"
          '')
        ];
      };
    };

    hardware.enableRedistributableFirmware = true;

    boot.tmp.cleanOnBoot = true;
  };
}
