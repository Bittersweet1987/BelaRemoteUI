# BelaRemoteUI

Fester, selbst gehosteter Remote-Zugriff auf die BELABOX-Weboberfläche über deinen eigenen VPS.

Der offizielle BELABOX-Remote-Key wird nicht benutzt, nicht überschrieben und nicht verändert. Die BELABOX baut nur einen ausgehenden Reverse-SSH-Tunnel zu deinem VPS auf. Der VPS stellt eine feste URL bereit und leitet sie zur lokalen BELABOX-UI weiter.

## Deutsch

### Was BelaRemoteUI macht

BelaRemoteUI besteht aus zwei Installationsscripts:

- `belabox-vps-remote-server.sh` läuft auf deinem VPS.
- `belabox-vps-remote-client.sh` läuft auf der BELABOX.

Der VPS erzeugt automatisch einen festen, zufälligen Linkpfad, zum Beispiel:

```text
http://158.180.35.14/r/0b9a8c7d6e5f4a3b2c1d/
```

Nur dieser komplette Link führt zur BELABOX-UI. Die reine VPS-IP zeigt absichtlich nicht direkt auf die UI.

Der Link bleibt gleich, auch nach Neustarts. Er ändert sich nur, wenn du auf dem VPS bewusst einen neuen Link erzeugst.

### Voraussetzungen

- Eine BELABOX mit SSH-Zugriff.
- Ein VPS mit Ubuntu 24.04 oder Ubuntu 26.04.
- Root- oder sudo-Zugriff auf dem VPS.
- Root- oder sudo-Zugriff auf der BELABOX.

### Schnellstart

#### 1. VPS vorbereiten

Auf dem VPS ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
```

Optional mit Domain:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --domain belabox.example.com
```

Am Ende zeigt das Script die feste Remote-URL an. Diese URL enthält bereits den zufällig generierten Pfad.

#### 2. BELABOX verbinden

Auf der BELABOX ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash
```

Das Script fragt während der Installation nach der VPS-IP oder Domain:

```text
VPS-IP oder Domain:
```

Beispiel:

```text
158.180.35.14
```

Danach trägt das Script den Tunnel-Key auf dem VPS ein, holt die komplette generierte Remote-URL vom VPS und zeigt genau diesen Link am Ende an.

Nicht-interaktiv geht es auch:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14
```

### Link erneut anzeigen

Auf der BELABOX:

```bash
belabox-vps-remote-link
```

Auf dem VPS:

```bash
cat /etc/belabox-remote-ui/public_url
```

### Neuen Link erzeugen

Nur auf dem VPS ausführen, wenn du wirklich einen neuen geheimen Linkpfad möchtest:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --regenerate-link
```

Danach das BELABOX-Client-Script erneut starten, damit die BELABOX die neue URL übernimmt:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash
```

### Status prüfen

Auf dem VPS:

```bash
belabox-remote-vps-status
systemctl status nginx
```

Auf der BELABOX:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
systemctl status belabox-vps-remote-ui-proxy.service
```

### Stoppen und Starten

Tunnel auf der BELABOX stoppen:

```bash
sudo systemctl stop belabox-vps-remote-ui-tunnel.service
```

Tunnel wieder starten:

```bash
sudo systemctl start belabox-vps-remote-ui-tunnel.service
```

Automatischen Start deaktivieren:

```bash
sudo systemctl disable belabox-vps-remote-ui-tunnel.service
sudo systemctl disable belabox-vps-remote-ui-proxy.service
```

### Wie es funktioniert

```text
Browser
  -> http://VPS-IP/r/zufälliger-pfad/
  -> Nginx auf dem VPS
  -> 127.0.0.1:18080 auf dem VPS
  -> Reverse-SSH-Tunnel
  -> lokaler Proxy auf der BELABOX
  -> lokale BELABOX-UI auf 127.0.0.1:80/8080/81
```

Der lokale Proxy auf der BELABOX ist nötig, weil die BELABOX-UI ihre WebSocket-Verbindung im Original als `ws://` aufbaut. Der Proxy macht HTTP und WebSocket für den Remote-Pfad passend, ohne die Originaldateien der BELABOX-UI zu verändern.

### Sicherheit

- Der offizielle BELABOX-Remote-Key bleibt unverändert.
- Die öffentliche URL enthält einen zufällig generierten geheimen Pfad.
- Die reine VPS-IP zeigt nicht direkt auf die BELABOX-UI.
- Der Tunnel-User auf dem VPS hat kein Passwort-Login.
- Der SSH-Key der BELABOX wird auf den benötigten Reverse-Tunnel-Port beschränkt.
- Die BELABOX-UI bleibt zusätzlich durch ihr eigenes UI-Passwort geschützt.
- Bei Zugriff per reiner IP ist der Weg vom Browser zum VPS nur HTTP. Für echte Verschlüsselung solltest du eine Domain nutzen und später HTTPS auf dem VPS aktivieren.

### Hinweise zu `--skip-key-install`

Wenn du den SSH-Key nicht automatisch eintragen möchtest, kannst du auf der BELABOX nutzen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --skip-key-install --public-url http://DEINE-VPS-IP/r/DEIN-PFAD/
```

Ohne automatisches Eintragen kann das Script die generierte URL nicht selbst vom VPS lesen. Gib sie dann mit `--public-url` an.

### Dateien

| Datei | Zweck |
| --- | --- |
| `belabox-vps-remote-server.sh` | Installiert den VPS-Empfänger mit Nginx, geheimem Linkpfad und SSH-Tunnel-User. |
| `belabox-vps-remote-client.sh` | Installiert den BELABOX-Client mit lokalem Proxy und dauerhaftem Reverse-SSH-Tunnel. |

## English

### What BelaRemoteUI does

BelaRemoteUI provides fixed, self-hosted remote access to the BELABOX web UI through your own VPS.

It does not use, overwrite, or modify the official BELABOX remote key. The BELABOX only opens an outgoing reverse SSH tunnel to your VPS. The VPS exposes a fixed URL and forwards it through that tunnel to the local BELABOX UI.

The VPS automatically creates a fixed random URL path, for example:

```text
http://158.180.35.14/r/0b9a8c7d6e5f4a3b2c1d/
```

Only the full generated URL reaches the BELABOX UI. The bare VPS IP intentionally does not expose the UI.

### Requirements

- A BELABOX with SSH access.
- A VPS running Ubuntu 24.04 or Ubuntu 26.04.
- Root or sudo access on the VPS.
- Root or sudo access on the BELABOX.

### Quick Start

#### 1. Prepare the VPS

Run this on the VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
```

Optional with a domain:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --domain belabox.example.com
```

The script prints the fixed remote URL at the end, including the generated random path.

#### 2. Connect the BELABOX

Run this on the BELABOX:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash
```

The installer asks for the VPS IP or domain:

```text
VPS-IP oder Domain:
```

Example:

```text
158.180.35.14
```

The script installs the tunnel key on the VPS, reads the generated remote URL from the VPS, and prints that full link at the end.

Non-interactive usage:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14
```

### Show the Link Again

On the BELABOX:

```bash
belabox-vps-remote-link
```

On the VPS:

```bash
cat /etc/belabox-remote-ui/public_url
```

### Generate a New Link

Run this on the VPS only when you intentionally want a new random URL path:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --regenerate-link
```

Then run the BELABOX client installer again so the BELABOX stores the new URL:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash
```

### Status

On the VPS:

```bash
belabox-remote-vps-status
systemctl status nginx
```

On the BELABOX:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
systemctl status belabox-vps-remote-ui-proxy.service
```

### How It Works

```text
Browser
  -> http://VPS-IP/r/random-path/
  -> Nginx on the VPS
  -> 127.0.0.1:18080 on the VPS
  -> reverse SSH tunnel
  -> local proxy on the BELABOX
  -> local BELABOX UI on 127.0.0.1:80/8080/81
```

The local proxy is required because the original BELABOX UI creates its WebSocket connection as `ws://`. The proxy makes HTTP and WebSocket work correctly under the remote path without modifying the original BELABOX UI files.

### Security Notes

- The official BELABOX remote key remains unchanged.
- The public URL includes a generated random secret path.
- The bare VPS IP does not expose the BELABOX UI.
- The VPS tunnel user has no password login.
- The BELABOX SSH key is restricted to the required reverse tunnel port.
- The BELABOX UI is still protected by its own UI password.
- Plain IP access uses HTTP between browser and VPS. Use a domain and add HTTPS later if you need transport encryption.
