# BelaRemoteUI

Fester, selbst gehosteter Remote-Zugriff auf eine oder mehrere BELABOX-Weboberflächen über deinen eigenen VPS.

Der offizielle BELABOX-Remote-Key wird nicht benutzt, nicht überschrieben und nicht verändert. Die BELABOX baut nur eine ausgehende Chisel-Verbindung zu deinem VPS auf. SSH zwischen BELABOX und VPS wird für den Remote-Zugang nicht benötigt.

## Deutsch

### Was BelaRemoteUI macht

BelaRemoteUI besteht aus zwei Installationsscripts:

- `belabox-vps-remote-server.sh` läuft auf deinem VPS.
- `belabox-vps-remote-client.sh` läuft auf der jeweiligen BELABOX.

Der VPS erzeugt pro BELABOX ein eigenes Profil mit:

- einer festen geheimen Remote-URL, zum Beispiel `http://158.180.35.14/r/belabox1/0b9a8c7d6e5f4a3b2c1d/`
- einem eigenen Chisel-Tunnel-Token, zum Beispiel `belabox1:abc123...`
- einem eigenen internen VPS-Port, zum Beispiel `18080`, `18081`, `18082`

Dadurch können mehrere BELABOXen parallel über denselben VPS laufen, ohne denselben Link oder denselben Tunnel-Port zu teilen.

Beim Browser-Aufruf der geheimen URL setzt der VPS ein Cookie und leitet danach auf `/` weiter. Dadurch funktionieren absolute Pfade der BELABOX-UI wie bei `belabox.local`. Für externe Widgets oder Hintergrund-Anfragen kann derselbe geheime Token zusätzlich als URL-Parameter genutzt werden, zum Beispiel `http://158.180.35.14/?token=DEIN_LINK` oder `ws://158.180.35.14/?token=DEIN_LINK`.

### Voraussetzungen

- Eine oder mehrere BELABOXen mit Terminal- oder SSH-Zugriff.
- Ein VPS mit Ubuntu 24.04 oder Ubuntu 26.04.
- Root- oder sudo-Zugriff auf dem VPS.
- Root- oder sudo-Zugriff auf jeder BELABOX.
- Auf dem VPS müssen TCP-Port `80` oder der ausgegebene HTTP-Port, der Chisel-Port `9090` und dein normaler SSH-Management-Port erreichbar sein.

Wenn auf dem VPS bereits eine RTMP-Nginx-Konfiguration erkannt wird, weicht BelaRemoteUI automatisch auf HTTP-Port `8088` aus, solange du nicht explizit `--public-port` setzt. So wird eine vorhandene RTMP-Konfiguration nicht überschrieben oder aus dem Weg geräumt.

### Schnellstart

#### 1. VPS vorbereiten

Auf dem VPS ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
```

Das Script fragt nach einem Profilnamen, zum Beispiel `belabox1`.

Optional direkt mit Profil und Domain:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --domain belabox.example.com
```

Am Ende zeigt das VPS-Script die feste Remote-URL, den Widget-Token, den Chisel-Port, den Tunnel-Token und den kompletten Curl-Befehl für die BELABOX an.

#### 2. BELABOX verbinden

Wichtig: Kopiere den kompletten Curl-Befehl aus der Ausgabe des VPS-Scripts und führe genau diesen auf der passenden BELABOX aus.

Er sieht ungefähr so aus:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14 --tunnel-server-port 9090 --tunnel-auth belabox1:DEIN_TUNNEL_TOKEN --remote-port 18080 --public-url http://158.180.35.14/r/belabox1/DEIN_LINK/
```

Das BELABOX-Script installiert fehlende Pakete inklusive `curl`, `nodejs`, `gzip` und Chisel, richtet den lokalen Proxy ein und baut danach den dauerhaften ausgehenden Tunnel zum VPS auf.

### Mehrere BELABOXen

Für jede weitere BELABOX auf demselben VPS führst du das VPS-Script erneut mit einem neuen Profilnamen aus:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox2
```

Danach kopierst du wieder den ausgegebenen Curl-Befehl auf die zweite BELABOX.

Profile anzeigen:

```bash
belabox-remote-vps-status
```

Einen neuen Link für ein bestehendes Profil erzeugen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --regenerate-link
```

Danach den neu ausgegebenen BELABOX-Befehl auf der zugehörigen BELABOX erneut ausführen.

### Nutzung im Browser

Öffne die geheime Remote-URL aus dem VPS-Script:

```text
http://158.180.35.14/r/belabox1/0b9a8c7d6e5f4a3b2c1d/
```

Der Browser wird danach auf `http://158.180.35.14/` oder, bei RTMP-Ausweichport, auf `http://158.180.35.14:8088/` weitergeleitet. Das ist normal: Die geheime URL hat vorher das Zugangs-Cookie gesetzt.

### Nutzung in externen Widgets

Für ein externes Widget nutzt du den Token direkt in der URL:

```text
http://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
```

Wenn BelaRemoteUI wegen vorhandener RTMP-Nginx-Konfiguration auf Port `8088` ausweicht:

```text
http://158.180.35.14:8088/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14:8088/?token=0b9a8c7d6e5f4a3b2c1d
```

Der Token ist der letzte Teil deiner geheimen Remote-URL.

### Neustart nach Installation

Beide Scripts fragen nach erfolgreicher Installation, ob das jeweilige System neu gestartet werden soll.

Automatisch neu starten:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --reboot
```

Reboot-Abfrage überspringen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --no-reboot
```

Die gleichen Optionen gibt es auch beim BELABOX-Client-Script.

### Löschen und rückgängig machen

Nur ein Profil vom VPS löschen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --delete-profile belabox1
```

Komplette VPS-Installation entfernen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --uninstall
```

BELABOX-Installation entfernen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --uninstall
```

Die Löschroutine entfernt nur BelaRemoteUI-Dienste, Chisel-Binary, lokale BelaRemoteUI-Verzeichnisse und die eigenen Nginx-Dateien. Bestehende BELABOX-UI, offizieller BELABOX-Remote-Key und fremde RTMP/Nginx-Konfigurationen bleiben unangetastet.

### Status prüfen

Auf dem VPS:

```bash
belabox-remote-vps-status
systemctl status belabox-remote-ui-chisel.service
systemctl status nginx
```

Auf der BELABOX:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
systemctl status belabox-vps-remote-ui-proxy.service
journalctl -u belabox-vps-remote-ui-tunnel.service -n 80 --no-pager
```

### Wie es funktioniert

```text
Browser oder Widget
  -> geheime URL mit Cookie oder ?token= auf dem VPS
  -> Nginx auf dem VPS
  -> profilbezogener lokaler VPS-Port, z. B. 127.0.0.1:18080
  -> Chisel-Reverse-Tunnel
  -> lokaler Proxy auf der jeweiligen BELABOX
  -> lokale BELABOX-UI auf 127.0.0.1:80/8080/81
```

### Sicherheit

- SSH zwischen BELABOX und VPS wird nicht genutzt.
- Der offizielle BELABOX-Remote-Key bleibt unverändert.
- Jede BELABOX bekommt einen eigenen geheimen Link und eigenen Chisel-Token.
- Die reine VPS-IP zeigt ohne Cookie oder gültigen `?token=`-Parameter nicht direkt auf eine BELABOX-UI.
- Die BELABOX-UI bleibt zusätzlich durch ihr eigenes UI-Passwort geschützt.
- Bei Zugriff per reiner IP ist der Weg vom Browser zum VPS nur HTTP. Für echte Verschlüsselung solltest du eine Domain nutzen und später HTTPS auf dem VPS aktivieren.

### Dateien

| Datei | Zweck |
| --- | --- |
| `belabox-vps-remote-server.sh` | Installiert und verwaltet den VPS-Empfänger mit Nginx, Multi-Profil-Verwaltung, Cookie-Gate, `?token=`-Zugriff und Chisel-Server. |
| `belabox-vps-remote-client.sh` | Installiert den BELABOX-Client mit lokalem Proxy und dauerhaftem Chisel-Reverse-Tunnel. |

## English

### What BelaRemoteUI Does

BelaRemoteUI provides fixed, self-hosted remote access to one or more BELABOX web UIs through your own VPS.

It does not use, overwrite, or modify the official BELABOX remote key. Each BELABOX only opens an outgoing Chisel connection to your VPS. SSH between the BELABOX and the VPS is not required for remote access.

The VPS creates one profile per BELABOX:

- a fixed secret remote URL, for example `http://158.180.35.14/r/belabox1/0b9a8c7d6e5f4a3b2c1d/`
- a dedicated Chisel tunnel token, for example `belabox1:abc123...`
- a dedicated internal VPS port, for example `18080`, `18081`, `18082`

This allows multiple BELABOX units to use the same VPS without sharing the same URL or tunnel port.

When the secret URL is opened in a browser, the VPS sets an access cookie and redirects to `/`. External widgets or background requests can also pass the same secret token as a URL parameter, for example `http://158.180.35.14/?token=YOUR_LINK` or `ws://158.180.35.14/?token=YOUR_LINK`.

### Requirements

- One or more BELABOX units with terminal or SSH access.
- A VPS running Ubuntu 24.04 or Ubuntu 26.04.
- Root or sudo access on the VPS.
- Root or sudo access on each BELABOX.
- TCP port `80` or the printed HTTP port, the Chisel port `9090`, and your normal SSH management port must be reachable on the VPS.

If an existing RTMP Nginx configuration is detected, BelaRemoteUI automatically uses HTTP port `8088` unless you explicitly set `--public-port`. This avoids overwriting or disturbing existing RTMP/Nginx setups.

### Quick Start

#### 1. Prepare the VPS

Run this on the VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
```

The script asks for a profile name, for example `belabox1`.

Optional with profile and domain:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --domain belabox.example.com
```

At the end, the VPS script prints the fixed remote URL, widget token, Chisel port, tunnel token, and the exact Curl command for the BELABOX.

#### 2. Connect the BELABOX

Important: Copy the complete Curl command printed by the VPS script and run exactly that command on the matching BELABOX.

It looks like this:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14 --tunnel-server-port 9090 --tunnel-auth belabox1:YOUR_TUNNEL_TOKEN --remote-port 18080 --public-url http://158.180.35.14/r/belabox1/YOUR_LINK/
```

The BELABOX script installs missing packages including `curl`, `nodejs`, `gzip`, and Chisel, then creates the local proxy and persistent outgoing tunnel.

### Multiple BELABOX Units

For each additional BELABOX on the same VPS, run the VPS script again with a new profile name:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox2
```

Then copy the newly printed BELABOX Curl command to the second BELABOX.

Show profiles:

```bash
belabox-remote-vps-status
```

Regenerate a link for an existing profile:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --regenerate-link
```

Then run the newly printed BELABOX command again on the matching BELABOX.

### Browser Usage

Open the secret remote URL printed by the VPS script:

```text
http://158.180.35.14/r/belabox1/0b9a8c7d6e5f4a3b2c1d/
```

The browser then redirects to `http://158.180.35.14/` or, when the RTMP fallback port is used, to `http://158.180.35.14:8088/`. That is expected: the secret URL already set the access cookie.

### External Widget Usage

For an external widget, pass the token directly in the URL:

```text
http://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
```

When BelaRemoteUI uses the RTMP fallback port:

```text
http://158.180.35.14:8088/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14:8088/?token=0b9a8c7d6e5f4a3b2c1d
```

The token is the last part of your secret remote URL.

### Reboot After Installation

Both scripts ask whether the system should be rebooted after successful installation.

Automatic reboot:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --reboot
```

Skip the reboot prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox1 --no-reboot
```

The same options are available for the BELABOX client script.

### Uninstall

Delete one VPS profile:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --delete-profile belabox1
```

Remove the complete VPS installation:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --uninstall
```

Remove the BELABOX client installation:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --uninstall
```

The uninstall routine removes only BelaRemoteUI services, the Chisel binary, local BelaRemoteUI directories, and BelaRemoteUI Nginx files. The BELABOX UI, official BELABOX remote key, and unrelated RTMP/Nginx configurations remain untouched.

### Status

On the VPS:

```bash
belabox-remote-vps-status
systemctl status belabox-remote-ui-chisel.service
systemctl status nginx
```

On the BELABOX:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
systemctl status belabox-vps-remote-ui-proxy.service
journalctl -u belabox-vps-remote-ui-tunnel.service -n 80 --no-pager
```

### How It Works

```text
Browser or widget
  -> secret URL with cookie or ?token= on the VPS
  -> Nginx on the VPS
  -> profile-specific local VPS port, e.g. 127.0.0.1:18080
  -> Chisel reverse tunnel
  -> local proxy on the matching BELABOX
  -> local BELABOX UI on 127.0.0.1:80/8080/81
```

### Security Notes

- SSH between BELABOX and VPS is not used.
- The official BELABOX remote key remains unchanged.
- Each BELABOX gets its own secret link and Chisel token.
- The bare VPS IP does not expose a BELABOX UI without the access cookie or a valid `?token=` parameter.
- The BELABOX UI is still protected by its own UI password.
- Plain IP access uses HTTP between browser and VPS. Use a domain and add HTTPS later if you need transport encryption.
