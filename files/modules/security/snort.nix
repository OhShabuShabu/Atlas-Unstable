{ pkgs, lib, config, ... }:

let
  snortPkg = pkgs.snort;

  snortRules = pkgs.writeTextDir "local.rules" ''
    # ============================================================================
    # SNORT LOCAL RULES — Atlas Security Configuration
    # ============================================================================
    # These rules detect malicious/dangerous traffic and trigger alerts.
    # Priority 1 = critical, 2 = high, 3 = medium

    # --------------------------------------------------------------------------
    # 1. MALWARE C2 / BOTNET DETECTION
    # --------------------------------------------------------------------------
    alert tcp $HOME_NET any -> $EXTERNAL_NET $HTTP_PORTS (
      msg:"MALWARE-CNC - Known malware callback detected";
      classtype:trojan-activity; sid:1000001; rev:1; priority:1;
      content:"/gate.php", nocase; http_uri;
      content:"bot_id", nocase; http_client_body;
      metadata: service http;
    )

    alert tcp $HOME_NET any -> $EXTERNAL_NET $HTTP_PORTS (
      msg:"MALWARE-CNC - Possible Cobalt Strike beacon";
      classtype:trojan-activity; sid:1000002; rev:1; priority:1;
      content:"|00 00 00 00 00 00 00 00|", depth 8;
      metadata: service http;
    )

    alert tcp $HOME_NET any -> $EXTERNAL_NET $HTTP_PORTS (
      msg:"MALWARE-CNC - Possible Mirai variant callback";
      classtype:trojan-activity; sid:1000003; rev:1; priority:1;
      content:"/cdn-cgi/", nocase; http_uri;
      pcre:"/\/cdn-cgi\/.*(?:report|connect)/Ri";
      metadata: service http;
    )

    alert tcp $HOME_NET any -> $EXTERNAL_NET [4444,6667,6668,6669] (
      msg:"MALWARE-CNC - Connection to known malware hosting IP range";
      classtype:trojan-activity; sid:1000004; rev:1; priority:1;
      metadata: relation dest_ip;
    )

    # --------------------------------------------------------------------------
    # 2. EXPLOIT DETECTION
    # --------------------------------------------------------------------------
    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"EXPLOIT - EternalBlue SMBv1 exploit attempt";
      classtype:attempted-admin; sid:1000010; rev:1; priority:1;
      content:"|00 00 00 31 ff|SMB|2e 00|", depth 10;
      content:"|00 00 00 00 00 00 00 00 00 00|", within 15;
      metadata: service smb;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET 445 (
      msg:"EXPLOIT - SMB remote code execution attempt";
      classtype:attempted-admin; sid:1000011; rev:1; priority:1;
      content:"|ff 53 6d 62 76 31|", depth 10;
      reference:cve,2020-0796;
      metadata: service smb;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET 3389 (
      msg:"EXPLOIT - RDP brute force / BlueKeep attempt";
      classtype:attempted-admin; sid:1000012; rev:1; priority:1;
      flow:to_server,established;
      content:"|03 00 00 0a 02 f0 80|", depth 10;
      detection_filter:track by_src, count 10, seconds 30;
      reference:cve,2019-0708;
      metadata: service rdp;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET 22 (
      msg:"EXPLOIT - SSH brute force attempt";
      classtype:attempted-admin; sid:1000013; rev:1; priority:2;
      flow:to_server,established;
      detection_filter:track by_src, count 20, seconds 60;
      metadata: service ssh;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"EXPLOIT - Shellshock CGI environment variable injection";
      classtype:attempted-admin; sid:1000014; rev:1; priority:1;
      flow:to_server,established;
      content:"() { :; };", nocase; http_header;
      reference:cve,2014-6271;
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET $HTTP_PORTS (
      msg:"EXPLOIT - Log4j JNDI injection attempt";
      classtype:web-application-attack; sid:1000015; rev:1; priority:1;
      flow:to_server,established;
      content:"''${jndi:", nocase;
      content:"ldap://", within 200, nocase;
      reference:cve,2021-44228;
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET $HTTP_PORTS (
      msg:"EXPLOIT - Apache Struts OGNL injection";
      classtype:web-application-attack; sid:1000016; rev:1; priority:1;
      flow:to_server,established;
      content:"%{", nocase;
      pcre:"/%7B/R";
      reference:cve,2017-5638;
      metadata: service http;
    )

    # --------------------------------------------------------------------------
    # 3. NETWORK SCANNING / RECONNAISSANCE
    # --------------------------------------------------------------------------
    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"SCAN - Port scan detected (TCP SYN)";
      classtype:network-scan; sid:1000020; rev:1; priority:2;
      flags:S,12; detection_filter:track by_src, count 50, seconds 10;
    )

    alert icmp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"SCAN - ICMP sweep / ping sweep detected";
      classtype:network-scan; sid:1000021; rev:1; priority:2;
      itype:8; detection_filter:track by_src, count 20, seconds 10;
    )

    alert udp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"SCAN - UDP port scan detected";
      classtype:network-scan; sid:1000022; rev:1; priority:2;
      detection_filter:track by_src, count 50, seconds 10;
    )

    alert ip $EXTERNAL_NET any -> $HOME_NET any (
      msg:"SCAN - IP protocol scan detected";
      classtype:network-scan; sid:1000023; rev:1; priority:2;
      detection_filter:track by_src, count 20, seconds 10;
    )

    # --------------------------------------------------------------------------
    # 4. DENIAL OF SERVICE ATTACKS
    # --------------------------------------------------------------------------
    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"DOS - TCP SYN flood detected";
      classtype:denial-of-service; sid:1000030; rev:1; priority:2;
      flags:S,12; detection_filter:track by_src, count 200, seconds 5;
    )

    alert icmp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"DOS - ICMP flood detected";
      classtype:denial-of-service; sid:1000031; rev:1; priority:2;
      itype:8; detection_filter:track by_src, count 200, seconds 5;
    )

    # --------------------------------------------------------------------------
    # 5. SUSPICIOUS / MALICIOUS PAYLOADS
    # --------------------------------------------------------------------------
    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"PAYLOAD - Base64 encoded executable download";
      classtype:string-detect; sid:1000040; rev:1; priority:2;
      content:"TVqQAAMAAAAEAAAA", within 400;
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"PAYLOAD - PowerShell encoded command detected";
      classtype:string-detect; sid:1000041; rev:1; priority:2;
      flow:to_server,established;
      content:"-EncodedCommand", nocase;
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET $HTTP_PORTS (
      msg:"PAYLOAD - Possible web shell upload attempt";
      classtype:web-application-attack; sid:1000042; rev:1; priority:1;
      flow:to_server,established;
      content:".php", nocase; http_uri;
      pcre:"/(?:cmd|exec|shell|eval|system)\s*=/Ri";
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET $HTTP_PORTS (
      msg:"PAYLOAD - SQL injection attempt";
      classtype:web-application-attack; sid:1000043; rev:1; priority:1;
      flow:to_server,established;
      pcre:"/(?i)(?:union.*select|select.*from|insert.*into|delete.*from|drop.*table|exec.*master)/R";
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET $HTTP_PORTS (
      msg:"PAYLOAD - XSS attempt detected";
      classtype:web-application-attack; sid:1000044; rev:1; priority:2;
      flow:to_server,established;
      pcre:"/<(?i:script|iframe|object|embed)\b[^>]*>/R";
      metadata: service http;
    )

    # --------------------------------------------------------------------------
    # 6. POLICY VIOLATIONS / DANGEROUS TRAFFIC
    # --------------------------------------------------------------------------
    alert udp $HOME_NET any -> $EXTERNAL_NET 53 (
      msg:"POLICY - DNS query to known malicious domain pattern";
      classtype:malware-cnc; sid:1000050; rev:1; priority:1;
      content:"|04 64 67 67 61|", depth 10, nocase;
      metadata: service dns;
    )

    alert tcp $HOME_NET any -> $EXTERNAL_NET 25 (
      msg:"POLICY - Outbound SMTP (possible data exfiltration)";
      classtype:policy-violation; sid:1000051; rev:1; priority:2;
      flow:to_server,established;
    )

    alert tcp $HOME_NET any -> $EXTERNAL_NET 445 (
      msg:"POLICY - Outbound SMB (possible data exfiltration)";
      classtype:policy-violation; sid:1000052; rev:1; priority:2;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET 23 (
      msg:"POLICY - Inbound Telnet (unencrypted, dangerous)";
      classtype:policy-violation; sid:1000053; rev:1; priority:2;
      metadata: service telnet;
    )

    # --------------------------------------------------------------------------
    # 7. PROTOCOL ANOMALIES
    # --------------------------------------------------------------------------
    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"ANOMALY - TCP packet with NO flags set (null scan)";
      classtype:network-scan; sid:1000060; rev:1; priority:2;
      flags:0,12;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"ANOMALY - TCP XMAS scan detected";
      classtype:network-scan; sid:1000061; rev:1; priority:2;
      flags:FPU,12;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"ANOMALY - TCP FIN scan detected";
      classtype:network-scan; sid:1000062; rev:1; priority:2;
      flags:F,12;
    )

    # --------------------------------------------------------------------------
    # 8. MALICIOUS FILE DOWNLOADS
    # --------------------------------------------------------------------------
    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"FILE - Windows executable download (PE file)";
      classtype:string-detect; sid:1000070; rev:1; priority:2;
      content:"MZ", within 2;
      content:"PE|00 00|", distance -2, within 64;
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"FILE - ZIP archive download (potential malware delivery)";
      classtype:string-detect; sid:1000071; rev:1; priority:3;
      content:"PK|03 04|", within 4;
      metadata: service http;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET any (
      msg:"FILE - JavaScript download (potential drive-by)";
      classtype:string-detect; sid:1000072; rev:1; priority:3;
      flow:to_client,established;
      content:"Content-Disposition: attachment", nocase; http_header;
      content:".js", nocase; http_header;
      metadata: service http;
    )

    # --------------------------------------------------------------------------
    # 9. DNS TUNNELING / DATA EXFIL
    # --------------------------------------------------------------------------
    alert udp $HOME_NET any -> $EXTERNAL_NET 53 (
      msg:"EXFIL - DNS query with high entropy (possible tunneling)";
      classtype:policy-violation; sid:1000080; rev:1; priority:2;
      content:"|01 00 00 01 00 00 00 00 00 00|", depth 10;
      byte_test:1,>,63,0,relative,string,dec;
      metadata: service dns;
    )

    # --------------------------------------------------------------------------
    # 10. SPECIALIZED ATTACK PATTERNS
    # --------------------------------------------------------------------------
    alert tcp $EXTERNAL_NET any -> $HOME_NET 1433 (
      msg:"ATTACK - MSSQL brute force / SA password attempt";
      classtype:attempted-admin; sid:1000090; rev:1; priority:1;
      flow:to_server,established;
      content:"|02 01|", depth 2;
      detection_filter:track by_src, count 10, seconds 30;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET 3306 (
      msg:"ATTACK - MySQL brute force attempt";
      classtype:attempted-admin; sid:1000091; rev:1; priority:2;
      flow:to_server,established;
      detection_filter:track by_src, count 10, seconds 30;
    )

    alert udp $EXTERNAL_NET 1900 -> $HOME_NET any (
      msg:"ATTACK - SSDP amplification attempt (DDoS reflection)";
      classtype:denial-of-service; sid:1000092; rev:1; priority:2;
      content:"M-SEARCH", nocase;
      metadata: service upnp;
    )

    alert tcp $EXTERNAL_NET any -> $HOME_NET 11211 (
      msg:"ATTACK - Memcached probe (potential amplification vector)";
      classtype:attempted-recon; sid:1000093; rev:1; priority:2;
      flow:to_server,established;
    )
  '';

  snortConfig = pkgs.writeTextDir "snort.lua" ''
    -- ============================================================================
    -- Snort++ configuration — Atlas NixOS Security Hardening
    -- ============================================================================

    HOME_NET = '192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12'
    EXTERNAL_NET = '!$HOME_NET'

    RULE_PATH = '${snortRules}'
    BUILTIN_RULE_PATH = '${snortPkg}/etc/snort'
    PLUGIN_RULE_PATH = '${snortPkg}/etc/snort'

    include '${snortPkg}/etc/snort/snort_defaults.lua'

    -- ============================================================================
    -- 2. CONFIGURE INSPECTION
    -- ============================================================================
    stream = { }
    stream_ip = { }
    stream_icmp = { }
    stream_tcp = { }
    stream_udp = { }
    stream_user = { }
    stream_file = { }

    arp_spoof = { }
    back_orifice = { }
    dns = { }
    imap = { }
    netflow = { }
    normalizer = { }
    pop = { }
    rpc_decode = { }
    sip = { }
    ssh = { }
    ssl = { }
    telnet = { }

    cip = { }
    dnp3 = { }
    iec104 = { }
    mms = { }
    modbus = { }
    s7commplus = { }

    dce_smb = { }
    dce_tcp = { }
    dce_udp = { }
    dce_http_proxy = { }
    dce_http_server = { }

    gtp_inspect = default_gtp
    port_scan = default_med_port_scan
    smtp = default_smtp

    ftp_server = default_ftp_server
    ftp_client = { }
    ftp_data = { }

    http_inspect = { }
    http2_inspect = { }

    file_id = { rules_file = '${snortPkg}/etc/snort/file_magic.rules' }
    file_policy = { }

    js_norm = default_js_norm

    -- ============================================================================
    -- 3. CONFIGURE BINDINGS
    -- ============================================================================
    wizard = default_wizard

    binder =
    {
        { when = { proto = 'udp', ports = '53', role='server' },  use = { type = 'dns' } },
        { when = { proto = 'tcp', ports = '53', role='server' },  use = { type = 'dns' } },
        { when = { proto = 'tcp', ports = '111', role='server' }, use = { type = 'rpc_decode' } },
        { when = { proto = 'tcp', ports = '502', role='server' }, use = { type = 'modbus' } },
        { when = { proto = 'tcp', ports = '2123 2152 3386', role='server' }, use = { type = 'gtp_inspect' } },
        { when = { proto = 'tcp', ports = '2404', role='server' }, use = { type = 'iec104' } },
        { when = { proto = 'udp', ports = '2222', role = 'server' }, use = { type = 'cip' } },
        { when = { proto = 'tcp', ports = '44818', role = 'server' }, use = { type = 'cip' } },
        { when = { service = 'netbios-ssn' },      use = { type = 'dce_smb' } },
        { when = { service = 'dce_http_server' },  use = { type = 'dce_http_server' } },
        { when = { service = 'dce_http_proxy' },   use = { type = 'dce_http_proxy' } },
        { when = { service = 'cip' },              use = { type = 'cip' } },
        { when = { service = 'dnp3' },             use = { type = 'dnp3' } },
        { when = { service = 'dns' },              use = { type = 'dns' } },
        { when = { service = 'ftp' },              use = { type = 'ftp_server' } },
        { when = { service = 'ftp-data' },         use = { type = 'ftp_data' } },
        { when = { service = 'gtp' },              use = { type = 'gtp_inspect' } },
        { when = { service = 'imap' },             use = { type = 'imap' } },
        { when = { service = 'http' },             use = { type = 'http_inspect' } },
        { when = { service = 'http2' },            use = { type = 'http2_inspect' } },
        { when = { service = 'iec104' },           use = { type = 'iec104' } },
        { when = { service = 'mms' },              use = { type = 'mms' } },
        { when = { service = 'modbus' },           use = { type = 'modbus' } },
        { when = { service = 'pop3' },             use = { type = 'pop' } },
        { when = { service = 'ssh' },              use = { type = 'ssh' } },
        { when = { service = 'sip' },              use = { type = 'sip' } },
        { when = { service = 'smtp' },             use = { type = 'smtp' } },
        { when = { service = 'ssl' },              use = { type = 'ssl' } },
        { when = { service = 'sunrpc' },           use = { type = 'rpc_decode' } },
        { when = { service = 's7commplus' },       use = { type = 's7commplus' } },
        { when = { service = 'telnet' },           use = { type = 'telnet' } },
        { use = { type = 'wizard' } }
    }

    -- ============================================================================
    -- 5. CONFIGURE DETECTION
    -- ============================================================================
    references = default_references
    classifications = default_classifications

    ips =
    {
        enable_builtin_rules = true,
        variables = default_variables,
        include = '${snortRules}/local.rules',
    }

    -- ============================================================================
    -- 7. CONFIGURE OUTPUTS — Alert logging
    -- ============================================================================
    alert_csv =
    {
        file = true,
    }

  '';
  snortMonitorDaemon = pkgs.writeShellScriptBin "snort-monitor" ''
    set -e
    LOG_DIR="/var/log/snort"
    EVENTS_LOG="$LOG_DIR/events.log"
    ALERT_LOG="$LOG_DIR/alert_csv.txt"
    mkdir -p "$LOG_DIR"

    log_event() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$EVENTS_LOG"
    }

    notify_user() {
      local urgency="$1"
      local title="$2"
      local msg="$3"
      ${notifyScript}/bin/snort-notify "$urgency" "$title" "$msg"
    }

    log_event "INFO" "Snort notification monitor starting"
    notify_user "normal" "Snort" "Network IDS monitoring active"

    LAST_LINE=0
    while true; do
      if [ -f "$ALERT_LOG" ]; then
        TOTAL=$(wc -l < "$ALERT_LOG" 2>/dev/null || echo 0)
        if [ "$TOTAL" -gt "$LAST_LINE" ]; then
          NEW=$((TOTAL - LAST_LINE))
          tail -n "$NEW" "$ALERT_LOG" | while IFS= read -r line; do
            SEVERITY="high"
            MSG=$(echo "$line" | awk -F',' '{print $NF}' | tr -d '"' || echo "Snort alert")
            SRC=$(echo "$line" | awk -F',' '{print $6}' || echo "unknown")
            DST=$(echo "$line" | awk -F',' '{print $8}' || echo "unknown")
            log_event "ALERT" "$MSG | $SRC -> $DST"
            notify_user "$SEVERITY" "Snort Alert" "$MSG | $SRC → $DST"
          done
          LAST_LINE=$TOTAL
        fi
      fi
      sleep 5
    done
  '';

  notifyScript = pkgs.writeShellScriptBin "snort-notify" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    SEVERITY="$1"
    TITLE="$2"
    MESSAGE="$3"

    for user in yusa; do
      uid=$(id -u "$user" 2>/dev/null || echo 1000)
      bus_path="/run/user/$uid/bus"
      if [ -S "$bus_path" ]; then
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path" \
          "$NOTIFY" -u "$SEVERITY" -t 10000 "$TITLE" "$MESSAGE" 2>/dev/null || true
      fi
    done
  '';

  snortBin = pkgs.writeShellScriptBin "snortctl" ''
    set -e
    case "''${1:-help}" in
      status)
        systemctl status snort-daemon 2>/dev/null || echo "snort-daemon not running"
        systemctl status snort-monitor 2>/dev/null || echo "snort-monitor not running"
        ;;
      logs)
        journalctl -fu snort-daemon
        ;;
      alerts)
        tail -f /var/log/snort/alert_csv.txt 2>/dev/null || echo "No alerts yet"
        ;;
      events)
        tail -f /var/log/snort/events.log 2>/dev/null || echo "No events yet"
        ;;
      test)
        echo "Running Snort config test..."
        ${snortPkg}/bin/snort -c ${snortConfig}/snort.lua -T -i lo 2>&1 || true
        ;;
      restart)
        systemctl restart snort-daemon snort-monitor
        echo "Snort daemon restarted"
        ;;
      *)
        echo "Usage: snortctl <status|logs|alerts|events|test|restart>"
        exit 1
        ;;
    esac
  '';
in

{
  environment.systemPackages = [ snortPkg snortBin snortMonitorDaemon notifyScript ];

  systemd.tmpfiles.rules = [
    "d /var/log/snort 0750 root root -"
  ];

  systemd.services.snort-daemon = {
    description = "Snort Network Intrusion Detection System";
    after = [ "network.target" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ snortPkg pkgs.coreutils pkgs.gawk pkgs.gnused ];
    serviceConfig = {
      Type = "simple";
      ExecStart = ''${snortPkg}/bin/snort -c ${snortConfig}/snort.lua -i any -l /var/log/snort'';
      ExecReload = "${snortPkg}/bin/snort -c ${snortConfig}/snort.lua -T 2>/dev/null && kill -HUP $MAINPID";
      Restart = "on-failure";
      RestartSec = 10;
      User = "root";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ReadWritePaths = [ "/var/log/snort" ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = false;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      CapabilityBoundingSet = [ "CAP_NET_RAW" "CAP_NET_ADMIN" ];
      SystemCallArchitectures = "native";
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
    };
  };

  systemd.services.snort-monitor = {
    description = "Snort Alert Notification Monitor";
    after = [ "snort-daemon.service" ];
    wants = [ "snort-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${snortMonitorDaemon}/bin/snort-monitor";
      Restart = "on-failure";
      RestartSec = 5;
      User = "root";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ReadWritePaths = [ "/var/log/snort" ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" ];
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = true;
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
    };
  };
}
