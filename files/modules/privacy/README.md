# Privacy Module

Privacy-first browsing and VPN configuration.

## Includes
- **Mullvad VPN** — Auto-connect on boot
- **Mullvad Browser** — Privacy-hardened Tor-integrated browser
- **Librewolf** — Hardened Firefox fork (default browser)
- **Metadata Cleaner** — Remove EXIF/metadata from files

## Mullvad VPN

Automatically connects on boot. To manage:
- Open Mullvad VPN GUI
- Select exit country/server
- View connection status

## Mullvad Browser

Provides Tor integration for maximum privacy. Use for:
- Sensitive research
- Anonymous browsing
- High-privacy communications

## Librewolf (Default Browser)

Configured as default browser with:
- Enhanced privacy settings
- Tracking protection (strict mode)
- No telemetry

## Metadata Cleaning

Automatically available as command-line tool:
```bash
metadata-cleaner /path/to/file.jpg
```

Removes:
- EXIF data from images
- GPS coordinates
- Camera information
- Document properties
