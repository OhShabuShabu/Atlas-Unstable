{ pkgs, ... }:

# INFO: ============================================================================
# INFO: PROCESS ACCOUNTING CONFIGURATION (ACCT-9622)
# INFO: ============================================================================
# INFO: Enables process-level accounting for security audit and compliance
# FIX: Process accounting enabled for detailed security monitoring (ACCT-9622)

{
  # FIX: Install process accounting utilities (ACCT-9622)
  # NOTE: psacct provides process accounting tools
  environment.systemPackages = with pkgs; [
    # INFO: Process accounting utilities
    acct  # INFO: Main process accounting tools
  ];

  # FIX: Enable process accounting daemon (ACCT-9622)
  systemd.services.acct = {
    description = "Process accounting daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.acct}/bin/accton /var/account/pacct";
      ExecStop = "${pkgs.acct}/bin/accton";
    };
  };

  # FIX: Configure process accounting with proper logging (ACCT-9622)
  systemd.tmpfiles.rules = [
    "d /var/account 0755 root root -"
    "f /var/account/pacct 0600 root root -"
  ];

  # FIX: Shell alias for process accounting reports
  environment.etc."profile.d/93-pacct.sh".text = ''
    # INFO: View process accounting data
    alias pa-report='sudo lastcomm'
    alias pa-summary='sudo ac'
    alias pa-dump='sudo dump-acct'
  '';
}
