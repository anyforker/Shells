#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_DIR="/etc/hysteria"
readonly CONFIG_FILE="${CONFIG_DIR}/config.yaml"
readonly SERVICE_NAME="hysteria-server.service"
readonly INSTALLER_URL="https://get.hy2.sh/"
readonly CLIENT_CONFIG="/root/hysteria2-client.yaml"
readonly MIHOMO_CONFIG="/root/hysteria2-mihomo.yaml"

DOMAIN="${HY2_DOMAIN:-}"
EMAIL="${HY2_EMAIL:-}"
PORT="${HY2_PORT:-443}"
PASSWORD="${HY2_PASSWORD:-}"
MASQUERADE_URL="${HY2_MASQUERADE_URL:-https://news.ycombinator.com/}"
ACME_TYPE="${HY2_ACME_TYPE:-http}"
OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-}"
ASSUME_YES=false
SKIP_DNS_CHECK=false
INSTALL_VERSION=""

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

warn() {
  printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Install and configure a Hysteria 2 server on Debian 13.

Usage:
  sudo bash install-hysteria2.sh [options]

Options:
  --domain DOMAIN            Domain pointing directly to this server (required)
  --email EMAIL              Email used for ACME (required)
  --port PORT                Hysteria UDP listen port (default: 443)
  --password PASSWORD        Authentication password (default: generated)
  --masquerade URL           HTTP/3 masquerade upstream
                              (default: https://news.ycombinator.com/)
  --acme-type http|tls       ACME challenge: TCP 80 or TCP 443 (default: http)
  --obfs-password PASSWORD   Enable Salamander obfuscation with this password
  --version VERSION          Install a specific version, for example v2.9.2
  --skip-dns-check           Do not require the domain to resolve before install
  -y, --yes                  Non-interactive mode
  -h, --help                 Show this help

Environment equivalents:
  HY2_DOMAIN, HY2_EMAIL, HY2_PORT, HY2_PASSWORD,
  HY2_MASQUERADE_URL, HY2_ACME_TYPE, HY2_OBFS_PASSWORD

Example:
  sudo bash install-hysteria2.sh \
    --domain hy2.example.com --email admin@example.com
EOF
}

while (($# > 0)); do
  case "$1" in
    --domain)
      [[ $# -ge 2 ]] || die '--domain requires a value'
      DOMAIN="$2"
      shift 2
      ;;
    --email)
      [[ $# -ge 2 ]] || die '--email requires a value'
      EMAIL="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die '--port requires a value'
      PORT="$2"
      shift 2
      ;;
    --password)
      [[ $# -ge 2 ]] || die '--password requires a value'
      PASSWORD="$2"
      shift 2
      ;;
    --masquerade)
      [[ $# -ge 2 ]] || die '--masquerade requires a value'
      MASQUERADE_URL="$2"
      shift 2
      ;;
    --acme-type)
      [[ $# -ge 2 ]] || die '--acme-type requires a value'
      ACME_TYPE="$2"
      shift 2
      ;;
    --obfs-password)
      [[ $# -ge 2 ]] || die '--obfs-password requires a value'
      OBFS_PASSWORD="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || die '--version requires a value'
      INSTALL_VERSION="$2"
      shift 2
      ;;
    --skip-dns-check)
      SKIP_DNS_CHECK=true
      shift
      ;;
    -y | --yes)
      ASSUME_YES=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ ${EUID} -eq 0 ]] || die 'run this script as root (sudo bash ...)'
[[ -d /run/systemd/system ]] || die 'systemd is required'

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == 'debian' ]] || warn "designed for Debian; detected ${ID:-unknown}"
  [[ ${VERSION_ID:-} == '13' ]] || warn "designed for Debian 13; detected ${VERSION_ID:-unknown}"
fi

prompt_required() {
  local variable_name="$1"
  local prompt="$2"
  local value="${!variable_name}"

  if [[ -n "$value" ]]; then
    return
  fi
  $ASSUME_YES && die "$prompt is required in non-interactive mode"
  read -r -p "$prompt: " value
  printf -v "$variable_name" '%s' "$value"
}

prompt_required DOMAIN 'Domain'
prompt_required EMAIL 'ACME email'

[[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || die 'invalid domain'
[[ "$DOMAIN" == *.* ]] || die 'domain must be a fully qualified name'
[[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die 'invalid email'
[[ "$PORT" =~ ^[0-9]+$ ]] || die 'port must be numeric'
((PORT >= 1 && PORT <= 65535)) || die 'port must be between 1 and 65535'
[[ "$ACME_TYPE" == 'http' || "$ACME_TYPE" == 'tls' ]] || die '--acme-type must be http or tls'
[[ "$MASQUERADE_URL" =~ ^https?://[^[:space:]]+$ ]] || die 'masquerade must be an HTTP(S) URL'
[[ "$MASQUERADE_URL" != *\"* && "$MASQUERADE_URL" != *\\* ]] || die 'masquerade URL cannot contain quotes or backslashes'

validate_secret() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[A-Za-z0-9._~-]+$ ]] || die "$label may contain only A-Z, a-z, 0-9, dot, underscore, tilde and hyphen"
  ((${#value} >= 16)) || die "$label must contain at least 16 characters"
}

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
fi
[[ -n "$PASSWORD" ]] || die 'failed to generate a password'
validate_secret 'password' "$PASSWORD"

if [[ -n "$OBFS_PASSWORD" ]]; then
  validate_secret 'obfs password' "$OBFS_PASSWORD"
fi

if ! $SKIP_DNS_CHECK; then
  mapfile -t RESOLVED_ADDRESSES < <(getent ahosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u)
  ((${#RESOLVED_ADDRESSES[@]} > 0)) || die "$DOMAIN does not resolve; create its DNS record first or use --skip-dns-check"
  log "DNS resolves ${DOMAIN} to: ${RESOLVED_ADDRESSES[*]}"
fi

export DEBIAN_FRONTEND=noninteractive
log 'Installing required Debian packages'
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl openssl libcap2-bin iproute2

if command -v ss >/dev/null 2>&1; then
  ACME_PORT=80
  [[ "$ACME_TYPE" == 'tls' ]] && ACME_PORT=443
  ACME_LISTENER="$(ss -H -ltnp | awk -v port="${ACME_PORT}" '$4 ~ (":" port "$") { print }')"
  if [[ -n "$ACME_LISTENER" && "$ACME_LISTENER" != *'"hysteria"'* ]]; then
    die "TCP ${ACME_PORT} is already in use; free it or select another ACME challenge method"
  fi
fi

INSTALLER_FILE="$(mktemp /tmp/hysteria2-installer.XXXXXX)"
cleanup() {
  [[ -n "${INSTALLER_FILE:-}" && -f "$INSTALLER_FILE" ]] && rm -f -- "$INSTALLER_FILE"
}
trap cleanup EXIT

log 'Downloading the official Hysteria installer'
curl --proto '=https' --tlsv1.2 -fsSL "$INSTALLER_URL" -o "$INSTALLER_FILE"
INSTALL_ARGS=()
[[ -n "$INSTALL_VERSION" ]] && INSTALL_ARGS+=(--version "$INSTALL_VERSION")
bash "$INSTALLER_FILE" "${INSTALL_ARGS[@]}"

command -v hysteria >/dev/null 2>&1 || die 'the official installer did not install hysteria'
id hysteria >/dev/null 2>&1 || die 'the official installer did not create the hysteria user'

install -d -m 0750 -o hysteria -g hysteria "$CONFIG_DIR" /var/lib/hysteria /var/lib/hysteria/acme

if [[ -f "$CONFIG_FILE" ]]; then
  BACKUP_FILE="${CONFIG_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a -- "$CONFIG_FILE" "$BACKUP_FILE"
  log "Existing server config backed up to ${BACKUP_FILE}"
fi

TEMP_CONFIG="$(mktemp "${CONFIG_DIR}/config.yaml.tmp.XXXXXX")"
{
  printf 'listen: ":%s"\n\n' "$PORT"
  printf 'acme:\n'
  printf '  domains:\n'
  printf '    - "%s"\n' "$DOMAIN"
  printf '  email: "%s"\n' "$EMAIL"
  printf '  ca: letsencrypt\n'
  printf '  dir: /var/lib/hysteria/acme\n'
  printf '  type: %s\n\n' "$ACME_TYPE"
  printf 'auth:\n'
  printf '  type: password\n'
  printf '  password: "%s"\n\n' "$PASSWORD"
  if [[ -n "$OBFS_PASSWORD" ]]; then
    printf 'obfs:\n'
    printf '  type: salamander\n'
    printf '  salamander:\n'
    printf '    password: "%s"\n\n' "$OBFS_PASSWORD"
  fi
  printf 'masquerade:\n'
  printf '  type: proxy\n'
  printf '  proxy:\n'
  printf '    url: "%s"\n' "$MASQUERADE_URL"
  printf '    rewriteHost: true\n'
} >"$TEMP_CONFIG"
chown hysteria:hysteria "$TEMP_CONFIG"
chmod 0640 "$TEMP_CONFIG"
mv -f -- "$TEMP_CONFIG" "$CONFIG_FILE"

configure_firewall() {
  local acme_port=80
  [[ "$ACME_TYPE" == 'tls' ]] && acme_port=443

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
    ufw allow "${PORT}/udp"
    ufw allow "${acme_port}/tcp"
    log 'Updated active UFW rules'
    return
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${PORT}/udp"
    firewall-cmd --permanent --add-port="${acme_port}/tcp"
    firewall-cmd --reload
    log 'Updated active firewalld rules'
    return
  fi

  warn "No active UFW/firewalld detected. Ensure UDP ${PORT} and TCP ${acme_port} are allowed by nftables and the VPS provider firewall."
}

configure_firewall

log 'Starting Hysteria 2'
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"

SERVER_READY=false
for _ in {1..30}; do
  if systemctl is-failed --quiet "$SERVICE_NAME"; then
    break
  fi
  if ss -H -lun | awk '{print $4}' | grep -Eq "[:.]${PORT}$"; then
    SERVER_READY=true
    break
  fi
  sleep 1
done

if ! $SERVER_READY; then
  journalctl --no-pager -n 80 -u "$SERVICE_NAME" >&2 || true
  die "Hysteria did not begin listening on UDP ${PORT}; review the log above"
fi

OBFS_URI=""
if [[ -n "$OBFS_PASSWORD" ]]; then
  OBFS_URI="&obfs=salamander&obfs-password=${OBFS_PASSWORD}"
fi
SHARE_URI="hysteria2://${PASSWORD}@${DOMAIN}:${PORT}/?sni=${DOMAIN}${OBFS_URI}"

TEMP_CLIENT="$(mktemp /root/hysteria2-client.yaml.tmp.XXXXXX)"
{
  printf 'server: "%s:%s"\n' "$DOMAIN" "$PORT"
  printf 'auth: "%s"\n\n' "$PASSWORD"
  printf 'tls:\n'
  printf '  sni: "%s"\n' "$DOMAIN"
  printf '  insecure: false\n'
  if [[ -n "$OBFS_PASSWORD" ]]; then
    printf '\nobfs:\n'
    printf '  type: salamander\n'
    printf '  salamander:\n'
    printf '    password: "%s"\n' "$OBFS_PASSWORD"
  fi
  printf '\nsocks5:\n'
  printf '  listen: 127.0.0.1:1080\n'
} >"$TEMP_CLIENT"
chmod 0600 "$TEMP_CLIENT"
mv -f -- "$TEMP_CLIENT" "$CLIENT_CONFIG"

TEMP_MIHOMO="$(mktemp /root/hysteria2-mihomo.yaml.tmp.XXXXXX)"
{
  printf 'proxies:\n'
  printf '  - name: "HY2-%s"\n' "$DOMAIN"
  printf '    type: hysteria2\n'
  printf '    server: "%s"\n' "$DOMAIN"
  printf '    port: %s\n' "$PORT"
  printf '    password: "%s"\n' "$PASSWORD"
  if [[ -n "$OBFS_PASSWORD" ]]; then
    printf '    obfs: salamander\n'
    printf '    obfs-password: "%s"\n' "$OBFS_PASSWORD"
  fi
  printf '    sni: "%s"\n' "$DOMAIN"
  printf '    skip-cert-verify: false\n'
  printf '    alpn:\n'
  printf '      - h3\n'
} >"$TEMP_MIHOMO"
chmod 0600 "$TEMP_MIHOMO"
mv -f -- "$TEMP_MIHOMO" "$MIHOMO_CONFIG"

log "Installed: $(hysteria version 2>/dev/null | head -n 1 || true)"
log "Server config: ${CONFIG_FILE}"
log "Official client config: ${CLIENT_CONFIG}"
log "Velo/mihomo node config: ${MIHOMO_CONFIG}"
printf '\nShare URI (keep it secret):\n%s\n\n' "$SHARE_URI"
printf 'Useful commands:\n'
printf '  systemctl status %s\n' "$SERVICE_NAME"
printf '  journalctl -u %s -f\n' "$SERVICE_NAME"
printf '  systemctl restart %s\n' "$SERVICE_NAME"
printf '\nRemember to allow UDP %s in the VPS provider security group.\n' "$PORT"
