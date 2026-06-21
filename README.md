# BELABOX VPS Remote UI

Eine kleine Zwei-Script-Loesung, um die lokale BELABOX-Weboberflaeche ueber eine feste VPS-URL erreichbar zu machen.

Der offizielle BELABOX `remote key` wird dabei nicht benutzt, nicht ueberschrieben und nicht veraendert. Die BELABOX baut nur einen ausgehenden Reverse-SSH-Tunnel zu deinem VPS auf. Der VPS nimmt die oeffentliche Anfrage per Nginx an und leitet sie durch diesen Tunnel zur lokalen BELABOX-UI weiter.

## Was du brauchst

- Eine BELABOX mit SSH-Zugriff.
- Einen VPS mit Ubuntu 24.04 oder Ubuntu 26.04.
- Root- oder sudo-Zugriff auf den VPS.
- Root- oder sudo-Zugriff auf der BELABOX.

## Dateien

| Datei | Zweck |
| --- | --- |
| `belabox-vps-remote-server.sh` | Wird auf dem VPS ausgefuehrt und richtet Nginx, SSH-Tunnel-User und Firewall ein. |
| `belabox-vps-remote-client.sh` | Wird auf der BELABOX ausgefuehrt und baut den dauerhaften Reverse-SSH-Tunnel zum VPS auf. |
| `belabox-remote-ui-tunnel.sh` | Alternative Quick-Tunnel-Variante mit wechselnder URL. Fuer feste URLs normalerweise nicht nutzen. |

## Schnellstart

### 1. VPS vorbereiten

Kopiere `belabox-vps-remote-server.sh` auf den VPS und fuehre es dort aus:

```bash
sudo bash belabox-vps-remote-server.sh
```

Optional mit Domain:

```bash
sudo bash belabox-vps-remote-server.sh --domain belabox.example.com
```

Wenn alles fertig ist, zeigt das Script die feste Remote-URL an, zum Beispiel:

```text
http://158.180.35.14/
```

### 2. BELABOX verbinden

Kopiere `belabox-vps-remote-client.sh` auf die BELABOX und starte es:

```bash
sudo bash belabox-vps-remote-client.sh
```

Das Script fragt waehrend der Installation nach der VPS-IP oder Domain:

```text
VPS-IP oder Domain:
```

Beispiel:

```text
158.180.35.14
```

Danach richtet das Script den lokalen Proxy, den SSH-Key und den dauerhaften Tunnel ein. Falls gefragt, gib das Passwort oder den SSH-Key-Zugriff fuer den Admin-User des VPS ein.

Die nicht-interaktive Variante geht weiterhin:

```bash
sudo bash belabox-vps-remote-client.sh --vps 158.180.35.14
```

Mit eigener sichtbarer URL:

```bash
sudo bash belabox-vps-remote-client.sh --vps 158.180.35.14 --public-url http://158.180.35.14/
```

## Nutzung

Nach erfolgreicher Installation erreichst du die BELABOX-UI ueber die feste URL:

```text
http://DEINE-VPS-IP/
```

Oder, wenn du eine Domain auf den VPS zeigen laesst:

```text
http://deine-domain.tld/
```

Den Link auf der BELABOX erneut anzeigen:

```bash
belabox-vps-remote-link
```

Status auf der BELABOX pruefen:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
systemctl status belabox-vps-remote-ui-proxy.service
```

Status auf dem VPS pruefen:

```bash
belabox-remote-vps-status
systemctl status nginx
```

## Wie es funktioniert

```text
Browser
  -> http://VPS-IP/
  -> Nginx auf dem VPS
  -> 127.0.0.1:18080 auf dem VPS
  -> Reverse-SSH-Tunnel
  -> lokaler Proxy auf der BELABOX
  -> lokale BELABOX-UI auf 127.0.0.1:80/8080/81
```

Der lokale Proxy auf der BELABOX ist noetig, weil die BELABOX-UI ihre WebSocket-Verbindung im Original hart als `ws://` aufbaut. Der Proxy leitet HTTP und WebSocket weiter und macht die UI tunnel-tauglich, ohne die Originaldateien der BELABOX-UI zu veraendern.

## Dienste

Auf dem VPS:

- `nginx`
- SSH-Konfiguration fuer den User `belabox-tunnel`

Auf der BELABOX:

- `belabox-vps-remote-ui-proxy.service`
- `belabox-vps-remote-ui-tunnel.service`

## Stoppen und Starten

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

Automatischen Start wieder aktivieren:

```bash
sudo systemctl enable belabox-vps-remote-ui-proxy.service
sudo systemctl enable belabox-vps-remote-ui-tunnel.service
```

## Sicherheit

- Der offizielle BELABOX `remote key` bleibt unveraendert.
- Der Tunnel-User auf dem VPS hat kein Passwort-Login.
- Der SSH-Key der BELABOX wird mit `permitlisten` auf den benoetigten Reverse-Tunnel-Port beschraenkt.
- Die BELABOX-UI bleibt weiterhin durch ihr eigenes UI-Passwort geschuetzt.
- Bei Zugriff per reiner IP ist der Weg vom Browser zum VPS nur HTTP. Fuer echte Verschluesselung solltest du eine Domain nutzen und spaeter HTTPS auf dem VPS aktivieren.

## Option: Domain und HTTPS

Wenn eine Domain auf deinen VPS zeigt, kannst du den Server so installieren:

```bash
sudo bash belabox-vps-remote-server.sh --domain belabox.example.com
```

HTTPS ist im aktuellen Script bewusst nicht automatisch eingebaut, weil dafuer eine echte Domain mit korrektem DNS noetig ist. Wenn DNS gesetzt ist, kann spaeter ein Let's-Encrypt-Setup mit Nginx ergaenzt werden.

## Troubleshooting

### Die URL zeigt noch nicht auf die BELABOX

Auf dem VPS:

```bash
belabox-remote-vps-status
```

Auf der BELABOX:

```bash
systemctl status belabox-vps-remote-ui-tunnel.service
journalctl -u belabox-vps-remote-ui-tunnel.service -n 80 --no-pager
```

### SSH-Key konnte nicht automatisch eingetragen werden

Starte das BELABOX-Script mit:

```bash
sudo bash belabox-vps-remote-client.sh --skip-key-install
```

Das Script zeigt dann den Public Key an. Diesen Key auf dem VPS beim User `belabox-tunnel` in `authorized_keys` eintragen.

### BELABOX-UI lokal nicht gefunden

Auf der BELABOX pruefen:

```bash
systemctl status belaUI.service
systemctl status belaUI.socket
```

Das Client-Script testet automatisch die lokalen Ports `80`, `8080` und `81`.

## Hinweis

Nutze diese Scripts nur fuer eigene BELABOX-Systeme und eigene VPS-Server. Die oeffentliche URL ist fest und damit nicht geheim. Verwende daher ein starkes Passwort fuer die BELABOX-UI.
