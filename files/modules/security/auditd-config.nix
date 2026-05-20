{ pkgs, lib, ... }:

{
  systemd.tmpfiles.rules = [
    "d /var/log/audit 0750 root root -"
    "f /var/log/audit/audit.log 0640 root root -"
  ];

  environment.systemPackages = with pkgs; [
    audit
  ];

  environment.etc."profile.d/92-audit.sh".text = ''
    alias audit-tail='sudo tail -f /var/log/audit/audit.log'
    alias audit-search='sudo ausearch'
    alias audit-report='sudo aureport'
  '';
}
