# Snort NIDS — Changelog

## Files Created

### `files/modules/security/snort.nix`
Snort3-based Network Intrusion Detection System module. Provides:

- **snort-daemon.service** — runs Snort3 in IDS mode on loopback
- **snort-monitor.service** — watches alert CSV output, sends desktop notifications via `notify-send` (DBUS, same pattern as Snout/ClamAV)
- **snortctl** — CLI tool: `status|logs|alerts|events|test|restart`
- **snort-notify** — notification helper script

#### Rules (93 total, SIDs 1000001–1000093)
| Category | Description |
|----------|-------------|
| Malware C2 | Callback detection, Cobalt Strike beacon, Mirai variant, known bad ports |
| Exploits | EternalBlue (SMBv1), SMBGhost (CVE-2020-0796), BlueKeep (RDP), SSH brute force, Shellshock, Log4j JNDI, Struts OGNL |
| Recon | TCP SYN scan, ICMP sweep, UDP scan, IP protocol scan |
| DoS | TCP SYN flood, ICMP flood |
| Payloads | Base64 PE download, PowerShell encoded cmd, web shells, SQLi, XSS |
| Policy | Outbound SMTP/SMB (exfil), inbound Telnet |
| Protocol | NULL scan, XMAS scan, FIN scan |
| Files | PE/JS/ZIP download detection |
| DNS | High-entropy DNS queries (tunneling detection) |
| Services | MSSQL/MySQL brute force, SSDP amplification, Memcached probe |

#### Systemd Hardening
Both services follow the same sandboxing pattern as Snout: `NoNewPrivileges`, `ProtectSystem=full`, `PrivateTmp`, `ProtectHome`, `MemoryDenyWriteExecute`, `LockPersonality`, `RestrictNamespaces`, `RestrictRealtime`, `RestrictSUIDSGID`.

snort-daemon additionally gets `CAP_NET_RAW` + `CAP_NET_ADMIN` (needed for packet capture) and `PrivateDevices=false`.

## Files Modified

### `files/modules/security/default.nix`
- Added `./snort.nix` to imports
- Added `snort` to `environment.systemPackages`
- Added aliases: `snort-status`, `snort-alerts`, `snortctl`

### `files/core/configuration.nix`
- Added `../modules/security/snort.nix` import (before snout)
