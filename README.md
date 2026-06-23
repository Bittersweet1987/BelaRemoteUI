# BelaRemoteUI

Self-hosted remote access to one or more BELABOX web UIs through your own VPS.

The official BELABOX remote key is not used, overwritten, or modified. Each BELABOX opens only an outgoing Chisel tunnel to your VPS; SSH between BELABOX and VPS is not required.

## Deutsch

### Inhalt

- [Kurzüberblick](#kurzüberblick)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Mehrere BELABOXen](#mehrere-belaboxen)
- [Nutzung](#nutzung)
- [Verwaltung](#verwaltung)
- [Fehlerbehebung](#fehlerbehebung)
- [Sicherheit](#sicherheit)
- [Lizenz](#lizenz)

### Kurzüberblick

BelaRemoteUI richtet auf deinem VPS einen eigenen Remote-Zugang zur BELABOX-Weboberfläche ein. Die BELABOX baut dabei nur eine ausgehende Verbindung zum VPS auf. Dadurch muss auf der BELABOX kein Port geöffnet werden, und der offizielle BELABOX-Remote-Key bleibt unangetastet.

Es gibt zwei Scripts:

| Script | Läuft auf | Aufgabe |
| --- | --- | --- |
| `belabox-vps-remote-server.sh` | VPS | Nginx, Chisel-Server, feste URLs und Profilverwaltung |
| `belabox-vps-remote-client.sh` | BELABOX | Lokaler Proxy und ausgehender Chisel-Tunnel |

Pro BELABOX-Profil erzeugt der VPS:

| Wert | Beispiel |
| --- | --- |
| Browser-Link | `http://158.180.35.14/r/DEIN_PROFILNAME/0b9a.../` |
| Widget/API-Link | `http://158.180.35.14/?token=0b9a...` |
| WebSocket-Link | `ws://158.180.35.14/?token=0b9a...` |
| Tunnel-Token | `DEIN_PROFILNAME:abc123...` |
| Interner VPS-Port | `18080`, `18081`, `18082` |

### Voraussetzungen

- VPS mit Ubuntu 24.04 oder Ubuntu 26.04
- Root- oder sudo-Zugriff auf VPS und BELABOX
- BELABOX mit Terminal- oder SSH-Zugriff
- Auf dem VPS offen: HTTP-Port `80` oder der ausgegebene Ersatzport, Chisel-Port `9090`, normaler SSH-Management-Port

Wenn auf dem VPS bereits Nginx oder eine RTMP-Nginx-Konfiguration vorhanden ist, weicht BelaRemoteUI automatisch auf HTTP-Port `8088` aus. Vorhandene Nginx-Dateien wie `sites-enabled/default` bleiben dann unangetastet. Wenn du bewusst einen anderen HTTP-Port möchtest, kannst du später `--public-port PORT` verwenden.

BelaRemoteUI aktiviert UFW nicht automatisch. Falls UFW bereits aktiv ist, ergänzt das Script nur fehlende BelaRemoteUI-Regeln für den HTTP-Port und den Chisel-Port. Bereits vorhandene Regeln werden nicht überschrieben und nicht als BelaRemoteUI-Regeln markiert. Bei einer kompletten Deinstallation werden nur die Regeln entfernt, die BelaRemoteUI selbst neu angelegt hat.

Bestehende Dienste wie RTMP auf `1935/tcp`, eine Statistikseite auf `8080/tcp` oder andere eigene Ports bleiben deine eigenen Firewall-Regeln und werden nicht verändert.

### Installation

#### 1. VPS vorbereiten

Auf dem VPS ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
```

Das Script fragt nach einem Profilnamen. Dieser Name dient nur zur Verwaltung auf dem VPS, zum Beispiel `kamera1`, `eventbox` oder `rucksack`.

Nach der Installation zeigt das VPS-Script alle wichtigen Daten an:

- feste Remote-URL
- Widget/API-URL
- WebSocket-URL
- Chisel-Tunnel-Port
- Tunnel-Token
- kompletter Installationsbefehl für die BELABOX

#### 2. BELABOX verbinden

Kopiere den kompletten Befehl aus der VPS-Ausgabe und führe genau diesen auf der passenden BELABOX aus.

Er sieht ungefähr so aus:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --vps 158.180.35.14 --tunnel-server-port 9090 --tunnel-auth DEIN_PROFILNAME:DEIN_TOKEN --remote-port 18080 --public-url http://158.180.35.14/r/DEIN_PROFILNAME/DEIN_LINK/
```

Das BELABOX-Script installiert fehlende Pakete wie `curl`, `nodejs`, `gzip` und Chisel. Danach richtet es den lokalen Proxy ein und startet den dauerhaften Tunnel zum VPS.

#### 3. Neustart

Beide Scripts fragen am Ende, ob das jeweilige System neu gestartet werden soll. Du kannst das Verhalten auch direkt setzen:

```bash
--reboot      # automatisch neu starten
--no-reboot   # Reboot-Abfrage überspringen
```

### Mehrere BELABOXen

Für jede weitere BELABOX startest du das VPS-Script erneut und gibst einen neuen Profilnamen ein:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
```

Danach kopierst du wieder den neu ausgegebenen BELABOX-Befehl auf die zweite BELABOX. Jedes Profil bekommt einen eigenen Link, eigenen Token und eigenen internen VPS-Port.

Profile anzeigen:

```bash
belabox-remote-vps-status
```

Neuen Link für ein bestehendes Profil erzeugen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --regenerate-link
```

Das Script fragt dabei wieder nach dem Profilnamen.

### Nutzung

Für normale Browser-Nutzung nimmst du die feste Remote-URL aus der VPS-Ausgabe:

```text
http://158.180.35.14/r/DEIN_PROFILNAME/0b9a8c7d6e5f4a3b2c1d/
```

Der Browser wird danach auf `/` weitergeleitet. Das ist normal: Die geheime URL setzt vorher ein Cookie, damit CSS, JavaScript und WebSockets wie bei `belabox.local` funktionieren.

Für externe Widgets oder Hintergrund-Anfragen kannst du den Token direkt in der URL nutzen:

```text
http://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
ws://158.180.35.14/?token=0b9a8c7d6e5f4a3b2c1d
```

Wenn BelaRemoteUI wegen RTMP auf Port `8088` ausweicht:

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

Ein VPS-Profil löschen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --delete-profile DEIN_PROFILNAME
```

Komplette VPS-Installation entfernen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --uninstall
```

BELABOX-Client entfernen:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh | sudo bash -s -- --uninstall
```

Die Löschroutinen entfernen nur BelaRemoteUI-Dateien, Services, eigene Nginx-Dateien und von BelaRemoteUI selbst neu angelegte UFW-Regeln. BELABOX-UI, offizieller Remote-Key, fremde RTMP/Nginx-Konfigurationen und bereits vorher vorhandene Firewall-Regeln bleiben unangetastet.

### Fehlerbehebung

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

Wenn nur die Nginx-Startseite erscheint, die VPS-Konfiguration neu schreiben und Nginx neu starten:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --no-reboot
sudo nginx -t
sudo systemctl restart nginx
```

Wenn der Browser `502 Bad Gateway` zeigt, ist Nginx erreichbar, aber der Tunnel zur BELABOX ist nicht verbunden. Prüfe dann auf der BELABOX:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
journalctl -u belabox-vps-remote-ui-tunnel.service -n 80 --no-pager
```

Wenn RTMP oder eine bestehende Statistikseite nach einem alten Installationsversuch nicht mehr erreichbar ist, prüfe zuerst UFW:

```bash
sudo ufw status
sudo ufw allow 1935/tcp
sudo ufw allow 8080/tcp
```

Wenn du UFW vorher gar nicht nutzen wolltest:

```bash
sudo ufw disable
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

### Overview

BelaRemoteUI provides fixed, self-hosted remote access to one or more BELABOX web UIs through your own VPS.

It uses two scripts:

| Script | Runs on | Purpose |
| --- | --- | --- |
| `belabox-vps-remote-server.sh` | VPS | Nginx, Chisel server, profiles, fixed URLs |
| `belabox-vps-remote-client.sh` | BELABOX | Local proxy and outgoing Chisel tunnel |

Each BELABOX profile gets its own URL, token, and internal VPS port. The official BELABOX remote key is not used or modified.

### Quick Start

Run this on the VPS and enter a profile name when asked:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
```

Then copy the complete BELABOX command printed by the VPS script and run it on the matching BELABOX.

### Multiple BELABOX Units

Run the VPS script again and enter a new profile name:

```bash
curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
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

### License

This project is licensed under the GNU General Public License v3.0, matching BELABOX/belaUI. See [LICENSE](LICENSE).
