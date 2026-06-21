#!/bin/bash
###############################################################################
# BELABOX Remote UI Tunnel Installer
#
# Erstellt einen kostenlosen, zufaellig generierten Remote-Link zur lokalen
# BELABOX-Weboberflaeche, ohne den bestehenden BELABOX remote key zu aendern.
#
# Technik:
#   - cloudflared Quick Tunnel erzeugt einen https://*.trycloudflare.com Link
#   - ein kleiner lokaler Node.js Proxy macht die BELABOX-WebSocket-Verbindung
#     HTTPS-tauglich, damit die UI ueber den Tunnel sauber funktioniert
###############################################################################
set -euo pipefail

SERVICE_NAME="belabox-remote-ui"
PROXY_SERVICE_NAME="belabox-remote-ui-proxy"
REMOTE_USER="belabox-remote"
INSTALL_DIR="/opt/belabox-remote-ui"
STATE_DIR="/var/lib/belabox-remote-ui"
CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
LINK_HELPER="/usr/local/bin/belabox-remote-link"
PROXY_PORT="18080"
BELABOX_PORTS="80 8080 81"

echo "=== BELABOX Remote UI Tunnel Installer ==="
echo "Dieser Installer veraendert den offiziellen BELABOX remote key nicht."
echo ""

if [ "${EUID}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Starte mit sudo neu..."
    exec sudo bash "$0" "$@"
  fi
  echo "Bitte als root ausfuehren."
  exit 1
fi

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

apt_install_if_missing() {
  local missing=()
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Installiere benoetigte Pakete: ${missing[*]}" >&2
    apt-get update -y -q >&2
    apt-get install -y -q "${missing[@]}" >&2
  fi
}

ensure_downloader() {
  if have_cmd curl || have_cmd wget; then
    return
  fi
  apt_install_if_missing ca-certificates curl
}

download_file() {
  local url="$1"
  local out="$2"

  if have_cmd curl; then
    curl -fsSL "$url" -o "$out"
  elif have_cmd wget; then
    wget -qO "$out" "$url"
  else
    echo "Weder curl noch wget gefunden."
    exit 1
  fi
}

detect_cloudflared_asset() {
  local arch
  arch="$(uname -m)"

  case "$arch" in
    aarch64|arm64)
      echo "cloudflared-linux-arm64"
      ;;
    armv7l|armv6l|armhf|arm)
      echo "cloudflared-linux-arm"
      ;;
    x86_64|amd64)
      echo "cloudflared-linux-amd64"
      ;;
    i386|i686)
      echo "cloudflared-linux-386"
      ;;
    *)
      echo "Nicht unterstuetzte CPU-Architektur: $arch" >&2
      exit 1
      ;;
  esac
}

install_cloudflared() {
  if [ -x "$CLOUDFLARED_BIN" ]; then
    echo "cloudflared ist bereits installiert: $($CLOUDFLARED_BIN --version 2>/dev/null || true)"
    return
  fi

  ensure_downloader

  local asset url tmp
  asset="$(detect_cloudflared_asset)"
  url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
  tmp="$(mktemp)"

  echo "Lade cloudflared (${asset}) herunter..."
  download_file "$url" "$tmp"
  install -m 0755 "$tmp" "$CLOUDFLARED_BIN"
  rm -f "$tmp"

  echo "cloudflared installiert: $($CLOUDFLARED_BIN --version)"
}

find_belabox_port() {
  ensure_downloader

  for port in $BELABOX_PORTS; do
    if have_cmd curl; then
      if curl -fsS --max-time 4 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
        echo "$port"
        return
      fi
    else
      if wget -qO- --timeout=4 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
        echo "$port"
        return
      fi
    fi
  done

  echo "Konnte die lokale BELABOX-UI auf Port 80/8080/81 nicht erreichen." >&2
  echo "Pruefe bitte: sudo systemctl status belaUI.service" >&2
  exit 1
}

ensure_node() {
  if have_cmd nodejs; then
    echo "$(command -v nodejs)"
    return
  fi
  if have_cmd node; then
    echo "$(command -v node)"
    return
  fi

  apt_install_if_missing nodejs

  if have_cmd nodejs; then
    echo "$(command -v nodejs)"
  elif have_cmd node; then
    echo "$(command -v node)"
  else
    echo "Node.js konnte nicht gefunden/installiert werden." >&2
    exit 1
  fi
}

setup_user_and_dirs() {
  if ! id -u "$REMOTE_USER" >/dev/null 2>&1; then
    echo "Erstelle Systembenutzer ${REMOTE_USER}..."
    useradd --system --home "$STATE_DIR" --shell /usr/sbin/nologin "$REMOTE_USER"
  fi

  mkdir -p "$INSTALL_DIR" "$STATE_DIR"
  chown -R "$REMOTE_USER:$REMOTE_USER" "$INSTALL_DIR" "$STATE_DIR"
}

write_proxy() {
  local belabox_port="$1"
  local node_bin="$2"

  echo "Schreibe lokalen BELABOX Remote Proxy..."

  cat > "${INSTALL_DIR}/proxy.js" <<'EOF'
'use strict';

const http = require('http');
const net = require('net');

const listenHost = process.env.LISTEN_HOST || '127.0.0.1';
const listenPort = Number(process.env.LISTEN_PORT || '18080');
const targetHost = process.env.TARGET_HOST || '127.0.0.1';
const targetPort = Number(process.env.TARGET_PORT || '80');

const wsFrom = 'new WebSocket("ws://" + window.location.host)';
const wsTo = 'new WebSocket((window.location.protocol === "https:" ? "wss://" : "ws://") + window.location.host)';

function copyHeaders(headers) {
  const out = {...headers};
  out.host = `${targetHost}:${targetPort}`;
  out['accept-encoding'] = 'identity';
  return out;
}

const server = http.createServer((clientReq, clientRes) => {
  const options = {
    host: targetHost,
    port: targetPort,
    method: clientReq.method,
    path: clientReq.url,
    headers: copyHeaders(clientReq.headers),
  };

  const proxyReq = http.request(options, (proxyRes) => {
    const urlPath = (clientReq.url || '').split('?')[0];
    const contentType = String(proxyRes.headers['content-type'] || '');
    const shouldPatch = urlPath.endsWith('/script.js') || contentType.includes('javascript');

    if (!shouldPatch) {
      clientRes.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
      proxyRes.pipe(clientRes);
      return;
    }

    const chunks = [];
    proxyRes.on('data', (chunk) => chunks.push(chunk));
    proxyRes.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8').replace(wsFrom, wsTo);
      const headers = {...proxyRes.headers};
      delete headers['content-encoding'];
      delete headers['content-length'];
      headers['cache-control'] = 'no-store';
      headers['content-length'] = Buffer.byteLength(body);
      clientRes.writeHead(proxyRes.statusCode || 200, headers);
      clientRes.end(body);
    });
  });

  proxyReq.on('error', (err) => {
    clientRes.writeHead(502, {'content-type': 'text/plain'});
    clientRes.end(`BELABOX local proxy error: ${err.message}\n`);
  });

  clientReq.pipe(proxyReq);
});

server.on('upgrade', (clientReq, clientSocket, head) => {
  const targetSocket = net.connect(targetPort, targetHost, () => {
    const headers = copyHeaders(clientReq.headers);
    const lines = [`${clientReq.method} ${clientReq.url} HTTP/${clientReq.httpVersion}`];

    for (const [key, value] of Object.entries(headers)) {
      if (Array.isArray(value)) {
        for (const item of value) lines.push(`${key}: ${item}`);
      } else if (value !== undefined) {
        lines.push(`${key}: ${value}`);
      }
    }

    targetSocket.write(lines.join('\r\n') + '\r\n\r\n');
    if (head && head.length) targetSocket.write(head);
    targetSocket.pipe(clientSocket);
    clientSocket.pipe(targetSocket);
  });

  const closeBoth = () => {
    clientSocket.destroy();
    targetSocket.destroy();
  };

  targetSocket.on('error', closeBoth);
  clientSocket.on('error', closeBoth);
});

server.listen(listenPort, listenHost, () => {
  console.log(`BELABOX remote proxy listening on http://${listenHost}:${listenPort}`);
  console.log(`Forwarding to BELABOX UI at http://${targetHost}:${targetPort}`);
});
EOF

  chown "$REMOTE_USER:$REMOTE_USER" "${INSTALL_DIR}/proxy.js"
  chmod 0644 "${INSTALL_DIR}/proxy.js"

  cat > "/etc/systemd/system/${PROXY_SERVICE_NAME}.service" <<EOF
[Unit]
Description=BELABOX Remote UI local proxy
After=network.target belaUI.service

[Service]
User=${REMOTE_USER}
Group=${REMOTE_USER}
Environment=LISTEN_HOST=127.0.0.1
Environment=LISTEN_PORT=${PROXY_PORT}
Environment=TARGET_HOST=127.0.0.1
Environment=TARGET_PORT=${belabox_port}
ExecStart=${node_bin} ${INSTALL_DIR}/proxy.js
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

write_cloudflared_service() {
  echo "Schreibe cloudflared Quick Tunnel Service..."

  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=BELABOX Remote UI Quick Tunnel
After=network-online.target ${PROXY_SERVICE_NAME}.service
Wants=network-online.target
Requires=${PROXY_SERVICE_NAME}.service

[Service]
User=${REMOTE_USER}
Group=${REMOTE_USER}
Environment=HOME=${STATE_DIR}
WorkingDirectory=${STATE_DIR}
ExecStart=${CLOUDFLARED_BIN} tunnel --no-autoupdate --url http://127.0.0.1:${PROXY_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

write_link_helper() {
  cat > "$LINK_HELPER" <<EOF
#!/bin/sh
journalctl -u ${SERVICE_NAME}.service -n 300 --no-pager 2>/dev/null \\
  | grep -Eo 'https://[-a-zA-Z0-9]+\\.trycloudflare\\.com' \\
  | tail -n 1
EOF
  chmod 0755 "$LINK_HELPER"
}

start_services() {
  systemctl daemon-reload
  systemctl enable "${PROXY_SERVICE_NAME}.service" >/dev/null
  systemctl enable "${SERVICE_NAME}.service" >/dev/null
  systemctl restart "${PROXY_SERVICE_NAME}.service"
  systemctl restart "${SERVICE_NAME}.service"
}

wait_for_link() {
  local link=""

  echo "Warte auf den automatisch generierten Remote-Link..." >&2
  for _ in $(seq 1 60); do
    link="$("$LINK_HELPER" || true)"
    if [ -n "$link" ]; then
      echo "$link"
      return
    fi
    sleep 1
  done

  echo ""
}

print_done() {
  local link="$1"

  echo ""
  echo "=================================================="
  echo "  BELABOX REMOTE-ZUGANG IST AKTIV"
  echo "=================================================="
  echo ""

  if [ -n "$link" ]; then
    echo "Remote-Link:"
    echo "  ${link}"
  else
    echo "Der Tunnel laeuft, aber der Link wurde noch nicht im Log gefunden."
    echo "In ein paar Sekunden erneut anzeigen mit:"
    echo "  belabox-remote-link"
  fi

  echo ""
  echo "Der Link fuehrt auf die normale BELABOX-UI."
  echo "Der vorhandene BELABOX remote key bleibt unveraendert."
  echo ""
  echo "Status pruefen:"
  echo "  systemctl status ${SERVICE_NAME}.service"
  echo ""
  echo "Aktuellen Link erneut anzeigen:"
  echo "  belabox-remote-link"
  echo ""
  echo "Tunnel stoppen:"
  echo "  systemctl stop ${SERVICE_NAME}.service"
  echo ""
  echo "Wichtig: Bei einem Neustart des Tunnels kann sich der trycloudflare-Link aendern."
  echo "=================================================="
}

install_cloudflared
setup_user_and_dirs

if systemctl list-unit-files 2>/dev/null | grep -q '^belaUI\.socket'; then
  systemctl start belaUI.socket >/dev/null 2>&1 || true
fi
if systemctl list-unit-files 2>/dev/null | grep -q '^belaUI\.service'; then
  systemctl start belaUI.service >/dev/null 2>&1 || true
fi

NODE_BIN="$(ensure_node)"
BELABOX_PORT="$(find_belabox_port)"

echo "Lokale BELABOX-UI gefunden auf http://127.0.0.1:${BELABOX_PORT}"

write_proxy "$BELABOX_PORT" "$NODE_BIN"
write_cloudflared_service
write_link_helper
start_services

REMOTE_LINK="$(wait_for_link)"
print_done "$REMOTE_LINK"
