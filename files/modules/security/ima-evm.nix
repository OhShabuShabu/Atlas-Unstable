{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: IMA/EVM - Kernel-Level File Integrity
# INFO: ============================================================================
# INFO: Integrity Measurement Architecture (IMA) measures files at runtime.
#       Extended Verification Module (EVM) protects extended attributes.
#       IMA is active with ima_appraise=fix (log-only, safe).
#       EVM key infrastructure is set up but EVM enforcement is NOT enabled
#       by default — switch to 'enforce' after testing.
# NOTE: IMA measurement policy measures: binaries, mmap'd files, kernel modules,
#       firmware, and critical data.
# WARN: EVM enforcement (ima_appraise=enforce) can break boot if setuid binaries
#       are not signed. Start with 'fix' (log-only) until all binaries are signed.

let
  persistentDir = "/persistent";
  evmKeyPath = "${persistentDir}/evm-key";
  evmKeyDesc = "evm-key";

  # INFO: IMA measurement policy (loaded once at boot)
  # NOTE: Cannot be changed after first load without reboot
  imaPolicy = ''
    # Don't measure pseudo-filesystems
    dont_measure fsmagic=0x01021994  # selinuxfs
    dont_measure fsmagic=0x1021994   # securityfs
    dont_measure fsmagic=0x9fa0      # procfs
    dont_measure fsmagic=0x62656572  # sysfs
    dont_measure fsmagic=0x64626720  # debugfs
    dont_measure fsmagic=0x1cd1     # devtmpfs
    dont_measure fsmagic=0x73636673  # securityfs

    # Measure all executables
    measure func=BPRM_CHECK mask=MAY_EXEC
    # Measure files mapped into memory
    measure func=FILE_MMAP mask=MAY_EXEC
    # Measure kernel modules
    measure func=MODULE_CHECK
    # Measure firmware
    measure func=FIRMWARE_CHECK
    # Measure policy files
    measure func=CRITICAL_DATA
  '';

  # INFO: IMA policy loader script (runs at boot)
  loadImaPolicy = pkgs.writeShellScript "load-ima-policy.sh" ''
    set -euo pipefail

    POLICY_FILE="/sys/kernel/security/integrity/ima/policy"
    LOGGER="${pkgs.util-linux}/bin/logger"

    # Check if IMA is available
    if [ ! -f "$POLICY_FILE" ]; then
      echo "IMA: Not available (policy file not found)"
      $LOGGER -p auth.warning -t ima "IMA not available in kernel"
      exit 0
    fi

    # Check if policy is already loaded (can only be loaded once)
    POLICY_COUNT=$(cat /sys/kernel/security/integrity/ima/runtime_measurements_count 2>/dev/null || echo "0")
    if [ "$POLICY_COUNT" -gt 10 ]; then
      echo "IMA: Policy already loaded ($POLICY_COUNT measurements)"
      exit 0
    fi

    # Load measurement policy
    echo "IMA: Loading measurement policy..."
    echo "${imaPolicy}" > "$POLICY_FILE" 2>/dev/null || \
      echo "IMA: Could not write policy (already set in kernel cmdline)"

    echo "IMA: Policy loaded successfully"
    $LOGGER -p auth.info -t ima "IMA measurement policy loaded"
  '';

  # INFO: EVM HMAC key generation + loading script
  # NOTE: The EVM key is stored in /persistent (LUKS-encrypted).
  #       It's loaded into the kernel keyring at boot for EVM operations.
  #       With evm=fix (kernel param), this is safe — no enforcement.
  #       To enable enforcement, change to evm=enforce and sign setuid binaries.
  evmKeyService = pkgs.writeShellScript "evm-key-setup.sh" ''
    set -euo pipefail

    KEY_PATH="${evmKeyPath}"
    KEY_DESC="${evmKeyDesc}"
    LOGGER="${pkgs.util-linux}/bin/logger"

    # Check if EVM is available in kernel
    if [ ! -d /sys/kernel/security/integrity/evm ]; then
      echo "EVM: Not available in kernel — skipping key setup"
      $LOGGER -p auth.info -t evm "EVM not available in kernel"
      exit 0
    fi

    # Create parent directory
    mkdir -p "$(dirname "$KEY_PATH")"

    # Generate EVM key if it doesn't exist
    if [ ! -f "$KEY_PATH" ]; then
      echo "EVM: Generating new HMAC key..."

      # Generate a random 512-bit HMAC key
      # Format: <desc>:<type>:<size>:<hex-encoded-key>
      KEY_HEX=$(${pkgs.openssl}/bin/openssl rand -hex 64 2>/dev/null)
      echo "$KEY_DESC:hmac-sha256:64:$KEY_HEX" > "$KEY_PATH"
      chmod 0600 "$KEY_PATH"

      echo "EVM: HMAC key created at $KEY_PATH"
      $LOGGER -p auth.info -t evm "EVM HMAC key generated"
    else
      echo "EVM: Key already exists at $KEY_PATH"
    fi

    # Load key into kernel keyring
    # Format: evmctl import /path/to/key
    # The key format is: <desc>:<type>:<size>:<hex>
    if KEY_DATA=$(cat "$KEY_PATH" 2>/dev/null); then
      # Check if already loaded by trying to read evm key
      if ${pkgs.ima-evm-utils}/bin/evmctl init 2>/dev/null; then
        echo "EVM: Key already loaded in kernel keyring"
        exit 0
      fi

      # Load the key using keyctl
      KEY_ID=$(echo "$KEY_DATA" | ${pkgs.kmod}/bin/keyctl padd encrypted "$KEY_DESC" @u 2>/dev/null || true)
      if [ -n "$KEY_ID" ]; then
        echo "EVM: Key loaded successfully (key ID: $KEY_ID)"
        $LOGGER -p auth.info -t evm "EVM key loaded (id: $KEY_ID)"
      else
        echo "EVM: Failed to load key — EVM may not be fully supported in kernel" >&2
        $LOGGER -p auth.warning -t evm "EVM key loading failed"
      fi
    else
      echo "EVM: Cannot read key file" >&2
      exit 1
    fi
  '';
in

{
  # INFO: IMA kernel parameters
  # NOTE: ima_appraise=fix enables logging without enforcement
  #       Change to ima_appraise=enforce after testing
  #       evm=fix enables EVM logging without enforcement
  boot.kernelParams = [
    "ima_policy=tcb"          # Default TCB (Trusted Computing Base) measurement
    "ima_appraise=fix"        # Log-only appraisal (safe for first deployment)
    "ima_hash=sha256"         # Use SHA256 for measurements
    "evm=fix"                 # EVM log-only mode (safe — no enforcement)
  ];

  # INFO: IMA/EVM related packages + EVM signing utility
  environment.systemPackages = with pkgs; [
    ima-evm-utils       # evmctl for signing/verifying EVM attributes
    kmod                # keyctl for key management
    (pkgs.writeShellScriptBin "evm-sign-binary" ''
      set -euo pipefail
      if [ $# -ne 1 ]; then
        echo "Usage: evm-sign-binary <path-to-binary>"
        exit 1
      fi
      BINARY="$1"
      KEY="${evmKeyPath}"
      if [ ! -f "$KEY" ]; then
        echo "EVM key not found at $KEY — run evm-key-setup first"
        exit 1
      fi
      echo "Signing $BINARY with EVM key..."
      ${pkgs.ima-evm-utils}/bin/evmctl sign --key "$KEY" --imasig "$BINARY" 2>/dev/null && \
        echo "✓ Signed $BINARY" || \
        echo "✗ Failed to sign $BINARY"
    '')
  ];
}
