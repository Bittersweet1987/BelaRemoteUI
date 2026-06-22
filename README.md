# BelaRemoteUI

Self-hosted remote access to one or more BELABOX web UIs through your own VPS.

The official BELABOX remote key is not used, overwritten, or modified. Each BELABOX opens only an outgoing Chisel tunnel to your VPS; SSH between BELABOX and VPS is not required.

## Deutsch

### Inhalt

- [Überblick](#überblick)
- [Voraussetzungen](#voraussetzungen)
- [Schnellstart](#schnellstart)
- [Mehrere BELABOXen](#mehrere-belaboxen)
- [Nutzung](#nutzung)
- [Verwaltung](#verwaltung)
- [Troubleshooting](#troubleshooting)
- [Lizenz](#lizenz)

### Überblick

BelaRemoteUI besteht aus zwei Scripts:

| Script | Läuft auf | Zweck |
| --- | --- | --- |
| `belabox-vps-remote-server.sh` | VPS | Nginx, Chisel-Server, Profile und feste Remote-URLs |
| `belabox-vps-remote-client.sh` | BELABOX | Lokaler Proxy und ausgehender Chisel-Tunnel |

Pro BELABOX-Profil erzeugt der VPS:

| Wert | Beispiel |
| --- | --- |
| Remote-URL | `http://158.180.35.14/r/DEIN_PROFILNAME/0b9a.../` |
| Widget/API-URL | `http://158.180.35.14/?token=0b9a...` |
| WebSocket-URL | `ws://158.180.35.14/?token=0b9a...` |
| Tunnel-Token | `DEIN_PROFILNAME:abc123...` |
| Interner VPS-Port | `18080`, `18081`, `18082` |

### Voraussetzungen

- VPS mit Ubuntu 24.04 oder Ubuntu 26.04
- Root- oder sudo-Zugriff auf VPS und BELABOX
- Offene VPS-Ports: HTTP `80` oder der ausgegebene Port, Chisel `9090`, SSH-Management-Port
- BELABOX mit Terminal- oder SSH-Zugriff

Wenn eine bestehende RTMP-Nginx-Konfiguration erkannt wird, weicht BelaRemoteUI automatisch auf HTTP-Port `8088` aus, sofern du keinen eigenen `--public-port` setzt.

### Schnellstart

**1. Auf dem VPS ausführen:**

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile DEIN_PROFILNAME
```


**2. Den ausgegebenen BELABOX-Befehl kopieren.**

Das VPS-Script zeigt am Ende eine komplette Zeile wie diese:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14 --tunnel-server-port 9090 --tunnel-auth DEIN_PROFILNAME:DEIN_TOKEN --remote-port 18080 --public-url http://158.180.35.14/r/DEIN_PROFILNAME/DEIN_LINK/
```

**3. Genau diese Zeile auf der passenden BELABOX ausführen.**

Das BELABOX-Script installiert fehlende Pakete inklusive `curl`, `nodejs`, `gzip` und Chisel.

### Mehrere BELABOXen

Für jede weitere BELABOX ein neues Profil auf dem VPS anlegen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile WEITERER_PROFILNAME
```

Danach wieder den neu ausgegebenen BELABOX-Befehl auf der zweiten BELABOX ausführen.

Profile anzeigen:

```bash
belabox-remote-vps-status
```

Link eines Profils neu erzeugen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile DEIN_PROFILNAME --regenerate-link
```

### Nutzung

Browser:

```text
http://158.180.35.14/r/DEIN_PROFILNAME/0b9a8c7d6e5f4a3b2c1d/
```

Widget/API:

```text
http://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
```

Bei RTMP-Ausweichport:

```text
http://158.180.35.14:8088/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14:8088/?token=0b9a8c7d6e5f4a3b2c1d
```

### Verwaltung

Profile auf dem VPS anzeigen:

```bash
belabox-remote-vps-status
```

Remote-Link auf der BELABOX anzeigen:

```bash
belabox-vps-remote-link
```

VPS-Profil löschen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --delete-profile DEIN_PROFILNAME
```

VPS-Installation komplett entfernen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --uninstall
```

BELABOX-Client entfernen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --uninstall
```

Reboot nach Installation:

```bash
--reboot      # automatisch neu starten
--no-reboot   # Reboot-Abfrage überspringen
```

### Troubleshooting

VPS prüfen:

```bash
belabox-remote-vps-status
systemctl status belabox-remote-ui-chisel.service
systemctl status nginx
```

BELABOX prüfen:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
systemctl status belabox-vps-remote-ui-proxy.service
journalctl -u belabox-vps-remote-ui-tunnel.service -n 80 --no-pager
```

Wenn du nur die Nginx-Startseite siehst, das VPS-Script erneut ausführen und Nginx neu starten:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile DEIN_PROFILNAME --no-reboot
sudo nginx -t
sudo systemctl restart nginx
```

### Sicherheit

- SSH zwischen BELABOX und VPS wird nicht genutzt.
- Der offizielle BELABOX-Remote-Key bleibt unverändert.
- Jede BELABOX bekommt eigenen Link, eigenen Token und eigenen internen VPS-Port.
- Ohne Cookie oder gültigen `?token=`-Parameter zeigt die VPS-IP nicht auf eine BELABOX-UI.
- Die BELABOX-UI bleibt zusätzlich durch ihr eigenes UI-Passwort geschützt.
- Ohne HTTPS ist die Browser-Verbindung zum VPS unverschlüsselt.

### Lizenz

Dieses Projekt steht unter der GNU General Public License v3.0, passend zu BELABOX/belaUI. Details stehen in [LICENSE](LICENSE).

## English

### Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Multiple BELABOX Units](#multiple-belabox-units)
- [Usage](#usage)
- [Management](#management)
- [Troubleshooting](#troubleshooting-1)
- [License](#license)

### Overview

BelaRemoteUI uses two scripts:

| Script | Runs on | Purpose |
| --- | --- | --- |
| `belabox-vps-remote-server.sh` | VPS | Nginx, Chisel server, profiles, fixed remote URLs |
| `belabox-vps-remote-client.sh` | BELABOX | Local proxy and outgoing Chisel tunnel |

Each BELABOX profile gets its own remote URL, widget token, Chisel token, and internal VPS port. Multiple BELABOX units can therefore share one VPS safely.

### Requirements

- VPS with Ubuntu 24.04 or Ubuntu 26.04
- Root or sudo access on VPS and BELABOX
- Reachable VPS ports: HTTP `80` or the printed port, Chisel `9090`, SSH management port
- BELABOX with terminal or SSH access

If an existing RTMP Nginx configuration is detected, BelaRemoteUI automatically uses HTTP port `8088` unless you explicitly set `--public-port`.

### Quick Start

Run on the VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile YOUR_PROFILE_NAME
```

Then copy the complete BELABOX command printed by the VPS script and run it on the matching BELABOX.

### Multiple BELABOX Units

Create another profile on the same VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile ANOTHER_PROFILE_NAME
```

Show profiles:

```bash
belabox-remote-vps-status
```

### Usage

Browser:

```text
http://158.180.35.14/r/YOUR_PROFILE_NAME/0b9a8c7d6e5f4a3b2c1d/
```

Widget/API:

```text
http://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
```

### Management

Show VPS profiles:

```bash
belabox-remote-vps-status
```

Show the remote link on the BELABOX:

```bash
belabox-vps-remote-link
```

Delete one VPS profile:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --delete-profile YOUR_PROFILE_NAME
```

Remove the VPS installation:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --uninstall
```

Remove the BELABOX client:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --uninstall
```

### Troubleshooting

VPS:

```bash
belabox-remote-vps-status
systemctl status belabox-remote-ui-chisel.service
systemctl status nginx
```

BELABOX:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
systemctl status belabox-vps-remote-ui-proxy.service
journalctl -u belabox-vps-remote-ui-tunnel.service -n 80 --no-pager
```

### Security Notes

- SSH between BELABOX and VPS is not used.
- The official BELABOX remote key remains unchanged.
- Each BELABOX gets its own link, token, and internal VPS port.
- Without HTTPS, browser traffic to the VPS is not encrypted.

### License

This project is licensed under the GNU General Public License v3.0, matching BELABOX/belaUI. See [LICENSE](LICENSE).
