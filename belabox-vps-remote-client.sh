#!/bin/bash
###############################################################################
# BELABOX VPS Remote UI Client
#
# Auf der BELABOX ausfuehren. Baut einen dauerhaften ausgehenden Chisel-Tunnel
# zum VPS auf. SSH zwischen BELABOX und VPS wird nicht benoetigt.
# Der offizielle BELABOX remote key bleibt unveraendert.
###############################################################################
set -euo pipefail

ORIGINAL_ARGS=("$@")

VPS_HOST=""
TUNNEL_SERVER_PORT="9090"
TUNNEL_AUTH=""
REMOTE_PORT="18080"
LOCAL_PROXY_PORT="18180"
PUBLIC_URL=""

LOCAL_USER="belabox-vps-remote"
INSTALL_DIR="/opt/belabox-vps-remote-ui"
STATE_DIR="/var/lib/belabox-vps-remote-ui"
PROXY_SERVICE_NAME="belabox-vps-remote-ui-proxy"
TUNNEL_SERVICE_NAME="belabox-vps-remote-ui-tunnel"
LINK_HELPER="/usr/local/bin/belabox-vps-remote-link"
CHISEL_BIN="/usr/local/bin/chisel"

usage() {
  cat <<EOF
BELABOX VPS Remote UI Client

Nutzung auf der BELABOX:
  sudo bash belabox-vps-remote-client.sh [Optionen]

Optionen:
  --vps HOST              VPS-IP oder Domain (optional, sonst Abfrage)
  --public-url URL        Feste Remote-URL vom VPS-Script
  --tunnel-server-port P  Chisel-Tunnel-Port des VPS (Standard: 9090)
  --tunnel-auth USER:PASS Chisel-Token aus dem VPS-Script
  --remote-port PORT      Interner Tunnel-Port auf dem VPS (Standard: 18080)
  --local-proxy-port P    Lokaler Proxy-Port auf der BELABOX (Standard: 18180)
  --skip-key-install      Veraltet, wird ignoriert. SSH wird nicht mehr genutzt.
  --admin-user USER       Veraltet, wird ignoriert. SSH wird nicht mehr genutzt.
  --vps-ssh-port PORT     Veraltet, wird ignoriert. SSH wird nicht mehr genutzt.
  -h, --help              Hilfe anzeigen

Beispiel:
  sudo bash belabox-vps-remote-client.sh --vps 158.180.35.14 --tunnel-auth belabox:GEHEIM --public-url http://158.180.35.14/r/GEHEIM/
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --vps)
      VPS_HOST="$2"; shift 2 ;;
    --public-url)
      PUBLIC_URL="$2"; shift 2 ;;
    --tunnel-server-port)
      TUNNEL_SERVER_PORT="$2"; shift 2 ;;
    --tunnel-auth)
      TUNNEL_AUTH="$2"; shift 2 ;;
    --remote-port)
      REMOTE_PORT="$2"; shift 2 ;;
    --local-proxy-port)
      LOCAL_PROXY_PORT="$2"; shift 2 ;;
    --skip-key-install)
      echo "Hinweis: --skip-key-install ist veraltet. SSH wird nicht mehr genutzt." >&2
      shift ;;
    --admin-user|--vps-ssh-port)
      echo "Hinweis: $1 ist veraltet. SSH wird nicht mehr genutzt." >&2
      shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unbekannte Option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [ "${EUID}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo bash "$0" "${ORIGINAL_ARGS[@]}"
  fi
  echo "Bitte als root ausfuehren." >&2
  exit 1
fi

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

prompt_value() {
  local var_name="$1"
  local prompt="$2"
  local current_value="${!var_name}"

  if [ -n "$current_value" ]; then
    return
  fi
  if [ ! -r /dev/tty ]; then
    echo "Fehlt: ${prompt}" >&2
    exit 1
  fi

  while [ -z "${!var_name}" ]; do
    read -rp "${prompt}: " "$var_name" < /dev/tty
    printf -v "$var_name" '%s' "${!var_name//[[:space:]]/}"
  done
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

ensure_node() {
  if have_cmd nodejs; then
    command -v nodejs
    return
  fi
  if have_cmd node; then
    command -v node
    return
  fi

  apt_install_if_missing nodejs

  if have_cmd nodejs; then
    command -v nodejs
  elif have_cmd node; then
    command -v node
  else
    echo "Node.js konnte nicht gefunden/installiert werden." >&2
    exit 1
  fi
}

detect_chisel_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv6l|armhf|arm) echo "arm" ;;
    i386|i686) echo "386" ;;
    *) echo "Nicht unterstuetzte CPU-Architektur fuer chisel: $(uname -m)" >&2; exit 1 ;;
  esac
}

install_chisel() {
  if [ -x "$CHISEL_BIN" ]; then
    echo "Chisel ist bereits installiert: $($CHISEL_BIN --version 2>/dev/null || true)"
    return
  fi

  local arch tag version url tmp_dir
  arch="$(detect_chisel_arch)"
  tag="$(curl -fsSL https://api.github.com/repos/jpillora/chisel/releases/latest | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -z "$tag" ]; then
    echo "Konnte die aktuelle Chisel-Version nicht ermitteln." >&2
    exit 1
  fi

  version="${tag#v}"
  url="https://github.com/jpillora/chisel/releases/download/${tag}/chisel_${version}_linux_${arch}.gz"
  tmp_dir="$(mktemp -d)"

  echo "Lade Chisel ${tag} fuer linux_${arch} herunter..."
  curl -fsSL "$url" -o "${tmp_dir}/chisel.gz"
  gzip -dc "${tmp_dir}/chisel.gz" > "$CHISEL_BIN"
  chmod 0755 "$CHISEL_BIN"
  rm -rf "$tmp_dir"
}

find_belabox_port() {
  ensure_downloader

  for port in 80 8080 81; do
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

setup_local_user_and_dirs() {
  if ! id -u "$LOCAL_USER" >/dev/null 2>&1; then
    echo "Erstelle lokalen Systembenutzer: ${LOCAL_USER}"
    useradd --system --home "$STATE_DIR" --shell /usr/sbin/nologin "$LOCAL_USER"
  fi

  mkdir -p "$INSTALL_DIR" "$STATE_DIR"
  chown -R "$LOCAL_USER:$LOCAL_USER" "$INSTALL_DIR" "$STATE_DIR"
  chmod 700 "$STATE_DIR"
}

write_proxy() {
  local belabox_port="$1"
  local node_bin="$2"

  echo "Schreibe lokalen BELABOX UI Proxy..."

  cat > "${INSTALL_DIR}/proxy.js" <<'EOF'
'use strict';

const http = require('http');
const net = require('net');

const listenHost = process.env.LISTEN_HOST || '127.0.0.1';
const listenPort = Number(process.env.LISTEN_PORT || '18180');
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

  chown "$LOCAL_USER:$LOCAL_USER" "${INSTALL_DIR}/proxy.js"
  chmod 0644 "${INSTALL_DIR}/proxy.js"

  cat > "/etc/systemd/system/${PROXY_SERVICE_NAME}.service" <<EOF
[Unit]
Description=BELABOX VPS Remote UI local proxy
After=network.target belaUI.service

[Service]
User=${LOCAL_USER}
Group=${LOCAL_USER}
Environment=LISTEN_HOST=127.0.0.1
Environment=LISTEN_PORT=${LOCAL_PROXY_PORT}
Environment=TARGET_HOST=127.0.0.1
Environment=TARGET_PORT=${belabox_port}
ExecStart=${node_bin} ${INSTALL_DIR}/proxy.js
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

write_tunnel_service() {
  echo "Schreibe dauerhaften Chisel-Tunnel..."

  cat > "/etc/systemd/system/${TUNNEL_SERVICE_NAME}.service" <<EOF
[Unit]
Description=BELABOX VPS Remote UI Chisel reverse tunnel
After=network-online.target ${PROXY_SERVICE_NAME}.service
Wants=network-online.target
Requires=${PROXY_SERVICE_NAME}.service

[Service]
User=${LOCAL_USER}
Group=${LOCAL_USER}
Environment=HOME=${STATE_DIR}
ExecStart=${CHISEL_BIN} client --auth ${TUNNEL_AUTH} ${VPS_HOST}:${TUNNEL_SERVER_PORT} R:127.0.0.1:${REMOTE_PORT}:127.0.0.1:${LOCAL_PROXY_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

write_link_helper() {
  echo "$PUBLIC_URL" > "${STATE_DIR}/public_url"
  chown "$LOCAL_USER:$LOCAL_USER" "${STATE_DIR}/public_url"
  chmod 0644 "${STATE_DIR}/public_url"

  cat > "$LINK_HELPER" <<EOF
#!/bin/sh
cat ${STATE_DIR}/public_url
EOF
  chmod 0755 "$LINK_HELPER"
}

start_services() {
  systemctl daemon-reload
  systemctl enable "${PROXY_SERVICE_NAME}.service" >/dev/null
  systemctl enable "${TUNNEL_SERVICE_NAME}.service" >/dev/null
  systemctl restart "${PROXY_SERVICE_NAME}.service"
  systemctl restart "${TUNNEL_SERVICE_NAME}.service"
}

check_tunnel() {
  echo "Pruefe Tunnel-Verbindung..."
  sleep 5

  local recent_log
  recent_log="$(journalctl -u "${TUNNEL_SERVICE_NAME}.service" --since "1 minute ago" --no-pager 2>/dev/null || true)"

  if printf '%s\n' "$recent_log" | grep -Eiq 'authentication failed|connection refused|server: Reverse port forwarding not enabled|failed|error'; then
    echo "Der Chisel-Tunnel konnte sich noch nicht mit dem VPS verbinden. Letzte Meldungen:" >&2
    printf '%s\n' "$recent_log" | tail -n 40 >&2
    return 1
  fi

  if systemctl is-active --quiet "${TUNNEL_SERVICE_NAME}.service"; then
    return 0
  fi

  echo "Der Tunnel-Dienst ist nicht aktiv. Letzte Meldungen:" >&2
  journalctl -u "${TUNNEL_SERVICE_NAME}.service" -n 40 --no-pager >&2 || true
  return 1
}

prompt_value VPS_HOST "VPS-IP oder Domain"
prompt_value TUNNEL_AUTH "Tunnel-Token aus dem VPS-Script"

if [ -z "$PUBLIC_URL" ]; then
  if [ -r /dev/tty ]; then
    read -rp "Feste Remote-URL aus dem VPS-Script: " PUBLIC_URL < /dev/tty
    PUBLIC_URL="${PUBLIC_URL//[[:space:]]/}"
  fi
fi
if [ -z "$PUBLIC_URL" ]; then
  PUBLIC_URL="http://${VPS_HOST}/"
  echo "Hinweis: Keine --public-url angegeben. Der angezeigte Link ist wahrscheinlich unvollstaendig." >&2
fi

apt_install_if_missing ca-certificates curl gzip nodejs
install_chisel
setup_local_user_and_dirs

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
write_tunnel_service
write_link_helper
start_services
TUNNEL_OK="0"
if check_tunnel; then
  TUNNEL_OK="1"
fi

if [ "$TUNNEL_OK" = "1" ]; then
  STATUS_TITLE="BELABOX VPS REMOTE-ZUGANG IST AKTIV"
else
  STATUS_TITLE="BELABOX VPS REMOTE-ZUGANG IST NOCH NICHT VERBUNDEN"
fi

cat <<EOF

==================================================
  ${STATUS_TITLE}
==================================================

Feste Remote-URL:
  ${PUBLIC_URL}

SSH zwischen BELABOX und VPS wird fuer diesen Remote-Zugang nicht benutzt.
Der offizielle BELABOX remote key bleibt unveraendert.

Link erneut anzeigen:
  belabox-vps-remote-link

Status auf der BELABOX pruefen:
  systemctl status ${TUNNEL_SERVICE_NAME}.service

Tunnel-Logs anzeigen:
  journalctl -u ${TUNNEL_SERVICE_NAME}.service -n 80 --no-pager

Tunnel stoppen:
  systemctl stop ${TUNNEL_SERVICE_NAME}.service

Tunnel wieder starten:
  systemctl start ${TUNNEL_SERVICE_NAME}.service
==================================================
EOF
