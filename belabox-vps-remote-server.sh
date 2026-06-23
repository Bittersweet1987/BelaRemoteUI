#!/bin/bash
###############################################################################
# BELABOX VPS Remote UI Receiver
#
# Auf dem VPS ausfuehren. Richtet einen oder mehrere feste Remote-Zugaenge ein.
# Jede BELABOX bekommt ein eigenes Profil mit eigener URL, eigenem Tunnel-Token
# und eigenem internen VPS-Port.
#
# SSH zwischen BELABOX und VPS wird nicht benoetigt.
# Der offizielle BELABOX remote key bleibt unveraendert.
###############################################################################
set -euo pipefail

ORIGINAL_ARGS=("$@")

BASE_REMOTE_PORT="18080"
BASE_REMOTE_PORT_SET="0"
TUNNEL_SERVER_PORT="9090"
TUNNEL_SERVER_PORT_SET="0"
PUBLIC_PORT="80"
PUBLIC_PORT_SET="0"
SSH_PORT="22"
SERVER_NAME="_"
SERVER_NAME_SET="0"
ENABLE_UFW="1"
KEEP_DEFAULT_SITE="0"
NGINX_EXISTED_BEFORE_INSTALL="0"
CONFIG_DIR="/etc/belabox-remote-ui"
PROFILES_DIR="${CONFIG_DIR}/profiles"
SERVER_CONFIG_FILE="${CONFIG_DIR}/server.conf"
AUTH_FILE="${CONFIG_DIR}/users.json"
PUBLIC_PORT_FILE="${CONFIG_DIR}/public_port"
SERVER_NAME_FILE="${CONFIG_DIR}/server_name"
PROFILE=""
PUBLIC_PATH=""
TUNNEL_AUTH=""
REMOTE_PORT=""
REGENERATE_LINK="0"
ACTION="install"
REBOOT_MODE="ask"
CHISEL_BIN="/usr/local/bin/chisel"
CHISEL_SERVICE_NAME="belabox-remote-ui-chisel"
NGINX_CONF="/etc/nginx/conf.d/belabox-remote-ui.conf"
NGINX_SITE="/etc/nginx/sites-available/belabox-remote-ui"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/belabox-remote-ui"
SERVER_SCRIPT_URL="https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh"
CLIENT_SCRIPT_URL="https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-client.sh"

usage() {
  cat <<EOF
BELABOX VPS Remote UI Receiver

Nutzung:
  curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- [Optionen]

Installation / Profile:
  --profile NAME          Name der BELABOX auf diesem VPS (sonst Abfrage)
  --domain NAME           Domain, die auf diesen VPS zeigt (optional)
  --public-port PORT      Oeffentlicher HTTP-Port (Standard: 80, bei RTMP-Konflikt automatisch 8088)
  --tunnel-server-port P  Oeffentlicher Chisel-Tunnel-Port (Standard: 9090)
  --remote-port PORT      Interner Reverse-Tunnel-Port fuer dieses Profil
  --tunnel-auth USER:PASS Chisel-Token, sonst automatisch erzeugt
  --ssh-port PORT         SSH-Management-Port des VPS fuer UFW (Standard: 22)
  --public-path PATH      Fester geheimer URL-Pfad, sonst automatisch erzeugt
  --regenerate-link       Neuen geheimen URL-Pfad fuer dieses Profil erzeugen
  --no-ufw                UFW nicht konfigurieren
  --keep-default-site     Nginx default site nicht deaktivieren

Verwaltung:
  --list                  Profile anzeigen
  --delete-profile NAME   Nur ein BELABOX-Profil loeschen
  --uninstall             Komplette VPS-Installation entfernen

Neustart:
  --reboot                Nach erfolgreicher Installation automatisch rebooten
  --no-reboot             Nach erfolgreicher Installation nicht nach Reboot fragen

Beispiele:
  curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash
  curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --profile belabox2 --domain belabox.example.com
  curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --list
  curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --delete-profile belabox2
  curl -fsSL https://raw.githubusercontent.com/Bittersweet1987/BelaRemoteUI/main/belabox-vps-remote-server.sh | sudo bash -s -- --uninstall
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile|--name)
      PROFILE="$2"; shift 2 ;;
    --domain)
      SERVER_NAME="$2"; SERVER_NAME_SET="1"; shift 2 ;;
    --public-port)
      PUBLIC_PORT="$2"; PUBLIC_PORT_SET="1"; shift 2 ;;
    --tunnel-port|--remote-port)
      REMOTE_PORT="$2"; shift 2 ;;
    --base-remote-port)
      BASE_REMOTE_PORT="$2"; BASE_REMOTE_PORT_SET="1"; shift 2 ;;
    --tunnel-server-port)
      TUNNEL_SERVER_PORT="$2"; TUNNEL_SERVER_PORT_SET="1"; shift 2 ;;
    --tunnel-auth)
      TUNNEL_AUTH="$2"; shift 2 ;;
    --ssh-port)
      SSH_PORT="$2"; shift 2 ;;
    --public-path)
      PUBLIC_PATH="$2"; shift 2 ;;
    --regenerate-link)
      REGENERATE_LINK="1"; shift ;;
    --no-ufw)
      ENABLE_UFW="0"; shift ;;
    --keep-default-site)
      KEEP_DEFAULT_SITE="1"; shift ;;
    --list)
      ACTION="list"; shift ;;
    --delete-profile)
      ACTION="delete-profile"; PROFILE="$2"; shift 2 ;;
    --uninstall)
      ACTION="uninstall"; shift ;;
    --reboot)
      REBOOT_MODE="yes"; shift ;;
    --no-reboot)
      REBOOT_MODE="no"; shift ;;
    --tunnel-user)
      echo "Hinweis: $1 ist veraltet. SSH wird nicht mehr fuer den Tunnel genutzt." >&2
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

prompt_value() {
  local var_name="$1"
  local prompt="$2"
  if [ -n "${!var_name}" ]; then
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

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//')"
  if [ -z "$value" ]; then
    echo "belabox"
  else
    echo "$value"
  fi
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

get_public_ip() {
  local ip=""
  if have_cmd curl; then
    ip="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  elif have_cmd wget; then
    ip="$(wget -qO- --timeout=5 https://ifconfig.me 2>/dev/null || true)"
  fi
  echo "$ip"
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

load_server_config() {
  local requested_server_name requested_public_port requested_tunnel_server_port requested_base_remote_port
  requested_server_name="$SERVER_NAME"
  requested_public_port="$PUBLIC_PORT"
  requested_tunnel_server_port="$TUNNEL_SERVER_PORT"
  requested_base_remote_port="$BASE_REMOTE_PORT"

  mkdir -p "$CONFIG_DIR" "$PROFILES_DIR"
  if [ -r "$SERVER_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$SERVER_CONFIG_FILE"
  fi

  if [ "$SERVER_NAME_SET" = "1" ]; then
    SERVER_NAME="$requested_server_name"
  fi
  if [ "$PUBLIC_PORT_SET" = "1" ]; then
    PUBLIC_PORT="$requested_public_port"
  fi
  if [ "$TUNNEL_SERVER_PORT_SET" = "1" ]; then
    TUNNEL_SERVER_PORT="$requested_tunnel_server_port"
  fi
  if [ "$BASE_REMOTE_PORT_SET" = "1" ]; then
    BASE_REMOTE_PORT="$requested_base_remote_port"
  fi

  if [ "$SERVER_NAME" = "_" ] && [ -s "$SERVER_NAME_FILE" ]; then
    SERVER_NAME="$(cat "$SERVER_NAME_FILE")"
  fi
  if [ "$PUBLIC_PORT_SET" = "0" ] && [ -s "$PUBLIC_PORT_FILE" ]; then
    PUBLIC_PORT="$(cat "$PUBLIC_PORT_FILE")"
  fi
}

detect_rtmp_nginx_config() {
  if [ ! -d /etc/nginx ]; then
    return 1
  fi
  grep -RIl '^[[:space:]]*rtmp[[:space:]]*{' /etc/nginx 2>/dev/null | grep -q .
}

choose_public_port() {
  if [ "$PUBLIC_PORT_SET" = "0" ] && [ "$PUBLIC_PORT" = "80" ] && { detect_rtmp_nginx_config || [ "$NGINX_EXISTED_BEFORE_INSTALL" = "1" ]; }; then
    PUBLIC_PORT="8088"
    KEEP_DEFAULT_SITE="1"
    echo "Bestehende Nginx/RTMP-Konfiguration erkannt. BelaRemoteUI nutzt deshalb HTTP-Port ${PUBLIC_PORT}, damit vorhandene Nginx-Setups nicht ueberschrieben werden."
  fi
}

profile_dir() {
  printf '%s/%s\n' "$PROFILES_DIR" "$1"
}

next_remote_port() {
  local used port max
  max="$((BASE_REMOTE_PORT - 1))"
  if [ -d "$PROFILES_DIR" ]; then
    for used in "$PROFILES_DIR"/*/remote_port; do
      [ -r "$used" ] || continue
      port="$(cat "$used")"
      case "$port" in
        ''|*[!0-9]*) continue ;;
      esac
      if [ "$port" -gt "$max" ]; then
        max="$port"
      fi
    done
  fi
  echo "$((max + 1))"
}

public_host() {
  local host="$SERVER_NAME"
  if [ "$host" = "_" ]; then
    host="$(get_public_ip)"
  fi
  if [ -z "$host" ]; then
    host="DEINE_VPS_IP"
  fi
  echo "$host"
}

make_public_url() {
  local host path
  host="$(public_host)"
  path="$1"
  if [ "$PUBLIC_PORT" = "80" ]; then
    echo "http://${host}/${path}/"
  else
    echo "http://${host}:${PUBLIC_PORT}/${path}/"
  fi
}

prepare_profile() {
  prompt_value PROFILE "Profilname fuer diese BELABOX"
  PROFILE="$(slugify "$PROFILE")"

  local dir existing_path existing_auth existing_remote public_token public_url
  dir="$(profile_dir "$PROFILE")"
  mkdir -p "$dir"

  PUBLIC_PATH="${PUBLIC_PATH#/}"
  PUBLIC_PATH="${PUBLIC_PATH%/}"

  existing_path=""
  existing_auth=""
  existing_remote=""
  [ -s "${dir}/public_path" ] && existing_path="$(cat "${dir}/public_path")"
  [ -s "${dir}/tunnel_auth" ] && existing_auth="$(cat "${dir}/tunnel_auth")"
  [ -s "${dir}/remote_port" ] && existing_remote="$(cat "${dir}/remote_port")"

  if [ -z "$PUBLIC_PATH" ]; then
    if [ "$REGENERATE_LINK" = "0" ] && [ -n "$existing_path" ]; then
      PUBLIC_PATH="$existing_path"
    else
      PUBLIC_PATH="r/${PROFILE}/$(generate_token)"
    fi
  fi

  case "$PUBLIC_PATH" in
    *[!A-Za-z0-9_/-]*|""|/*|*//*)
      echo "Ungueltiger public path: ${PUBLIC_PATH}" >&2
      echo "Erlaubt sind Buchstaben, Zahlen, _, - und einzelne /." >&2
      exit 1 ;;
  esac

  if [ -z "$TUNNEL_AUTH" ]; then
    if [ -n "$existing_auth" ]; then
      TUNNEL_AUTH="$existing_auth"
    else
      TUNNEL_AUTH="${PROFILE}:$(generate_token)"
    fi
  fi

  case "$TUNNEL_AUTH" in
    *[!A-Za-z0-9_:-]*|""|:*|*:|*:*:*)
      echo "Ungueltiger Tunnel-Token. Nutze das Format USER:PASS mit Buchstaben, Zahlen, _, - oder :." >&2
      exit 1 ;;
    *:*) ;;
    *)
      echo "Ungueltiger Tunnel-Token. Nutze das Format USER:PASS." >&2
      exit 1 ;;
  esac

  if [ -z "$REMOTE_PORT" ]; then
    if [ -n "$existing_remote" ]; then
      REMOTE_PORT="$existing_remote"
    else
      REMOTE_PORT="$(next_remote_port)"
    fi
  fi

  case "$REMOTE_PORT" in
    ''|*[!0-9]*)
      echo "Ungueltiger Remote-Port: ${REMOTE_PORT}" >&2
      exit 1 ;;
  esac

  public_token="${PUBLIC_PATH##*/}"
  public_url="$(make_public_url "$PUBLIC_PATH")"

  printf '%s\n' "$PROFILE" > "${dir}/name"
  printf '%s\n' "$PUBLIC_PATH" > "${dir}/public_path"
  printf '%s\n' "$public_token" > "${dir}/public_token"
  printf '%s\n' "$TUNNEL_AUTH" > "${dir}/tunnel_auth"
  printf '%s\n' "$REMOTE_PORT" > "${dir}/remote_port"
  printf '%s\n' "$public_url" > "${dir}/public_url"
  chmod 600 "${dir}/tunnel_auth" "${dir}/public_token" "${dir}/public_path"
  chmod 644 "${dir}/name" "${dir}/remote_port" "${dir}/public_url"

  printf 'SERVER_NAME=%q\nPUBLIC_PORT=%q\nTUNNEL_SERVER_PORT=%q\nBASE_REMOTE_PORT=%q\n' \
    "$SERVER_NAME" "$PUBLIC_PORT" "$TUNNEL_SERVER_PORT" "$BASE_REMOTE_PORT" > "$SERVER_CONFIG_FILE"
  printf '%s\n' "$SERVER_NAME" > "$SERVER_NAME_FILE"
  printf '%s\n' "$PUBLIC_PORT" > "$PUBLIC_PORT_FILE"
}

write_chisel_authfile() {
  local first="1" dir auth port user
  mkdir -p "$CONFIG_DIR"
  {
    echo "{"
    if [ -d "$PROFILES_DIR" ]; then
      for dir in "$PROFILES_DIR"/*; do
        [ -d "$dir" ] || continue
        [ -s "${dir}/tunnel_auth" ] || continue
        [ -s "${dir}/remote_port" ] || continue
        auth="$(cat "${dir}/tunnel_auth")"
        port="$(cat "${dir}/remote_port")"
        user="${auth%%:*}"
        case "$port" in ''|*[!0-9]*) continue ;; esac
        [ "$first" = "1" ] || echo ","
        first="0"
        printf '  "%s": ["^R:127\\\\.0\\\\.0\\\\.1:%s$"]' "$auth" "$port"
      done
    fi
    echo
    echo "}"
  } > "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"
}

write_chisel_service() {
  echo "Schreibe Chisel-Tunnelserver..."
  cat > "/etc/systemd/system/${CHISEL_SERVICE_NAME}.service" <<EOF
[Unit]
Description=BELABOX Remote UI Chisel reverse tunnel server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${CHISEL_BIN} server --host 0.0.0.0 --port ${TUNNEL_SERVER_PORT} --reverse --authfile ${AUTH_FILE}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${CHISEL_SERVICE_NAME}.service" >/dev/null
  systemctl restart "${CHISEL_SERVICE_NAME}.service"
}

write_nginx_config() {
  local dir token port path listen_suffix
  echo "Konfiguriere Nginx als oeffentlichen Empfaenger..."
  rm -f /etc/nginx/conf.d/belabox-remote-ui-websocket.conf

  listen_suffix=" default_server"
  if [ "$PUBLIC_PORT" = "80" ] && { [ "$KEEP_DEFAULT_SITE" = "1" ] || [ "$NGINX_EXISTED_BEFORE_INSTALL" = "1" ]; }; then
    listen_suffix=""
  fi

  {
    cat <<'EOF'
map $http_upgrade $belabox_remote_ui_connection_upgrade {
    default upgrade;
    '' close;
}

map $cookie_belabox_remote_token $belabox_remote_ui_cookie_port {
    default "";
EOF
    if [ -d "$PROFILES_DIR" ]; then
      for dir in "$PROFILES_DIR"/*; do
        [ -d "$dir" ] || continue
        [ -s "${dir}/public_token" ] || continue
        [ -s "${dir}/remote_port" ] || continue
        token="$(cat "${dir}/public_token")"
        port="$(cat "${dir}/remote_port")"
        printf '    "%s" "%s";\n' "$token" "$port"
      done
    fi
    cat <<'EOF'
}

map $arg_token $belabox_remote_ui_query_port {
    default "";
EOF
    if [ -d "$PROFILES_DIR" ]; then
      for dir in "$PROFILES_DIR"/*; do
        [ -d "$dir" ] || continue
        [ -s "${dir}/public_token" ] || continue
        [ -s "${dir}/remote_port" ] || continue
        token="$(cat "${dir}/public_token")"
        port="$(cat "${dir}/remote_port")"
        printf '    "%s" "%s";\n' "$token" "$port"
      done
    fi
    cat <<'EOF'
}

map $arg_token $belabox_remote_ui_query_cookie {
    default "";
EOF
    if [ -d "$PROFILES_DIR" ]; then
      for dir in "$PROFILES_DIR"/*; do
        [ -d "$dir" ] || continue
        [ -s "${dir}/public_token" ] || continue
        token="$(cat "${dir}/public_token")"
        printf '    "%s" "belabox_remote_token=%s; Path=/; HttpOnly; SameSite=Lax";\n' "$token" "$token"
      done
    fi
    cat <<'EOF'
}

map "$belabox_remote_ui_query_port:$belabox_remote_ui_cookie_port" $belabox_remote_ui_port {
    default "";
    ~^([0-9]+): $1;
    ~^:([0-9]+)$ $1;
}
EOF
  } > "$NGINX_CONF"

  {
    cat <<EOF
server {
    listen ${PUBLIC_PORT}${listen_suffix};
    server_name ${SERVER_NAME};

EOF
    if [ -d "$PROFILES_DIR" ]; then
      for dir in "$PROFILES_DIR"/*; do
        [ -d "$dir" ] || continue
        [ -s "${dir}/public_path" ] || continue
        [ -s "${dir}/public_token" ] || continue
        path="$(cat "${dir}/public_path")"
        token="$(cat "${dir}/public_token")"
        cat <<EOF
    location = /${path} {
        add_header Set-Cookie "belabox_remote_token=${token}; Path=/; HttpOnly; SameSite=Lax" always;
        return 302 /;
    }

    location /${path}/ {
        add_header Set-Cookie "belabox_remote_token=${token}; Path=/; HttpOnly; SameSite=Lax" always;
        return 302 /;
    }

EOF
      done
    fi
    cat <<'EOF'
    location / {
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With" always;
        add_header Set-Cookie $belabox_remote_ui_query_cookie always;

        if ($request_method = OPTIONS) {
            return 204;
        }

        if ($belabox_remote_ui_port = "") {
            return 404;
        }

        proxy_pass http://127.0.0.1:$belabox_remote_ui_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $belabox_remote_ui_connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF
  } > "$NGINX_SITE"

  if [ "$KEEP_DEFAULT_SITE" = "0" ] && [ "$NGINX_EXISTED_BEFORE_INSTALL" != "1" ]; then
    rm -f /etc/nginx/sites-enabled/default
  fi

  ln -sfn "$NGINX_SITE" "$NGINX_SITE_LINK"
  nginx -t
  systemctl enable nginx >/dev/null
  systemctl restart nginx
}

configure_firewall() {
  if [ "$ENABLE_UFW" != "1" ]; then
    echo "UFW-Konfiguration uebersprungen. Oeffne extern mindestens TCP ${PUBLIC_PORT}, ${TUNNEL_SERVER_PORT} und deinen SSH-Management-Port."
    return
  fi

  if ! have_cmd ufw || ! ufw status 2>/dev/null | grep -qi '^Status: active'; then
    echo "UFW ist nicht aktiv. BelaRemoteUI aktiviert keine Firewall automatisch."
    echo "Oeffne extern mindestens TCP ${PUBLIC_PORT}, ${TUNNEL_SERVER_PORT} und deinen SSH-Management-Port."
    echo "Falls du RTMP/Statistiken nutzt, muessen bestehende Ports wie 1935/tcp und 8080/tcp offen bleiben."
    return
  fi

  echo "UFW ist aktiv. Oeffne BelaRemoteUI-Ports: SSH ${SSH_PORT}/tcp, HTTP ${PUBLIC_PORT}/tcp, Tunnel ${TUNNEL_SERVER_PORT}/tcp"
  ufw allow "${SSH_PORT}/tcp" >/dev/null || true
  ufw allow "${PUBLIC_PORT}/tcp" >/dev/null || true
  ufw allow "${TUNNEL_SERVER_PORT}/tcp" >/dev/null || true
}

write_status_helper() {
  cat > /usr/local/bin/belabox-remote-vps-status <<'EOF'
#!/bin/sh
CONFIG_DIR="/etc/belabox-remote-ui"
PROFILES_DIR="${CONFIG_DIR}/profiles"

echo "=== BELABOX VPS Remote UI Status ==="
echo ""
echo "Profile:"
if [ -d "$PROFILES_DIR" ]; then
  for dir in "$PROFILES_DIR"/*; do
    [ -d "$dir" ] || continue
    name="$(cat "$dir/name" 2>/dev/null || basename "$dir")"
    url="$(cat "$dir/public_url" 2>/dev/null || true)"
    port="$(cat "$dir/remote_port" 2>/dev/null || true)"
    auth="$(cat "$dir/tunnel_auth" 2>/dev/null || true)"
    echo "  ${name}"
    echo "    URL: ${url}"
    echo "    Token: ${auth}"
    echo "    VPS-Port: ${port}"
  done
else
  echo "  Keine Profile gefunden."
fi
echo ""
echo "Nginx:"
systemctl --no-pager --full status nginx | sed -n '1,8p'
echo ""
echo "Chisel:"
systemctl --no-pager --full status belabox-remote-ui-chisel.service | sed -n '1,10p'
echo ""
echo "Ports:"
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep -E ':(9090|180[0-9][0-9]) ' || true
else
  netstat -ltnp 2>/dev/null | grep -E ':(9090|180[0-9][0-9]) ' || true
fi
EOF
  chmod 0755 /usr/local/bin/belabox-remote-vps-status
}

list_profiles() {
  load_server_config
  if [ ! -d "$PROFILES_DIR" ]; then
    echo "Keine Profile vorhanden."
    return
  fi
  belabox-remote-vps-status 2>/dev/null || true
}

delete_profile() {
  load_server_config
  if [ -z "$PROFILE" ]; then
    echo "Fehlt: --delete-profile NAME" >&2
    exit 1
  fi
  PROFILE="$(slugify "$PROFILE")"
  rm -rf "$(profile_dir "$PROFILE")"
  write_chisel_authfile
  write_chisel_service
  write_nginx_config
  write_status_helper
  echo "Profil geloescht: ${PROFILE}"
}

uninstall_all() {
  echo "Entferne BelaRemoteUI vom VPS..."
  systemctl stop "${CHISEL_SERVICE_NAME}.service" 2>/dev/null || true
  systemctl disable "${CHISEL_SERVICE_NAME}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${CHISEL_SERVICE_NAME}.service"
  systemctl daemon-reload

  rm -f "$NGINX_CONF" "$NGINX_SITE_LINK" "$NGINX_SITE"
  nginx -t >/dev/null 2>&1 && systemctl restart nginx || true

  rm -rf "$CONFIG_DIR"
  rm -f /usr/local/bin/belabox-remote-vps-status
  rm -f "$CHISEL_BIN"

  echo "VPS-Installation entfernt. Bestehende andere Nginx/RTMP-Konfigurationen wurden nicht geloescht."
}

maybe_reboot() {
  case "$REBOOT_MODE" in
    yes)
      echo "Starte VPS neu..."
      reboot
      ;;
    no)
      return
      ;;
  esac

  if [ -r /dev/tty ]; then
    local answer
    read -rp "VPS jetzt neu starten? [y/N]: " answer < /dev/tty
    case "$answer" in
      y|Y|yes|YES|j|J|ja|JA)
        echo "Starte VPS neu..."
        reboot ;;
    esac
  else
    echo "Kein interaktives Terminal fuer Reboot-Abfrage. Bei Bedarf: sudo reboot"
  fi
}

if [ "$ACTION" = "uninstall" ]; then
  uninstall_all
  exit 0
fi

if [ "$ACTION" = "list" ]; then
  list_profiles
  exit 0
fi

validate_os
if dpkg -s nginx >/dev/null 2>&1 || [ -d /etc/nginx ]; then
  NGINX_EXISTED_BEFORE_INSTALL="1"
fi
apt_install_if_missing ca-certificates curl gzip nginx
install_chisel
load_server_config
choose_public_port

if [ "$ACTION" = "delete-profile" ]; then
  delete_profile
  exit 0
fi

prepare_profile
write_chisel_authfile
write_chisel_service
write_nginx_config
configure_firewall
write_status_helper

PROFILE_DIR="$(profile_dir "$PROFILE")"
PUBLIC_URL="$(cat "${PROFILE_DIR}/public_url")"
PUBLIC_TOKEN="$(cat "${PROFILE_DIR}/public_token")"
TUNNEL_AUTH="$(cat "${PROFILE_DIR}/tunnel_auth")"
REMOTE_PORT="$(cat "${PROFILE_DIR}/remote_port")"
PUBLIC_HOST="$(public_host)"

cat <<EOF

==================================================
  VPS-EMPFANG IST BEREIT
==================================================

Profil:
  ${PROFILE}

Feste Remote-URL:
  ${PUBLIC_URL}

Token fuer externe Widgets:
  ${PUBLIC_TOKEN}

Widget/API-URL mit Token:
  http://${PUBLIC_HOST}$([ "$PUBLIC_PORT" = "80" ] || printf ':%s' "$PUBLIC_PORT")/?token=${PUBLIC_TOKEN}

WebSocket-URL ohne Cookie:
  ws://${PUBLIC_HOST}$([ "$PUBLIC_PORT" = "80" ] || printf ':%s' "$PUBLIC_PORT")/?token=${PUBLIC_TOKEN}

Chisel-Tunnel-Port:
  ${TUNNEL_SERVER_PORT}/tcp

Interner VPS-Port fuer dieses Profil:
  ${REMOTE_PORT}/tcp

Tunnel-Token:
  ${TUNNEL_AUTH}

Naechster Schritt auf der BELABOX:
  curl -fsSL ${CLIENT_SCRIPT_URL} | sudo bash -s -- --vps ${PUBLIC_HOST} --tunnel-server-port ${TUNNEL_SERVER_PORT} --tunnel-auth ${TUNNEL_AUTH} --remote-port ${REMOTE_PORT} --public-url ${PUBLIC_URL}

Wichtig: Diese komplette Curl-Zeile auf der BELABOX ausfuehren.

Weitere Profile anlegen:
  curl -fsSL ${SERVER_SCRIPT_URL} | sudo bash

Profile anzeigen:
  belabox-remote-vps-status
  curl -fsSL ${SERVER_SCRIPT_URL} | sudo bash -s -- --list

Profil loeschen:
  curl -fsSL ${SERVER_SCRIPT_URL} | sudo bash -s -- --delete-profile ${PROFILE}

Komplett entfernen:
  curl -fsSL ${SERVER_SCRIPT_URL} | sudo bash -s -- --uninstall

SSH zwischen BELABOX und VPS wird fuer diesen Remote-Zugang nicht benutzt.
Der offizielle BELABOX remote key wird nicht benutzt und nicht veraendert.
==================================================
EOF

maybe_reboot
