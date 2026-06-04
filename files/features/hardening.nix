{ ... }: {
  flake.modules.nixos.hardening = { pkgs, lib, config, ... }: {
    security.apparmor = {
      enable = true;
      killUnconfinedConfinables = true;
    };

    security.lockKernelModules = true;
    security.protectKernelImage = true;
    security.forcePageTableIsolation = true;
    security.virtualisation.flushL1DataCache = "always";

    security.tpm2 = {
      enable = true;
      tctiEnvironment.enable = true;
    };

    security.audit = {
      enable = true;
      backlogLimit = 8192;
    };
    security.auditd.enable = true;

    systemd.services.audit-rules-nixos.serviceConfig = {
      ExecStart = lib.mkForce "${pkgs.bash}/bin/sh -c \"${pkgs.audit}/bin/auditctl -D && ${pkgs.audit}/bin/auditctl -R ${pkgs.writeTextDir "audit.rules" ''
        -a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
        -a always,exit -F arch=b64 -S clock_settime -k time_change
        -w /etc/localtime -p wa -k time_change
        -w /etc/group -p wa -k identity
        -w /etc/passwd -p wa -k identity
        -w /etc/gshadow -p wa -k identity
        -w /etc/shadow -p wa -k identity
        -w /etc/security/opasswd -p wa -k identity
        -a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_modifications
        -w /etc/hostname -p wa -k network_modifications
        -w /etc/hosts -p wa -k network_modifications
        -w /etc/network -p wa -k network_modifications
        -w /var/log/faillog -p wa -k logins
        -w /var/log/lastlog -p wa -k logins
        -w /var/log/tallylog -p wa -k logins
        -w /etc/sudoers -p wa -k scope
        -w /etc/sudoers.d/ -p wa -k scope
        -a always,exit -F arch=b64 -S init_module -k modules
        -a always,exit -F arch=b64 -S delete_module -k modules
        -a always,exit -F arch=b64 -S chmod -F auid>=1000 -F auid!=-1 -k perm_mod
        -a always,exit -F arch=b64 -S chown -F auid>=1000 -F auid!=-1 -k perm_mod
        -a always,exit -F arch=b64 -S fchmod -F auid>=1000 -F auid!=-1 -k perm_mod
        -a always,exit -F arch=b64 -S fchmodat -F auid>=1000 -F auid!=-1 -k perm_mod
        -a always,exit -F arch=b64 -S open,openat -F exit=-EACCES -F auid>=1000 -F auid!=-1 -k access
        -a always,exit -F arch=b64 -S open,openat -F exit=-EPERM -F auid>=1000 -F auid!=-1 -k access
      ''}/audit.rules\"";
      ExecStopPost = lib.mkForce [ "${pkgs.coreutils}/bin/true" ];
    };

    services.dbus.implementation = "broker";

    security.sudo.execWheelOnly = true;

    security.sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    services.sysstat = { enable = true; };

    security.loginDefs.settings = {
      UMASK = "027";
      USERGROUPS_ENAB = "no";
    };

    environment.etc."profile.d/umask.sh".text = ''
      umask 027
    '';

    environment.etc."profile.d/session-timeout.sh".text = ''
      TMOUT=900
      readonly TMOUT
      export TMOUT
    '';

    environment.etc."profile.d/coredump.sh".text = ''
      ulimit -c 0 > /dev/null 2>&1
    '';
    environment.etc."systemd/coredump.conf.d/disable.conf".text = ''
      [Coredump]
      ProcessSizeMax=0
      Storage=none
    '';

    fileSystems."/proc" = {
      device = "proc";
      fsType = "proc";
      options = [ "nosuid" "noexec" "nodev" "hidepid=2" ];
    };

    systemd.services."NetworkManager-dispatcher".serviceConfig = {
      NoNewPrivileges = true;
      PrivateNetwork = false;
      ProtectHome = lib.mkDefault true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
    };

    systemd.services."usbguard-dbus".serviceConfig = {
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "full";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
    };

    services.logrotate.enable = true;
    services.logrotate.settings = {
      header = {
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        rotate = 4;
        frequency = "weekly";
        create = "0640 root adm";
      };
    };

    services.rsyslogd.enable = true;
    services.rsyslogd.extraConfig = ''
      $IncludeConfig /etc/rsyslog.d/remote.conf
    '';

    environment.etc."rsyslog.d/remote.conf".source = ./../etc/rsyslog.d/remote.conf;

    security.pam.services = {
      sudo = { allowNullPassword = lib.mkForce false; nodelay = true; };
      su = { allowNullPassword = lib.mkForce false; nodelay = true; };
      login = { allowNullPassword = lib.mkForce false; nodelay = true; };
      passwd = {
        text = lib.mkDefault (lib.mkBefore "password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so try_first_pass");
      };
      chpasswd = {
        text = lib.mkDefault (lib.mkBefore "password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so try_first_pass");
      };
    };

    services.usbguard = {
      enable = true;
      rules = "allow";
      implicitPolicyTarget = "allow";
      presentDevicePolicy = "apply-policy";
      IPCAllowedUsers = [ "root" "yusa" ];
      IPCAllowedGroups = [ "wheel" ];
      dbus.enable = true;
    };

    environment.etc."usbguard/usbguard-daemon.conf".text = ''
      RuleFile=/var/lib/usbguard/rules.conf
      ImplicitPolicyTarget=allow
      PresentDevicePolicy=apply-policy
      PresentControllerPolicy=keep
      IPCAllowedUsers=root yusa
      IPCAllowedGroups=wheel
      DeviceRulesWithPort=false
      AuditBackend=LinuxAudit
    '';

    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl --no-block start systemd-udev-trigger.service"
      SUBSYSTEM=="block", ACTION=="add", ATTR{removable}=="1", RUN+="${pkgs.systemd}/bin/udevadm trigger"
      SUBSYSTEM=="block", KERNEL=="nvme0n1*", ENV{UDISKS_PRESENTATION_HIDE}="1"
      SUBSYSTEM=="block", ENV{ID_PART_ENTRY_NAME}=="disk-main-esp", ENV{UDISKS_PRESENTATION_HIDE}="1"
      SUBSYSTEM=="block", ENV{ID_PART_ENTRY_NAME}=="disk-main-root", ENV{UDISKS_PRESENTATION_HIDE}="1"
      SUBSYSTEM=="block", ENV{DM_NAME}=="crypt", ENV{UDISKS_PRESENTATION_HIDE}="1"
    '';

    environment.etc."pam.d/common-password".text = ''
      password requisite ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so try_first_pass
    '';

    systemd.tmpfiles.rules = [
      "L+ /lib/security/pam_pwquality.so - - - - ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so"
    ];

    systemd.services.fix-home-perms = {
      description = "Fix home directory permissions for Lynis compliance";
      after = [ "home.mount" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/chmod 0750 /home/yusa";
      };
    };

    services.resolved = {
      enable = true;
      settings = {
        Resolve = {
          DNS = [ "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001" ];
          FallbackDNS = [ "8.8.8.8" "8.8.4.4" ];
          DNSOverTLS = true;
          DNSSEC = true;
          DNSStubListener = "yes";
        };
      };
    };
  };
}
