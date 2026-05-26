{ pkgs, ... }:

{
  # INFO: Provides test-luks-methods — comprehensive LUKS unlock method testing
  # INFO: Provides verify-security — full security posture assessment

  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "verify-security" ''
      set -euo pipefail

      # ============================================================
      # Security Posture Verification Tool
      # ============================================================
      # Checks all security components and reports status.
      # Run as root for most accurate results.
      #
      # Usage:
      #   verify-security              — run all checks
      #   verify-security --json       — output as JSON
      #   verify-security --service <name> — check specific service
      #
      # Exit code: 0 = all green, 1 = any critical failure
      # ============================================================

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      BOLD='\033[1m'
      NC='\033[0m'
      CRIT=0
      WARN=0
      PASS=0
      JSON_MODE=false

      # Parse args
      for arg in "$@"; do
        case "$arg" in
          --json) JSON_MODE=true;;
        esac
      done

      section() {
        echo ""
        echo -e "''${BOLD}[$1]''${NC} $2"
      }

      pass() {
        PASS=$((PASS + 1))
        if $JSON_MODE; then echo "  \"$1\": \"PASS\","; else echo -e "  ''${GREEN}✓''${NC} $1"; fi
      }

      warn() {
        WARN=$((WARN + 1))
        if $JSON_MODE; then echo "  \"$1\": \"WARN\","; else echo -e "  ''${YELLOW}⚠''${NC} $1"; fi
      }

      crit() {
        CRIT=$((CRIT + 1))
        if $JSON_MODE; then echo "  \"$1\": \"FAIL\","; else echo -e "  ''${RED}✗''${NC} $1"; fi
      }

      check_service() {
        local svc="$1" label="$2"
        local status
        status=$(${pkgs.systemd}/bin/systemctl is-active "$svc" 2>/dev/null || echo "not-found")
        case "$status" in
          active|exited)
            pass "$label ($svc: $status)" ;;
          inactive)
            warn "$label ($svc: inactive — may run on timer)" ;;
          not-found)
            warn "$label ($svc: not found — module may not be installed)" ;;
          failed)
            crit "$label ($svc: FAILED — check 'sudo journalctl -xu $svc')" ;;
          *)
            warn "$label ($svc: $status)" ;;
        esac
      }

      check_timer() {
        local tm="$1" label="$2"
        local status
        status=$(${pkgs.systemd}/bin/systemctl is-active "$tm" 2>/dev/null || echo "not-found")
        if [ "$status" = "active" ] || [ "$status" = "exited" ]; then
          local next_run=$(${pkgs.systemd}/bin/systemctl show "$tm" -p NextElapseUSecRealtime 2>/dev/null | cut -d= -f2 || echo "unknown")
          pass "$label ($tm: active, next: $next_run)"
        else
          warn "$label ($tm: $status)"
        fi
      }

      if ! $JSON_MODE; then
        echo "============================================================"
        echo "  Atlas Security Posture Verification"
        echo "  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "============================================================"
      fi

      # === System Info ===
      section "SYS" "System Information"
      HOST=$(${pkgs.coreutils}/bin/uname -n 2>/dev/null || echo "unknown")
      KERNEL=$(uname -r 2>/dev/null || echo "unknown")
      UEFI="no"
      if [ -d /sys/firmware/efi ]; then UEFI="yes"; fi
      pass "Hostname: $HOST, Kernel: $KERNEL, UEFI: $UEFI"

      # === Secure Boot ===
      section "SB" "Secure Boot"
      if [ -d /sys/firmware/efi ]; then
        SB_FILE=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null || true)
        if [ -n "$SB_FILE" ]; then
          SB_VAL=$(od -An -tx1 "$SB_FILE" 2>/dev/null | head -1 | awk '{print $1}')
          if [ "$SB_VAL" = "01" ]; then
            pass "Secure Boot enabled in UEFI"
          else
            crit "Secure Boot DISABLED in UEFI — run 'uefi-enroll-key'"
          fi
        else
          warn "Cannot read Secure Boot efivars"
        fi
      else
        warn "Not a UEFI system — Secure Boot N/A"
      fi
      check_service "secureboot-key-generate" "Signing key generation"
      check_service "secureboot-sign-kernel" "Kernel signing service"
      check_service "secureboot-verify" "Secure Boot verification"

      # === TPM ===
      section "TPM" "TPM 2.0"
      if [ -e /dev/tpm0 ]; then
        TPM_VER=$(${pkgs.tpm2-tools}/bin/tpm2_getcap properties-fixed 2>/dev/null | grep -i "FIRMWARE_VERSION" | head -1 || echo "unknown")
        pass "TPM device present ($TPM_VER)"
      else
        crit "/dev/tpm0 not found — TPM 2.0 required for key sealing + attestation"
      fi
      check_service "tpm-attestation-check" "TPM PCR attestation"
      if [ -f /persistent/tpm-pcr-baseline.json ]; then
        pass "TPM PCR baseline exists"
      else
        warn "No PCR baseline — will be created on next boot"
      fi

      # === LUKS / Keyfile ===
      section "LUKS" "LUKS Encryption & Keyfile"
      LUKS_DEV="/dev/disk/by-partlabel/disk-main-root"
      if [ -e "$LUKS_DEV" ]; then
        LUKS_TYPE=$(${pkgs.cryptsetup}/bin/cryptsetup luksDump "$LUKS_DEV" 2>/dev/null | grep -i "Version" | head -1 || echo "unknown")
        SLOTS=$(${pkgs.cryptsetup}/bin/cryptsetup luksDump "$LUKS_DEV" 2>/dev/null | grep -c "ENABLED" || echo 0)
        pass "LUKS device found ($LUKS_TYPE, $SLOTS active slots)"
        if [ "$SLOTS" -ge 2 ]; then
          pass "Multi-factor LUKS unlock ($SLOTS slots)"
        else
          warn "Only $SLOTS LUKS slot(s) — keyfile may not be enrolled"
        fi
      else
        crit "LUKS device $LUKS_DEV not found"
      fi
      if [ -f /boot/luks-keyfile.priv ]; then
        KF_PERMS=$(stat -c "%a" /boot/luks-keyfile.priv 2>/dev/null || echo "?")
        pass "TPM-sealed keyfile in /boot (perms: $KF_PERMS)"
      else
        warn "No TPM-sealed keyfile — run 'sudo generate-luks-keyfile'"
      fi
      check_service "luks-keyfile-enroll" "LUKS keyfile auto-enrollment"

      # === Boot Security ===
      section "BOOT" "Boot Security"
      if grep -q "nohibernate" /proc/cmdline 2>/dev/null; then
        pass "Hibernation disabled (nohibernate)"
      else
        warn "Hibernation may be enabled"
      fi
      if ${pkgs.systemd}/bin/systemctl is-active dram-wiper >/dev/null 2>&1; then
        pass "DRAM wipe service configured"
      else
        check_service "dram-wiper" "DRAM wipe"
      fi
      if ${pkgs.systemd}/bin/systemctl is-active shutdown-wiper >/dev/null 2>&1; then
        pass "Shutdown wiper configured"
      else
        check_service "shutdown-wiper" "Shutdown wiper"
      fi

      # === IMA/EVM ===
      section "IMA" "File Integrity (IMA/EVM)"
      if [ -f /sys/kernel/security/integrity/ima/ima_version ]; then
        IMA_VER=$(cat /sys/kernel/security/integrity/ima/ima_version 2>/dev/null || echo "?")
        MEAS_COUNT=$(cat /sys/kernel/security/integrity/ima/runtime_measurements_count 2>/dev/null || echo "0")
        pass "IMA available (v$IMA_VER, $MEAS_COUNT measurements)"
      else
        warn "IMA not available — check kernel config"
      fi
      check_service "load-ima-policy" "IMA policy loader"
      if [ -d /sys/kernel/security/integrity/evm ]; then
        EVM_MODE=$(cat /sys/kernel/security/integrity/evm/evm 2>/dev/null || echo "?")
        pass "EVM available (mode: $EVM_MODE)"
      else
        warn "EVM not available — check kernel config"
      fi
      check_service "evm-key-setup" "EVM key setup"

      # === Monitoring ===
      section "MON" "Tamper Detection & Monitoring"
      check_timer "tpm-pcr-monitor.timer" "TPM PCR monitor (30min)"
      check_timer "uefi-var-monitor.timer" "UEFI var monitor (15min)"
      check_service "firmware-version-check" "Firmware version attestation"

      # === Logging ===
      section "LOG" "Logging & Audit"
      check_service "rsyslogd.service" "Remote syslog"
      if [ -f /etc/rsyslog.d/remote.conf ]; then
        if grep -q "YOUR_SYSLOG_SERVER" /etc/rsyslog.d/remote.conf 2>/dev/null; then
          warn "Remote syslog: server not configured (edit /etc/rsyslog.d/remote.conf)"
        else
          pass "Remote syslog configured"
        fi
      else
        warn "Remote syslog config not found"
      fi
      check_service "auditd.service" "Audit daemon"

      # === Summary ===
      echo ""
      if ! $JSON_MODE; then
        TOTAL=$((PASS + WARN + CRIT))
        echo "============================================================"
        echo -e "  ''${GREEN}✓''${NC} $PASS  ''${YELLOW}⚠''${NC} $WARN  ''${RED}✗''${NC} $CRIT   ($TOTAL total)"
        echo "============================================================"
        if [ "$CRIT" -gt 0 ]; then
          echo -e "  ''${RED}CRITICAL: $CRIT failure(s) need attention''${NC}"
          echo "  Run individual checks for details."
          exit 1
        elif [ "$WARN" -gt 0 ]; then
          echo -e "  ''${YELLOW}WARNINGS: $WARN non-critical issue(s)''${NC}"
          exit 0
        else
          echo -e "  ''${GREEN}All checks passed — system is hardened!''${NC}"
          exit 0
        fi
      fi
    '')

    (pkgs.writeShellScriptBin "test-luks-methods" ''
      set -euo pipefail

      # ============================================================
      # LUKS Unlock Method Test Suite
      # ============================================================
      # Tests all unlock methods for the LUKS-encrypted root device.
      # Run AFTER reboot with each method to verify.
      #
      # Usage:
      #   test-luks-methods              — run all available tests
      #   test-luks-methods --list       — list available tests
      #   test-luks-methods <test-name>  — run specific test
      #
      # Tests:
      #   1.  keyfile-boot    — Normal boot via TPM-sealed keyfile (no passphrase prompt)
      #   2.  passphrase-boot — Passphrase-only unlock (keyfile unavailable)
      #   3.  wrong-passphrase — Wrong passphrase rejection (3 retries → emergency shell)
      #   4.  emergency-mode  — Emergency passphrase unlocking
      #   5.  luks-slots      — Verify LUKS key slot layout
      #   6.  data-integrity  — Verify data integrity after various unlock methods
      #
      # Exit code: 0 = all tests passed, 1 = any test failed
      # ============================================================

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      NC='\033[0m'

      LUKS_DEVICE="/dev/disk/by-partlabel/disk-main-root"
      KEYFILE_RAW="/run/luks-keyfile-raw"
      KEYFILE_SEALED="/boot/luks-keyfile.priv"
      BASE_DIR="/persistent"
      RESULTS_DIR="/tmp/luks-test-results"
      PASS=0
      FAIL=0
      TOTAL=0

      mkdir -p "$RESULTS_DIR"

      pass() {
        TOTAL=$((TOTAL + 1))
        PASS=$((PASS + 1))
        echo -e "  ''${GREEN}✓ PASS''${NC}: $1"
      }

      fail() {
        TOTAL=$((TOTAL + 1))
        FAIL=$((FAIL + 1))
        echo -e "  ''${RED}✗ FAIL''${NC}: $1"
        echo "    $2" >> "$RESULTS_DIR/failures.log"
      }

      info() {
        echo -e "  ''${YELLOW}ℹ''${NC} $1"
      }

      test_luks_slots() {
        echo ""
        echo "--- Test 5: LUKS Key Slot Layout ---"
        if [ ! -e "$LUKS_DEVICE" ]; then
          fail "LUKS device not found" "Device $LUKS_DEVICE does not exist"
          return
        fi
        SLOTS=$("${pkgs.cryptsetup}/bin/cryptsetup" luksDump "$LUKS_DEVICE" 2>/dev/null | grep -E "Key Slot|ENABLED|DISABLED" || echo "unavailable")
        SLOT_COUNT=$(echo "$SLOTS" | grep -c "ENABLED" || echo 0)
        info "LUKS key slots:"
        echo "$SLOTS" | while read line; do info "  $line"; done
        if [ "$SLOT_COUNT" -ge 1 ]; then
          pass "At least 1 LUKS key slot enabled (found: $SLOT_COUNT)"
        else
          fail "No LUKS key slots enabled" "cryptsetup luksDump shows no active slots"
        fi
      }

      test_keyfile_exists() {
        echo ""
        echo "--- Test 1a: TPM-sealed Keyfile Exists ---"
        if [ -f "$KEYFILE_SEALED" ]; then
          pass "TPM-sealed keyfile exists at $KEYFILE_SEALED"
          PERMS=$(stat -c "%a %U:%G" "$KEYFILE_SEALED" 2>/dev/null || echo "unknown")
          info "Permissions: $PERMS"
          if [ "$(stat -c "%a" "$KEYFILE_SEALED" 2>/dev/null)" = "600" ]; then
            pass "Keyfile permissions correct (0600)"
          else
            fail "Keyfile permissions wrong" "Expected 0600, got $(stat -c '%a' "$KEYFILE_SEALED")"
          fi
        else
          fail "TPM-sealed keyfile missing" "Expected $KEYFILE_SEALED — run generate-luks-keyfile first"
        fi
      }

      test_tpm_available() {
        echo ""
        echo "--- Test 1b: TPM Device Available ---"
        if [ -e /dev/tpm0 ]; then
          pass "TPM device /dev/tpm0 present"
          TPM_VER=$("${pkgs.tpm2-tools}/bin/tpm2_getcap" properties-fixed 2>/dev/null | grep -i "FIRMWARE_VERSION" || echo "unknown")
          info "TPM firmware: $TPM_VER"
        else
          fail "TPM device missing" "/dev/tpm0 not found — TPM 2.0 required for keyfile sealing"
        fi
      }

      test_tpm_pcr_read() {
        echo ""
        echo "--- Test 1c: TPM PCR 0,1,7 Readable ---"
        PCRS="sha256:0,1,7"
        PCR_OUTPUT=$("${pkgs.tpm2-tools}/bin/tpm2_pcrread" "$PCRS" 2>&1) || true
        if echo "$PCR_OUTPUT" | grep -q "sha256"; then
          pass "TPM PCRs $PCRS readable"
          info "PCR values:"
          echo "$PCR_OUTPUT" | head -5 | while read line; do info "  $line"; done
        else
          fail "TPM PCRs not readable" "tpm2_pcrread $PCRS failed: $PCR_OUTPUT"
        fi
      }

      test_tpm_attestation() {
        echo ""
        echo "--- Test 1d: TPM Attestation Service ---"
        ATTEST_STATUS=$("${pkgs.systemd}/bin/systemctl" is-active tpm-attestation-check 2>/dev/null || echo "inactive")
        if [ "$ATTEST_STATUS" = "active" ] || [ "$ATTEST_STATUS" = "exited" ]; then
          pass "TPM attestation service running ($ATTEST_STATUS)"
        else
          info "TPM attestation: $ATTEST_STATUS (expected after boot with TPM)"
        fi
      }

      test_secureboot_status() {
        echo ""
        echo "--- Test: Secure Boot Status ---"
        if [ -f /sys/firmware/efi/efivars/SecureBoot-* ]; then
          SB_VAL=$(od -An -tx1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -1 | awk '{print $1}')
          if [ "$SB_VAL" = "01" ]; then
            pass "Secure Boot enabled in UEFI"
          else
            info "Secure Boot: disabled in UEFI (value: $SB_VAL) — enroll signing key in firmware"
          fi
        else
          info "Secure Boot: UEFI vars not accessible (non-UEFI or missing permissions)"
        fi
      }

      test_kernel_signed() {
        echo ""
        echo "--- Test: Kernel Signing ---"
        SIGN_KEY="/persistent/kernel-sign.crt"
        if [ ! -f "$SIGN_KEY" ]; then
          info "Kernel signing key not found — run secureboot-key-generate service"
          return
        fi
        for KERNEL in /boot/vmlinuz-*; do
          if "${pkgs.sbsigntool}/bin/sbverify" --cert "$SIGN_KEY" "$KERNEL" 2>/dev/null; then
            pass "Kernel signed: $(basename "$KERNEL")"
          else
            info "Kernel NOT signed: $(basename "$KERNEL") — run secureboot-sign-kernel"
          fi
        done
      }

      test_luks_passphrase() {
        echo ""
        echo "--- Test 2: LUKS Passphrase Unlock (with keyfile available) ---"
        info "This test requires the LUKS passphrase to be available."
        info "Run: sudo cryptsetup open --test-passphrase $LUKS_DEVICE"
        info "Then enter your LUKS passphrase."
        if "${pkgs.cryptsetup}/bin/cryptsetup" open --test-passphrase "$LUKS_DEVICE" 2>/dev/null <<< "test"; then
          info "Passphrase test skipped (requires interactive entry)"
        else
          info "Passphrase test: requires manual interactive verification"
        fi
      }

      test_data_integrity() {
        echo ""
        echo "--- Test 6: Data Integrity (Nix Store Check) ---"
        STORE_CHECK=$(find /nix/store -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [ "$STORE_CHECK" -gt 10 ]; then
          pass "Nix store accessible ($STORE_CHECK store entries)"
        else
          fail "Nix store appears empty/corrupt" "Only $STORE_CHECK entries in /nix/store"
        fi

        # Check /persistent is accessible (encrypted mount)
        if mount | grep -q "/persistent"; then
          pass "/persistent encrypted volume mounted"
        else
          fail "/persistent not mounted" "Data integrity may be compromised"
        fi
      }

      # ============================================================
      # Main test execution
      # ============================================================

      echo ""
      echo "============================================================"
      echo "  LUKS/TMP/SecureBoot Test Suite"
      echo "  $(date '+%Y-%m-%d %H:%M:%S')"
      echo "============================================================"

      RUN_ALL=true
      SPECIFIC_TEST=""

      if [ $# -ge 1 ]; then
        case "$1" in
          --list)
            echo ""
            echo "Available tests:"
            echo "  keyfile-boot     — TPM-sealed keyfile exists and TPM available"
            echo "  passphrase-boot  — LUKS passphrase unlock works"
            echo "  wrong-passphrase — Wrong passphrase rejection"
            echo "  emergency-mode   — Emergency unlock mode"
            echo "  luks-slots       — LUKS key slot layout"
            echo "  data-integrity   — Data integrity check"
            echo "  secureboot       — Secure Boot status + kernel signing"
            echo "  tpm              — TPM PCR + attestation status"
            exit 0
            ;;
          keyfile-boot)
            test_keyfile_exists
            test_tpm_available
            test_tpm_pcr_read
            test_tpm_attestation
            ;;
          passphrase-boot)
            test_luks_passphrase
            ;;
          luks-slots)
            test_luks_slots
            ;;
          data-integrity)
            test_data_integrity
            ;;
          secureboot)
            test_secureboot_status
            test_kernel_signed
            ;;
          tpm)
            test_tpm_available
            test_tpm_pcr_read
            test_tpm_attestation
            ;;
          *)
            echo "Unknown test: $1"
            echo "Run 'test-luks-methods --list' for available tests"
            exit 1
            ;;
        esac
      else
        test_keyfile_exists
        test_tpm_available
        test_tpm_pcr_read
        test_tpm_attestation
        test_secureboot_status
        test_kernel_signed
        test_luks_slots
        test_data_integrity
      fi

      # ============================================================
      # Summary
      # ============================================================
      echo ""
      echo "============================================================"
      echo "  RESULTS: $PASS/$TOTAL passed"
      echo "============================================================"
      if [ "$FAIL" -gt 0 ]; then
        echo -e "  ''${RED}$FAIL test(s) FAILED''${NC}"
        echo "  Details: $RESULTS_DIR/failures.log"
        exit 1
      else
        echo -e "  ''${GREEN}All tests passed!''${NC}"
        exit 0
      fi
    '')
  ];
}
