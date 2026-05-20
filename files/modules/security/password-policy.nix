{ lib, pkgs, ... }: {
    # ============================================================================
    # SECTION 8: PASSWORD POLICY
    # ============================================================================
    # NOTE: pam_passwdqc can be added via security.pam.services.<name>.text
    #       if desired (Lynis AUTH-9262). Current policy manages strength
    #       through login.defs settings (PASS_MIN_LEN, YESCRYPT).

    # INFO: Disable GNOME keyring (security preference)
    security.pam.services.login.enableGnomeKeyring = lib.mkForce false;

    # INFO: Password aging and quality settings
    security.loginDefs.settings = {
        FAIL_DELAY = "3";
        LOGIN_RETRIES = "3";
        LOGIN_TIMEOUT = "30";
        PASS_MAX_DAYS = "90";
        PASS_MIN_DAYS = "7";
        PASS_WARN_AGE = "7";
        PASS_MIN_LEN = "12";
        # FIX: Use YESCRYPT - modern password hashing (2024+)
        #      More secure than SHA512, resistant to GPU cracking
        ENCRYPT_METHOD = "YESCRYPT";
        YESCRYPT_COST_FACTOR = "10";

        # Disable legacy hashing methods
        MD5_CRYPT_ENAB = "false";
        SHA_CRYPT_MIN_ROUNDS = "10000";
        SHA_CRYPT_MAX_ROUNDS = "10000";
    };

}