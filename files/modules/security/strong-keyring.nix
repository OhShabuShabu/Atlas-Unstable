{ lib, pkgs, ... }:

# INFO: ============================================================================
# INFO: STRONG KEYRING MODULE - Hardware Security Token Support
# INFO: ============================================================================
# INFO: Strong Keyring provides hardware security token support for strongSwan VPN
#       Includes PKCS#11 support for smartcards, USB tokens, and TPM devices
# INFO: ============================================================================

let
  cfg = {
    enable = false;  # Set to true if using hardware security tokens / IPsec VPN
    enablePKCS11 = true;
    enableTPM = true;
  };
in
lib.mkIf cfg.enable {
  # FIX: Enable strongSwan VPN with Strong Keyring support
  services.strongswan = {
    enable = cfg.enable;
  };

  # FIX: Ensure proper permissions for hardware tokens
  # NOTE: Add user to plugdev group to access USB tokens and smartcards
  users.users.yusa.extraGroups = lib.optionals cfg.enablePKCS11 [
    "plugdev"
  ];

  # INFO: System packages for Strong Keyring and related tools
  environment.systemPackages = with pkgs; [
    # FIX: strongSwan VPN with Strong Keyring support
    strongswan
    
    # FIX: PKCS#11 libraries for hardware token support
    libp11
    opensc  # INFO: Smart card support
    
    # FIX: Cryptography support
    gnutls
    openssl
    
    # INFO: TPM tools for TPM-based keys (if using TPM tokens)
    tpm2-tools
    tpm2-abrmd
    
    # INFO: Hardware token management utilities
    libyubikey
    yubico-pam
    yubico-piv-tool
  ];

  # FIX: Configure udev rules for hardware token access
  # NOTE: Allows non-root users in plugdev group to access USB tokens
  services.udev.packages = with pkgs; [
    opensc
    yubikey-personalization
  ];

  # FIX: Shell aliases for Strong Keyring tools
  environment.etc."profile.d/91-strong-keyring.sh".text = ''
    # INFO: List available PKCS#11 modules
    alias pkcs11-list='p11-kit list-modules'
    
    # INFO: Test hardware token connectivity
    alias token-info='opensc-tool --info'
    
    # INFO: Test StrongSwan with hardware tokens
    alias strongswan-status='sudo ipsec status'
    alias strongswan-restart='sudo ipsec restart'
  '';
}
