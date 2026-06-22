# BelaRemoteUI

Fester, selbst gehosteter Remote-Zugriff auf die BELABOX-Weboberfläche über deinen eigenen VPS.

Der offizielle BELABOX-Remote-Key wird nicht benutzt, nicht überschrieben und nicht verändert. Die BELABOX baut nur eine ausgehende Chisel-Verbindung zu deinem VPS auf. SSH zwischen BELABOX und VPS wird für den Remote-Zugang nicht benötigt.

## Deutsch

### Was BelaRemoteUI macht

BelaRemoteUI besteht aus zwei Installationsscripts:

- `belabox-vps-remote-server.sh` läuft auf deinem VPS.
- `belabox-vps-remote-client.sh` läuft auf der BELABOX.

Der VPS erzeugt automatisch:

- eine feste geheime Remote-URL, zum Beispiel `http://158.180.35.14/r/0b9a8c7d6e5f4a3b2c1d/`
- einen Chisel-Tunnel-Token, zum Beispiel `belabox:abc123...`

Beim Aufruf der geheimen URL setzt der VPS ein Cookie und leitet danach auf `/` weiter. Dadurch funktionieren absolute Pfade der BELABOX-UI wie bei `belabox.local`, ohne dass die reine VPS-IP direkt offen ist.

### Voraussetzungen

- Eine BELABOX mit Terminal- oder SSH-Zugriff.
- Ein VPS mit Ubuntu 24.04 oder Ubuntu 26.04.
- Root- oder sudo-Zugriff auf dem VPS.
- Root- oder sudo-Zugriff auf der BELABOX.
- Auf dem VPS müssen TCP-Port `80`, der Chisel-Port `9090` und dein normaler SSH-Management-Port erreichbar sein.

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

Am Ende zeigt das Script die feste Remote-URL, den Chisel-Port und den kompletten BELABOX-Befehl an.

#### 2. BELABOX verbinden

Nutze auf der BELABOX am besten genau den Befehl, den das VPS-Script ausgibt. Er sieht ungefähr so aus:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14 --tunnel-server-port 9090 --tunnel-auth belabox:DEIN_TOKEN --public-url http://158.180.35.14/r/DEIN_LINK/
```

Du kannst das BELABOX-Script auch ohne Parameter starten. Dann fragt es VPS-IP, Tunnel-Token und Remote-URL ab:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash
```

### Nutzung

Nach erfolgreicher Installation öffnest du die geheime Remote-URL aus dem VPS-Script, zum Beispiel:

```text
http://158.180.35.14/r/0b9a8c7d6e5f4a3b2c1d/
```

Der Browser wird danach auf `http://158.180.35.14/` weitergeleitet. Das ist normal: Die geheime URL hat vorher das Zugangs-Cookie gesetzt. Ohne dieses Cookie liefert die reine VPS-IP nur `404`.

### Link erneut anzeigen

Auf der BELABOX:

```bash
belabox-vps-remote-link
```

Auf dem VPS:

```bash
cat /etc/belabox-remote-ui/public_url
cat /etc/belabox-remote-ui/tunnel_auth
```

### Neuen geheimen Link erzeugen

Nur auf dem VPS ausführen, wenn du wirklich einen neuen Linkpfad möchtest:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --regenerate-link
```

Danach das BELABOX-Client-Script erneut mit dem vom VPS ausgegebenen Befehl starten.

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
Browser
  -> geheime URL auf dem VPS
  -> VPS setzt Cookie und leitet auf / weiter
  -> Nginx auf dem VPS
  -> 127.0.0.1:18080 auf dem VPS
  -> Chisel-Reverse-Tunnel
  -> lokaler Proxy auf der BELABOX
  -> lokale BELABOX-UI auf 127.0.0.1:80/8080/81
```

### Sicherheit

- SSH zwischen BELABOX und VPS wird nicht genutzt.
- Der offizielle BELABOX-Remote-Key bleibt unverändert.
- Die öffentliche URL enthält einen zufällig generierten geheimen Pfad.
- Die reine VPS-IP zeigt ohne Cookie nicht direkt auf die BELABOX-UI.
- Der Chisel-Tunnel nutzt einen zufällig generierten Token.
- Die BELABOX-UI bleibt zusätzlich durch ihr eigenes UI-Passwort geschützt.
- Bei Zugriff per reiner IP ist der Weg vom Browser zum VPS nur HTTP. Für echte Verschlüsselung solltest du eine Domain nutzen und später HTTPS auf dem VPS aktivieren.

### Dateien

| Datei | Zweck |
| --- | --- |
| `belabox-vps-remote-server.sh` | Installiert den VPS-Empfänger mit Nginx, geheimem Linkpfad, Cookie-Gate und Chisel-Server. |
| `belabox-vps-remote-client.sh` | Installiert den BELABOX-Client mit lokalem Proxy und dauerhaftem Chisel-Reverse-Tunnel. |

## English

### What BelaRemoteUI Does

BelaRemoteUI provides fixed, self-hosted remote access to the BELABOX web UI through your own VPS.

It does not use, overwrite, or modify the official BELABOX remote key. The BELABOX only opens an outgoing Chisel connection to your VPS. SSH between the BELABOX and the VPS is not required for remote access.

The VPS automatically creates:

- a fixed secret remote URL, for example `http://158.180.35.14/r/0b9a8c7d6e5f4a3b2c1d/`
- a Chisel tunnel token, for example `belabox:abc123...`

When the secret URL is opened, the VPS sets an access cookie and redirects to `/`. This lets the BELABOX UI behave like it does on `belabox.local`, even when the UI uses absolute paths.

### Requirements

- A BELABOX with terminal or SSH access.
- A VPS running Ubuntu 24.04 or Ubuntu 26.04.
- Root or sudo access on the VPS.
- Root or sudo access on the BELABOX.
- TCP port `80`, the Chisel port `9090`, and your normal SSH management port must be reachable on the VPS.

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

The script prints the fixed remote URL, the Chisel port, the tunnel token, and the exact BELABOX command.

#### 2. Connect the BELABOX

Run the command printed by the VPS script. It looks like this:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14 --tunnel-server-port 9090 --tunnel-auth belabox:YOUR_TOKEN --public-url http://158.180.35.14/r/YOUR_LINK/
```

You can also start the BELABOX installer without parameters. It will ask for the VPS IP, tunnel token, and remote URL:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash
```

### Usage

Open the secret remote URL printed by the VPS script, for example:

```text
http://158.180.35.14/r/0b9a8c7d6e5f4a3b2c1d/
```

The browser is then redirected to `http://158.180.35.14/`. That is expected: the secret URL already set the access cookie. Without that cookie, the bare VPS IP returns `404`.

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
Browser
  -> secret URL on the VPS
  -> VPS sets a cookie and redirects to /
  -> Nginx on the VPS
  -> 127.0.0.1:18080 on the VPS
  -> Chisel reverse tunnel
  -> local proxy on the BELABOX
  -> local BELABOX UI on 127.0.0.1:80/8080/81
```

### Security Notes

- SSH between BELABOX and VPS is not used.
- The official BELABOX remote key remains unchanged.
- The public URL includes a generated random secret path.
- The bare VPS IP does not expose the BELABOX UI without the access cookie.
- The Chisel tunnel uses a generated token.
- The BELABOX UI is still protected by its own UI password.
- Plain IP access uses HTTP between browser and VPS. Use a domain and add HTTPS later if you need transport encryption.
