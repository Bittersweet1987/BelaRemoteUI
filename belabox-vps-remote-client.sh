#!/bin/bash
###############################################################################
# BELABOX VPS Remote UI Client
#
# Auf der BELABOX ausfuehren. Baut einen dauerhaften ausgehenden Tunnel zum VPS.
# Die feste URL kommt vom VPS, z.B.:
#   http://158.180.35.14/
#
# Der offizielle BELABOX remote key bleibt unveraendert.
###############################################################################
set -euo pipefail

ORIGINAL_ARGS=("$@")

VPS_HOST=""
VPS_SSH_PORT="22"
VPS_ADMIN_USER="root"
TUNNEL_USER="belabox-tunnel"
REMOTE_PORT="18080"
LOCAL_PROXY_PORT="18180"
PUBLIC_URL=""
SKIP_KEY_INSTALL="0"

LOCAL_USER="belabox-vps-remote"
INSTALL_DIR="/opt/belabox-vps-remote-ui"
STATE_DIR="/var/lib/belabox-vps-remote-ui"
PROXY_SERVICE_NAME="belabox-vps-remote-ui-proxy"
TUNNEL_SERVICE_NAME="belabox-vps-remote-ui-tunnel"
LINK_HELPER="/usr/local/bin/belabox-vps-remote-link"
KEY_FILE="${STATE_DIR}/id_ed25519"

usage() {
  cat <<EOF
BELABOX VPS Remote UI Client

Nutzung auf der BELABOX:
  sudo bash belabox-vps-remote-client.sh [Optionen]

Optionen:
  --vps HOST            VPS-IP oder Domain (optional, sonst Abfrage)
  --public-url URL      Feste URL, die am Ende angezeigt wird
  --vps-ssh-port PORT   SSH-Port des VPS (Standard: 22)
  --admin-user USER     Admin-User zum Eintragen des SSH-Keys (Standard: root)
  --tunnel-user USER    Tunnel-User auf dem VPS (Standard: belabox-tunnel)
  --remote-port PORT    Interner Tunnel-Port auf dem VPS (Standard: 18080)
  --local-proxy-port P  Lokaler Proxy-Port auf der BELABOX (Standard: 18180)
  --skip-key-install    SSH-Key nicht automatisch auf dem VPS eintragen
  -h, --help            Hilfe anzeigen

Beispiele:
  sudo bash belabox-vps-remote-client.sh
  sudo bash belabox-vps-remote-client.sh --vps 158.180.35.14
  sudo bash belabox-vps-remote-client.sh --vps 158.180.35.14 --public-url http://158.180.35.14/
EOF
}

prompt_for_vps_host() {
  if [ -n "$VPS_HOST" ]; then
    return
  fi

  echo ""
  echo "Bitte gib die IP-Adresse oder Domain deines VPS ein."

  while [ -z "$VPS_HOST" ]; do
    if [ ! -r /dev/tty ]; then
      echo "Fehlt: VPS-IP oder Domain. Nutze z.B. --vps 158.180.35.14" >&2
      exit 1
    fi

    read -rp "VPS-IP oder Domain: " VPS_HOST < /dev/tty
    VPS_HOST="${VPS_HOST//[[:space:]]/}"
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --vps)
      VPS_HOST="$2"; shift 2 ;;
    --public-url)
      PUBLIC_URL="$2"; shift 2 ;;
    --vps-ssh-port)
      VPS_SSH_PORT="$2"; shift 2 ;;
    --admin-user)
      VPS_ADMIN_USER="$2"; shift 2 ;;
    --tunnel-user)
      TUNNEL_USER="$2"; shift 2 ;;
    --remote-port)
      REMOTE_PORT="$2"; shift 2 ;;
    --local-proxy-port)
      LOCAL_PROXY_PORT="$2"; shift 2 ;;
    --skip-key-install)
      SKIP_KEY_INSTALL="1"; shift ;;
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

prompt_for_vps_host

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

run_as_local_user() {
  if have_cmd runuser; then
    runuser -u "$LOCAL_USER" -- "$@"
  elif have_cmd sudo; then
    sudo -u "$LOCAL_USER" "$@"
  else
    echo "Weder runuser noch sudo gefunden; kann Befehl nicht als ${LOCAL_USER} starten." >&2
    exit 1
  fi
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

generate_ssh_key() {
  if [ ! -f "$KEY_FILE" ]; then
    echo "Erzeuge SSH-Key fuer den Reverse-Tunnel..."
    run_as_local_user ssh-keygen -t ed25519 -N "" -f "$KEY_FILE" -C "belabox-remote-ui" >/dev/null
  fi

  chmod 600 "$KEY_FILE"
  chmod 644 "${KEY_FILE}.pub"
  chown "$LOCAL_USER:$LOCAL_USER" "$KEY_FILE" "${KEY_FILE}.pub"
}

install_key_on_vps() {
  if [ "$SKIP_KEY_INSTALL" = "1" ]; then
    echo "Automatisches Eintragen des SSH-Keys uebersprungen."
    echo "Trage diesen Public Key manuell beim User ${TUNNEL_USER} auf dem VPS ein:"
    cat "${KEY_FILE}.pub"
    return
  fi

  local pubkey authorized_line key_b64
  pubkey="$(cat "${KEY_FILE}.pub")"
  authorized_line="restrict,port-forwarding,permitlisten=\"127.0.0.1:${REMOTE_PORT}\" ${pubkey}"
  key_b64="$(printf '%s' "$authorized_line" | base64 | tr -d '\n')"

  echo "Trage den Tunnel-Key auf dem VPS ein. Falls gefragt: VPS-${VPS_ADMIN_USER}-Passwort eingeben."
  local remote_output
  remote_output="$(ssh -p "$VPS_SSH_PORT" -o StrictHostKeyChecking=accept-new "${VPS_ADMIN_USER}@${VPS_HOST}" \
    "KEY_B64='${key_b64}' TUNNEL_USER='${TUNNEL_USER}' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail
SUDO="sudo"
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
fi

if ! id "$TUNNEL_USER" >/dev/null 2>&1; then
  echo "Tunnel-User ${TUNNEL_USER} existiert nicht. Bitte zuerst das VPS-Server-Script ausfuehren." >&2
  exit 1
fi

HOME_DIR="$(getent passwd "$TUNNEL_USER" | cut -d: -f6)"
AUTH_FILE="${HOME_DIR}/.ssh/authorized_keys"
LINE="$(printf '%s' "$KEY_B64" | base64 -d)"

$SUDO install -d -m 700 -o "$TUNNEL_USER" -g "$TUNNEL_USER" "${HOME_DIR}/.ssh"
$SUDO touch "$AUTH_FILE"
if ! $SUDO grep -qxF "$LINE" "$AUTH_FILE" 2>/dev/null; then
  printf '%s\n' "$LINE" | $SUDO tee -a "$AUTH_FILE" >/dev/null
fi
$SUDO awk '!seen[$0]++' "$AUTH_FILE" | $SUDO tee "${AUTH_FILE}.tmp" >/dev/null
$SUDO mv "${AUTH_FILE}.tmp" "$AUTH_FILE"
$SUDO chown "$TUNNEL_USER:$TUNNEL_USER" "$AUTH_FILE"
$SUDO chmod 600 "$AUTH_FILE"

if [ -r /etc/belabox-remote-ui/public_url ]; then
  printf 'BELAREMOTE_PUBLIC_URL=%s\n' "$(cat /etc/belabox-remote-ui/public_url)"
fi
REMOTE_SCRIPT
)"

  printf '%s\n' "$remote_output" | sed '/^BELAREMOTE_PUBLIC_URL=/d'

  if [ -z "$PUBLIC_URL" ]; then
    PUBLIC_URL="$(printf '%s\n' "$remote_output" | sed -n 's/^BELAREMOTE_PUBLIC_URL=//p' | tail -n 1)"
  fi
}

finalize_public_url() {
  if [ -n "$PUBLIC_URL" ]; then
    return
  fi

  PUBLIC_URL="http://${VPS_HOST}/"
  echo "Hinweis: Konnte keinen generierten Link vom VPS lesen." >&2
  echo "Pruefe auf dem VPS: cat /etc/belabox-remote-ui/public_url" >&2
  echo "Oder starte das Client-Script mit --public-url <URL>." >&2
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
const wsTo = 'new WebSocket((window.location.protocol === "https:" ? "wss://" : "ws://") + window.location.host + window.location.pathname)';

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
  console.log(`BELABOX proxy listening on http://${listenHost}:${listenPort}`);
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
  echo "Schreibe dauerhaften Reverse-SSH-Tunnel..."

  ssh-keyscan -p "$VPS_SSH_PORT" -H "$VPS_HOST" >> "${STATE_DIR}/known_hosts" 2>/dev/null || true
  chown "$LOCAL_USER:$LOCAL_USER" "${STATE_DIR}/known_hosts" 2>/dev/null || true
  chmod 600 "${STATE_DIR}/known_hosts" 2>/dev/null || true

  cat > "/etc/systemd/system/${TUNNEL_SERVICE_NAME}.service" <<EOF
[Unit]
Description=BELABOX VPS Remote UI reverse SSH tunnel
After=network-online.target ${PROXY_SERVICE_NAME}.service
Wants=network-online.target
Requires=${PROXY_SERVICE_NAME}.service

[Service]
User=${LOCAL_USER}
Group=${LOCAL_USER}
Environment=HOME=${STATE_DIR}
Environment=AUTOSSH_GATETIME=0
ExecStart=/usr/bin/autossh -M 0 -N -T \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=${STATE_DIR}/known_hosts \
  -i ${KEY_FILE} \
  -p ${VPS_SSH_PORT} \
  -R 127.0.0.1:${REMOTE_PORT}:127.0.0.1:${LOCAL_PROXY_PORT} \
  ${TUNNEL_USER}@${VPS_HOST}
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
  sleep 3
  if systemctl is-active --quiet "${TUNNEL_SERVICE_NAME}.service"; then
    return 0
  fi

  echo "Der Tunnel-Dienst ist nicht aktiv. Letzte Meldungen:" >&2
  journalctl -u "${TUNNEL_SERVICE_NAME}.service" -n 40 --no-pager >&2 || true
  return 1
}

apt_install_if_missing ca-certificates curl openssh-client autossh nodejs
setup_local_user_and_dirs
generate_ssh_key
install_key_on_vps
finalize_public_url

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
check_tunnel || true

cat <<EOF

==================================================
  BELABOX VPS REMOTE-ZUGANG IST AKTIV
==================================================

Feste Remote-URL:
  ${PUBLIC_URL}

Diese URL bleibt gleich, solange du denselben VPS bzw. dieselbe Domain nutzt.
Der offizielle BELABOX remote key bleibt unveraendert.

Link erneut anzeigen:
  belabox-vps-remote-link

Status auf der BELABOX pruefen:
  systemctl status ${TUNNEL_SERVICE_NAME}.service

Tunnel stoppen:
  systemctl stop ${TUNNEL_SERVICE_NAME}.service

Tunnel wieder starten:
  systemctl start ${TUNNEL_SERVICE_NAME}.service
==================================================
EOF
