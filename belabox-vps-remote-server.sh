#!/bin/bash
###############################################################################
# BELABOX VPS Remote UI Receiver
#
# Auf dem VPS ausfuehren. Richtet eine feste oeffentliche URL ein:
#   http://VPS-IP/
# oder, wenn eine Domain auf den VPS zeigt:
#   http://deine-domain.tld/
#
# Die BELABOX verbindet sich spaeter ausgehend per Reverse-SSH-Tunnel zum VPS.
# Der offizielle BELABOX remote key bleibt unveraendert.
###############################################################################
set -euo pipefail

ORIGINAL_ARGS=("$@")

TUNNEL_USER="belabox-tunnel"
TUNNEL_PORT="18080"
PUBLIC_PORT="80"
SSH_PORT="22"
SERVER_NAME="_"
ENABLE_UFW="1"
KEEP_DEFAULT_SITE="0"
CONFIG_DIR="/etc/belabox-remote-ui"
PUBLIC_PATH_FILE="${CONFIG_DIR}/public_path"
PUBLIC_URL_FILE="${CONFIG_DIR}/public_url"
PUBLIC_PATH=""
REGENERATE_LINK="0"

usage() {
  cat <<EOF
BELABOX VPS Remote UI Receiver

Nutzung:
  sudo bash belabox-vps-remote-server.sh [Optionen]

Optionen:
  --domain NAME          Domain, die auf diesen VPS zeigt (optional)
  --public-port PORT    Oeffentlicher HTTP-Port (Standard: 80)
  --tunnel-port PORT    Interner Reverse-Tunnel-Port (Standard: 18080)
  --ssh-port PORT       SSH-Port des VPS fuer Firewall-Freigabe (Standard: 22)
  --tunnel-user USER    SSH-Tunnel-User (Standard: belabox-tunnel)
  --public-path PATH    Fester geheimer URL-Pfad, sonst automatisch erzeugt
  --regenerate-link     Neuen geheimen URL-Pfad erzeugen
  --no-ufw              UFW nicht konfigurieren/aktivieren
  --keep-default-site   Nginx default site nicht deaktivieren
  -h, --help            Hilfe anzeigen

Beispiel:
  sudo bash belabox-vps-remote-server.sh --domain belabox.example.com
  sudo bash belabox-vps-remote-server.sh --public-port 8080
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain)
      SERVER_NAME="$2"; shift 2 ;;
    --public-port)
      PUBLIC_PORT="$2"; shift 2 ;;
    --tunnel-port)
      TUNNEL_PORT="$2"; shift 2 ;;
    --ssh-port)
      SSH_PORT="$2"; shift 2 ;;
    --tunnel-user)
      TUNNEL_USER="$2"; shift 2 ;;
    --public-path)
      PUBLIC_PATH="$2"; shift 2 ;;
    --regenerate-link)
      REGENERATE_LINK="1"; shift ;;
    --no-ufw)
      ENABLE_UFW="0"; shift ;;
    --keep-default-site)
      KEEP_DEFAULT_SITE="1"; shift ;;
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

apt_install_if_missing() {
  local missing=()
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Installiere benoetigte Pakete: ${missing[*]}"
    apt-get update -y -q
    apt-get install -y -q "${missing[@]}"
  fi
}

validate_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "Erkanntes System: ${PRETTY_NAME:-unknown}"
    if [ "${ID:-}" != "ubuntu" ]; then
      echo "Hinweis: Dieses Script ist fuer Ubuntu 24.04/26.04 gedacht." >&2
    fi
    case "${VERSION_ID:-}" in
      24.04|26.04) ;;
      *) echo "Hinweis: Nicht explizit getestete Ubuntu-Version: ${VERSION_ID:-unknown}" >&2 ;;
    esac
  fi
}

get_public_ip() {
  local ip=""
  if have_cmd curl; then
    ip="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  elif have_cmd wget; then
    ip="$(wget -qO- --timeout=5 https://ifconfig.me 2>/dev/null || true)"
  fi
  echo "$ip"
}

generate_token() {
  if have_cmd openssl; then
    openssl rand -hex 18
    return
  fi

  set +o pipefail
  local token
  token="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 36)"
  set -o pipefail
  echo "$token"
}

prepare_public_path() {
  mkdir -p "$CONFIG_DIR"

  PUBLIC_PATH="${PUBLIC_PATH#/}"
  PUBLIC_PATH="${PUBLIC_PATH%/}"

  if [ -n "$PUBLIC_PATH" ]; then
    :
  elif [ "$REGENERATE_LINK" = "0" ] && [ -s "$PUBLIC_PATH_FILE" ]; then
    PUBLIC_PATH="$(cat "$PUBLIC_PATH_FILE")"
  else
    PUBLIC_PATH="r/$(generate_token)"
  fi

  case "$PUBLIC_PATH" in
    *[!A-Za-z0-9_/-]*|""|/*|*//*)
      echo "Ungueltiger public path: ${PUBLIC_PATH}" >&2
      echo "Erlaubt sind Buchstaben, Zahlen, _, - und einzelne /." >&2
      exit 1
      ;;
  esac

  printf '%s\n' "$PUBLIC_PATH" > "$PUBLIC_PATH_FILE"
  chmod 600 "$PUBLIC_PATH_FILE"
}

setup_tunnel_user() {
  local home_dir="/var/lib/${TUNNEL_USER}"

  if ! id -u "$TUNNEL_USER" >/dev/null 2>&1; then
    echo "Erstelle SSH-Tunnel-User: ${TUNNEL_USER}"
    useradd --system --create-home --home-dir "$home_dir" --shell /bin/bash "$TUNNEL_USER"
  fi

  passwd -l "$TUNNEL_USER" >/dev/null 2>&1 || true
  install -d -m 700 -o "$TUNNEL_USER" -g "$TUNNEL_USER" "$home_dir/.ssh"
  touch "$home_dir/.ssh/authorized_keys"
  chown "$TUNNEL_USER:$TUNNEL_USER" "$home_dir/.ssh/authorized_keys"
  chmod 600 "$home_dir/.ssh/authorized_keys"
}

configure_sshd() {
  echo "Konfiguriere SSH fuer eingeschraenkten Reverse-Tunnel..."
  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/90-belabox-remote-ui.conf <<EOF
# BELABOX Remote UI reverse tunnel user
Match User ${TUNNEL_USER}
    AllowTcpForwarding remote
    GatewayPorts no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
    PasswordAuthentication no
EOF

  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
}

configure_nginx() {
  echo "Konfiguriere Nginx als oeffentlichen Empfaenger..."

  cat > /etc/nginx/conf.d/belabox-remote-ui-websocket.conf <<'EOF'
map $http_upgrade $belabox_remote_ui_connection_upgrade {
    default upgrade;
    '' close;
}
EOF

  cat > /etc/nginx/sites-available/belabox-remote-ui <<EOF
server {
    listen ${PUBLIC_PORT} default_server;
    server_name ${SERVER_NAME};

    location = / {
        return 404;
    }

    location = /${PUBLIC_PATH} {
        return 302 /${PUBLIC_PATH}/;
    }

    location /${PUBLIC_PATH}/ {
        rewrite ^/${PUBLIC_PATH}/?(.*)$ /\$1 break;
        proxy_pass http://127.0.0.1:${TUNNEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$belabox_remote_ui_connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

  if [ "$KEEP_DEFAULT_SITE" = "0" ]; then
    rm -f /etc/nginx/sites-enabled/default
  fi

  ln -sfn /etc/nginx/sites-available/belabox-remote-ui /etc/nginx/sites-enabled/belabox-remote-ui
  nginx -t
  systemctl enable nginx >/dev/null
  systemctl restart nginx
}

configure_firewall() {
  if [ "$ENABLE_UFW" != "1" ]; then
    echo "UFW-Konfiguration uebersprungen."
    return
  fi

  if ! have_cmd ufw; then
    apt_install_if_missing ufw
  fi

  echo "Oeffne Firewall-Ports: SSH ${SSH_PORT}/tcp, HTTP ${PUBLIC_PORT}/tcp"
  ufw allow "${SSH_PORT}/tcp" >/dev/null || true
  ufw allow "${PUBLIC_PORT}/tcp" >/dev/null || true
  echo "y" | ufw enable >/dev/null || true
}

write_status_helper() {
  cat > /usr/local/bin/belabox-remote-vps-status <<EOF
#!/bin/sh
echo "=== BELABOX VPS Remote UI Status ==="
echo "Nginx:"
systemctl --no-pager --full status nginx | sed -n '1,8p'
echo ""
echo "Tunnel-Port ${TUNNEL_PORT}:"
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep ':${TUNNEL_PORT} ' || echo "Noch kein Reverse-Tunnel verbunden."
else
  netstat -ltnp 2>/dev/null | grep ':${TUNNEL_PORT} ' || echo "Noch kein Reverse-Tunnel verbunden."
fi
EOF
  chmod 0755 /usr/local/bin/belabox-remote-vps-status
}

validate_os
apt_install_if_missing ca-certificates curl openssh-server nginx
prepare_public_path
setup_tunnel_user
configure_sshd
configure_nginx
configure_firewall
write_status_helper

PUBLIC_HOST="$SERVER_NAME"
if [ "$PUBLIC_HOST" = "_" ]; then
  PUBLIC_HOST="$(get_public_ip)"
fi
if [ -z "$PUBLIC_HOST" ]; then
  PUBLIC_HOST="DEINE_VPS_IP"
fi

if [ "$PUBLIC_PORT" = "80" ]; then
  PUBLIC_URL="http://${PUBLIC_HOST}/${PUBLIC_PATH}/"
else
  PUBLIC_URL="http://${PUBLIC_HOST}:${PUBLIC_PORT}/${PUBLIC_PATH}/"
fi

printf '%s\n' "$PUBLIC_URL" > "$PUBLIC_URL_FILE"
chmod 644 "$PUBLIC_URL_FILE"

cat <<EOF

==================================================
  VPS-EMPFANG IST BEREIT
==================================================

Feste Remote-URL:
  ${PUBLIC_URL}

Noch zeigt diese URL erst dann auf die BELABOX-UI,
wenn das BELABOX-Client-Script verbunden ist.

Naechster Schritt auf der BELABOX:
  sudo bash belabox-vps-remote-client.sh --vps ${PUBLIC_HOST} --public-url ${PUBLIC_URL}

Falls SSH auf dem VPS nicht Port 22 nutzt:
  sudo bash belabox-vps-remote-client.sh --vps ${PUBLIC_HOST} --vps-ssh-port ${SSH_PORT} --public-url ${PUBLIC_URL}

Status auf dem VPS pruefen:
  belabox-remote-vps-status

Der offizielle BELABOX remote key wird nicht benutzt und nicht veraendert.
==================================================
EOF
