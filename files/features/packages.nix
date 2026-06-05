{ inputs, ... }: {
  flake.modules.nixos.packages = { pkgs, lib, config, ... }: {
    environment.systemPackages = with pkgs; [
      niri
      inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
      python3
      curl
      ffmpeg

      nerd-fonts.symbols-only
      roboto
      material-design-icons

      oreo-cursors-plus

      wtype
      wlrctl
      gocryptfs
      inotify-tools
      tpm2-tools

      (pkgs.writeShellScriptBin "encrypted-storage" ''
        export YORHA_LIB_DIR="${./../lib}"
        exec ${./../bin/encrypted-storage.sh} "$@"
      '')

      (pkgs.writeShellScriptBin "yorha-hardware-detect" ''
        export YORHA_LIB_DIR="${./../lib}"
        exec ${./../bin/shell/detect-hardware.sh} "$@"
      '')

      pavucontrol
      # NOTE: pulseaudio intentionally omitted — PipeWire is the system audio service

      jq
      polkit_gnome
      libpwquality
      nftables
      acct
      sysstat
      nautilus
      yazi
      exiftool

      ollama-rocm

      alacritty

      kdePackages.kde-cli-tools
      kdePackages.kdialog

      (pkgs.stdenv.mkDerivation {
        pname = "sddm-nier-automata-theme";
        version = "6946b53";
        src = pkgs.fetchFromGitHub {
          owner = "Darkkal44";
          repo = "qylock";
          rev = "6946b53626b4f3c1507ae9a78c287411df5fb36c";
          sha256 = "0kdy4w7az0ygmv3yf92xsyrflak52lm3prp8lickwk207y3qgm7g";
        };
        installPhase = ''
          mkdir -p $out/share/sddm/themes/nier-automata
          cp -r $src/themes/nier-automata/* $out/share/sddm/themes/nier-automata/
        '';
      })
      qt6.qtdeclarative
      qt6.qt5compat
      qt6.qtsvg
      qt6.qtmultimedia
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good

      trashy

      docker-compose

      (pkgs.writeShellScriptBin "odysseus-build" ''
        set -euo pipefail
        echo "=== Odysseus image rebuild via docker exec+tar+import ==="
        echo "This rebuilds the image from a running container."
        echo ""
        echo "  docker exec odysseus-build tar cf - / > /tmp/odysseus-fs.tar"
        echo "  docker import --change 'ENTRYPOINT ...' /tmp/odysseus-fs.tar odysseus-odysseus:latest"
        echo ""
        echo "See configuration.nix for full import command."
      '')
      (pkgs.writeShellScriptBin "odysseus-down" ''
        sudo systemctl stop odysseus
      '')
      (pkgs.writeShellScriptBin "odysseus-logs" ''
        journalctl -fu odysseus
      '')

      (pkgs.writeShellScriptBin "yorha-rebuild" ''
        set -euo pipefail

        STOPPED_SERVICES=(
          snort-daemon snort-monitor
          snout-watcher.service snout-watcher.path
          aide-check.service aide-check.timer
          firmware-version-check
          tpm-attestation-check
          secureboot-verify
          mullvad-daemon
        )

        for svc in "''${STOPPED_SERVICES[@]}"; do
          sudo systemctl stop "$svc" 2>/dev/null || true
        done

        FLAKE="''${FLAKE:-.#yorha}"

        echo "=== Detection services stopped, running nixos-rebuild ==="
        BUILD_FAILED=0
        if sudo nixos-rebuild switch --flake "$FLAKE" "$@"; then
          echo "=== Build succeeded — restarting stopped services ==="
        else
          BUILD_FAILED=1
          echo "=== Build FAILED — restarting security services to restore protection ==="
        fi
        for svc in "''${STOPPED_SERVICES[@]}"; do
          sudo systemctl restart "$svc" 2>/dev/null || true
        done
        if [ "$BUILD_FAILED" -eq 0 ]; then
          echo "=== Running health check ==="
          yorha-health quick 2>/dev/null || echo "⚠  Health check found issues — run 'yorha-health' for details."
        else
          echo "=== Build failed. Security services have been restarted. ==="
          exit 1
        fi
      '')

      (pkgs.writeShellScriptBin "yorha-health" ''
        set -euo pipefail

        RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

        ok()   { echo -e "  ''${GREEN}✓''${NC} $1"; }
        warn() { echo -e "  ''${YELLOW}⚠''${NC} $1"; }
        fail() { echo -e "  ''${RED}✗''${NC} $1"; }

        MODE="''${1:-full}"

        if [[ "$MODE" == "quick" ]]; then
          echo -e "''${BOLD}YoRHa Quick Health''${NC}"
        else
          echo -e "''${BOLD}══════════════════════════════════════════''${NC}"
          echo -e "''${BOLD}  YoRHa System Health''${NC}"
          echo -e "''${BOLD}══════════════════════════════════════════''${NC}"
        fi

        if [[ "$MODE" != "quick" ]]; then
          echo -e "\n''${BOLD}System:''${NC}"
          uname -r 2>/dev/null | xargs -I{} echo "  Kernel: {}"
          uptime -p 2>/dev/null | sed 's/^/  Uptime: /'
          free -h 2>/dev/null | awk '/^Mem:/ {printf "  Memory: %s used / %s total\n", $3, $2}'
          df -h /nix 2>/dev/null | awk 'NR==2 {printf "  Nix store: %s used / %s total\n", $3, $2}'
          echo ""
        fi

        echo -e "''${BOLD}Security:''${NC}"
        for svc in snort-daemon snout-watcher.service clamav-daemon aide-check.timer; do
          if sudo systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc"
          else
            fail "$svc (inactive)"
          fi
        done

        echo -e "\n''${BOLD}Desktop:''${NC}"
        for svc in awww vicinae xwayland-satellite; do
          if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc"
          else
            warn "$svc (not running — may be normal if not logged into a desktop)"
          fi
        done

        if [[ "$MODE" != "quick" ]]; then
          echo -e "\n''${BOLD}Disk:''${NC}"
          df -h / /nix /persistent /boot 2>/dev/null | awk 'NR==1; NR>1 {printf "  %s  %s used / %s (%s)\n", $1, $3, $2, $5}'

          echo -e "\n''${BOLD}LUKS:''${NC}"
          if sudo cryptsetup status crypt 2>/dev/null | grep -q "active"; then
            ok "LUKS container 'crypt' is active"
          else
            fail "LUKS container not active (check encryption)"
          fi
        fi

        echo -e "\n''${BOLD}Last Scans:''${NC}"
        if sudo test -f /var/log/clamav/scan.log 2>/dev/null; then
          sudo tail -3 /var/log/clamav/scan.log 2>/dev/null | head -1 | sed 's/^/  ClamAV: /' || true
        fi
        if sudo journalctl -u aide-check.service --no-pager -n 1 2>/dev/null | grep -q "OK\|completed"; then
          ok "AIDE last check passed"
        else
          warn "AIDE: no recent check logged"
        fi

        echo ""
      '')
    ];
  };
}
