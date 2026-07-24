#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_DIR="/etc/snell"
readonly CONFIG_FILE="${CONFIG_DIR}/snell-v6-server.conf"
readonly BINARY_FILE="/usr/local/bin/snell-server-v6"
readonly SERVICE_FILE="/etc/systemd/system/snell-v6.service"
readonly SERVICE_NAME="snell-v6.service"

SNELL_VERSION="${SNELLV6_VERSION:-6.0.0rc}"
DOWNLOAD_URL="${SNELLV6_DOWNLOAD_URL:-}"
PORT="${SNELLV6_PORT:-80}"
PSK="${SNELLV6_PSK:-}"
LISTEN_MODE="${SNELLV6_LISTEN_MODE:-ipv4}"
DNS_PREFERENCE="${SNELLV6_DNS_PREFERENCE:-ipv4-only}"
DNS_SERVERS="${SNELLV6_DNS_SERVERS:-}"
EGRESS_INTERFACE="${SNELLV6_EGRESS_INTERFACE:-}"
ASSUME_YES=false
REPLACE_CONFIG=false
KEEP_CONFIG=false

PORT_SET=false
PSK_SET=false
LISTEN_MODE_SET=false
DNS_PREFERENCE_SET=false
DNS_SERVERS_SET=false
EGRESS_INTERFACE_SET=false

[[ -n "${SNELLV6_PORT:-}" ]] && PORT_SET=true
[[ -n "${SNELLV6_PSK:-}" ]] && PSK_SET=true
[[ -n "${SNELLV6_LISTEN_MODE:-}" ]] && LISTEN_MODE_SET=true
[[ -n "${SNELLV6_DNS_PREFERENCE:-}" ]] && DNS_PREFERENCE_SET=true
[[ -n "${SNELLV6_DNS_SERVERS:-}" ]] && DNS_SERVERS_SET=true
[[ -n "${SNELLV6_EGRESS_INTERFACE:-}" ]] && EGRESS_INTERFACE_SET=true

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
Install or update Snell Server v6 on a systemd Linux server.

Usage:
  sudo bash install-snellv6.sh [options]

Options:
  --port PORT                 Listen port (default: 80)
  --psk PSK                   Pre-shared key, 12-255 safe ASCII characters
                               (default: generated)
  --listen-mode MODE          ipv4, dual, or ipv6 (default: ipv4)
  --dns-preference MODE       default, prefer-ipv4, prefer-ipv6,
                               ipv4-only, or ipv6-only (default: ipv4-only)
  --dns SERVERS               Comma-separated custom DNS servers
  --egress-interface NAME     Bind outbound TCP, UDP, and DNS to an interface
  --version VERSION           Server package version (default: 6.0.0rc)
  --download-url URL          Override the official package URL
  --replace-config            Replace an existing Snell v6 config
  -y, --yes                   Non-interactive mode
  -h, --help                  Show this help

Environment equivalents:
  SNELLV6_PORT, SNELLV6_PSK, SNELLV6_LISTEN_MODE,
  SNELLV6_DNS_PREFERENCE, SNELLV6_DNS_SERVERS,
  SNELLV6_EGRESS_INTERFACE, SNELLV6_VERSION,
  SNELLV6_DOWNLOAD_URL

Examples:
  sudo bash install-snellv6.sh

  sudo bash install-snellv6.sh \
    --port 8443 --listen-mode dual --dns-preference prefer-ipv6

  sudo bash install-snellv6.sh -y \
    --port 8443 --psk 'replace-with-a-long-random-secret'
EOF
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

while (($# > 0)); do
  case "$1" in
    --port)
      [[ $# -ge 2 ]] || die '--port requires a value'
      PORT="$2"
      PORT_SET=true
      shift 2
      ;;
    --psk)
      [[ $# -ge 2 ]] || die '--psk requires a value'
      PSK="$2"
      PSK_SET=true
      shift 2
      ;;
    --listen-mode)
      [[ $# -ge 2 ]] || die '--listen-mode requires a value'
      LISTEN_MODE="$2"
      LISTEN_MODE_SET=true
      shift 2
      ;;
    --dns-preference)
      [[ $# -ge 2 ]] || die '--dns-preference requires a value'
      DNS_PREFERENCE="$2"
      DNS_PREFERENCE_SET=true
      shift 2
      ;;
    --dns)
      [[ $# -ge 2 ]] || die '--dns requires a value'
      DNS_SERVERS="$2"
      DNS_SERVERS_SET=true
      shift 2
      ;;
    --egress-interface)
      [[ $# -ge 2 ]] || die '--egress-interface requires a value'
      EGRESS_INTERFACE="$2"
      EGRESS_INTERFACE_SET=true
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || die '--version requires a value'
      SNELL_VERSION="$2"
      shift 2
      ;;
    --download-url)
      [[ $# -ge 2 ]] || die '--download-url requires a value'
      DOWNLOAD_URL="$2"
      shift 2
      ;;
    --replace-config)
      REPLACE_CONFIG=true
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
command_exists systemctl || die 'systemd is required'

if [[ -f "$CONFIG_FILE" && "$REPLACE_CONFIG" == false ]] && {
  $PORT_SET || $PSK_SET || $LISTEN_MODE_SET || $DNS_PREFERENCE_SET || $DNS_SERVERS_SET || $EGRESS_INTERFACE_SET
}; then
  die 'an existing Snell v6 config was found; add --replace-config to apply new configuration values'
fi

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64)
      printf 'amd64\n'
      ;;
    aarch64 | arm64)
      printf 'aarch64\n'
      ;;
    i386 | i486 | i586 | i686)
      printf 'i386\n'
      ;;
    *)
      return 1
      ;;
  esac
}

install_dependencies() {
  local packages=(ca-certificates curl unzip)

  if command_exists apt-get; then
    log 'Installing dependencies with apt-get'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends "${packages[@]}"
  elif command_exists dnf; then
    log 'Installing dependencies with dnf'
    dnf install -y "${packages[@]}"
  elif command_exists yum; then
    log 'Installing dependencies with yum'
    yum install -y "${packages[@]}"
  elif command_exists zypper; then
    log 'Installing dependencies with zypper'
    zypper --non-interactive install "${packages[@]}"
  else
    die "unsupported package manager; install manually: ${packages[*]}"
  fi
}

config_value() {
  local key="$1"
  local file="$2"
  awk -v wanted="$key" '
    /^[[:space:]]*[#;]/ { next }
    index($0, "=") {
      key = substr($0, 1, index($0, "=") - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == wanted) {
        value = substr($0, index($0, "=") + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' "$file"
}

prompt_yes_no() {
  local prompt="$1"
  local default_answer="$2"
  local answer=''

  if $ASSUME_YES; then
    [[ "$default_answer" == 'y' ]]
    return
  fi

  read -r -p "${prompt} " answer
  answer="${answer:-$default_answer}"
  [[ "$answer" == 'y' || "$answer" == 'Y' ]]
}

prompt_configuration() {
  local input=''
  local default_choice='1'

  if ! $PORT_SET; then
    read -r -p "监听端口 [${PORT}]: " input
    PORT="${input:-$PORT}"
  fi

  if ! $PSK_SET; then
    if [[ -n "$PSK" ]]; then
      read -r -s -p 'PSK [留空保留现有值]: ' input
    else
      read -r -s -p 'PSK [留空自动生成]: ' input
    fi
    printf '\n'
    [[ -n "$input" ]] && PSK="$input"
  fi

  if ! $LISTEN_MODE_SET; then
    case "$LISTEN_MODE" in
      ipv4) default_choice='1' ;;
      dual) default_choice='2' ;;
      ipv6) default_choice='3' ;;
    esac
    printf '监听地址：\n  1) 仅 IPv4\n  2) IPv4 + IPv6 双栈\n  3) 仅 IPv6\n'
    read -r -p "请选择 [${default_choice}]: " input
    input="${input:-$default_choice}"
    case "$input" in
      1) LISTEN_MODE='ipv4' ;;
      2) LISTEN_MODE='dual' ;;
      3) LISTEN_MODE='ipv6' ;;
      *) die 'invalid listen mode selection' ;;
    esac
  fi

  if ! $DNS_PREFERENCE_SET; then
    case "$DNS_PREFERENCE" in
      default) default_choice='1' ;;
      prefer-ipv4) default_choice='2' ;;
      prefer-ipv6) default_choice='3' ;;
      ipv4-only) default_choice='4' ;;
      ipv6-only) default_choice='5' ;;
    esac
    printf '目标域名地址族偏好：\n'
    printf '  1) default      自动选择\n'
    printf '  2) prefer-ipv4  优先 IPv4，失败时可用 IPv6\n'
    printf '  3) prefer-ipv6  优先 IPv6，失败时可用 IPv4\n'
    printf '  4) ipv4-only    仅使用 IPv4\n'
    printf '  5) ipv6-only    仅使用 IPv6\n'
    read -r -p "请选择 [${default_choice}]: " input
    input="${input:-$default_choice}"
    case "$input" in
      1) DNS_PREFERENCE='default' ;;
      2) DNS_PREFERENCE='prefer-ipv4' ;;
      3) DNS_PREFERENCE='prefer-ipv6' ;;
      4) DNS_PREFERENCE='ipv4-only' ;;
      5) DNS_PREFERENCE='ipv6-only' ;;
      *) die 'invalid DNS preference selection' ;;
    esac
  fi

  if ! $DNS_SERVERS_SET; then
    read -r -p "自定义 DNS，多个地址用逗号分隔 [留空使用系统 DNS，当前: ${DNS_SERVERS:-未设置}]: " input
    [[ -n "$input" ]] && DNS_SERVERS="$input"
  fi

  if ! $EGRESS_INTERFACE_SET; then
    read -r -p "绑定出口网卡 [留空自动选择，当前: ${EGRESS_INTERFACE:-未设置}]: " input
    [[ -n "$input" ]] && EGRESS_INTERFACE="$input"
  fi
}

validate_configuration() {
  [[ "$PORT" =~ ^[0-9]+$ ]] || die 'port must be numeric'
  ((PORT >= 1 && PORT <= 65535)) || die 'port must be between 1 and 65535'

  case "$LISTEN_MODE" in
    ipv4 | dual | ipv6) ;;
    *) die '--listen-mode must be ipv4, dual, or ipv6' ;;
  esac

  case "$DNS_PREFERENCE" in
    default | prefer-ipv4 | prefer-ipv6 | ipv4-only | ipv6-only) ;;
    *) die 'invalid --dns-preference value' ;;
  esac

  [[ "$SNELL_VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || die 'invalid version string'
  [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" =~ ^https://[^[:space:]]+$ ]] || die '--download-url must be an HTTPS URL'

  if [[ -z "$PSK" ]]; then
    PSK="$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  fi
  [[ "$PSK" =~ ^[A-Za-z0-9._~-]+$ ]] || die 'PSK may contain only A-Z, a-z, 0-9, dot, underscore, tilde, and hyphen'
  ((${#PSK} >= 12 && ${#PSK} <= 255)) || die 'PSK length must be between 12 and 255 characters'

  [[ ! "$DNS_SERVERS" =~ [[:space:]] ]] || die 'DNS server list cannot contain whitespace'
  [[ "$EGRESS_INTERFACE" =~ ^[A-Za-z0-9_.:-]*$ ]] || die 'invalid egress interface name'

  if [[ -n "$EGRESS_INTERFACE" ]] && command_exists ip && ! ip link show dev "$EGRESS_INTERFACE" >/dev/null 2>&1; then
    die "egress interface does not exist: ${EGRESS_INTERFACE}"
  fi
}

if [[ -f "$CONFIG_FILE" && "$REPLACE_CONFIG" == false ]]; then
  if prompt_yes_no '检测到现有 Snell v6 配置，是否原样保留？(Y/n，默认 Y):' 'y'; then
    KEEP_CONFIG=true
    log 'Keeping existing Snell v6 config unchanged'
  else
    REPLACE_CONFIG=true
  fi
fi

if [[ "$KEEP_CONFIG" == false && "$ASSUME_YES" == false ]]; then
  prompt_configuration
fi
validate_configuration

install_dependencies

SNELL_ARCH="$(detect_arch)" || die "unsupported architecture: $(uname -m)"
if [[ -z "$DOWNLOAD_URL" ]]; then
  DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${SNELL_ARCH}.zip"
fi

TEMP_DIR="$(mktemp -d /tmp/snellv6.XXXXXX)"
cleanup() {
  if [[ -n "${TEMP_DIR:-}" && "$TEMP_DIR" == /tmp/snellv6.* && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

log "Downloading Snell Server v6 package: ${DOWNLOAD_URL}"
curl --proto '=https' --tlsv1.2 -fL "$DOWNLOAD_URL" -o "$TEMP_DIR/snell.zip"
unzip -q "$TEMP_DIR/snell.zip" -d "$TEMP_DIR/unpacked"
[[ -f "$TEMP_DIR/unpacked/snell-server" ]] || die 'download package does not contain snell-server'
chmod 0755 "$TEMP_DIR/unpacked/snell-server"

DOWNLOADED_VERSION="$("$TEMP_DIR/unpacked/snell-server" --version 2>&1 || true)"
[[ "$DOWNLOADED_VERSION" == *'snell-server v6.'* ]] || die "downloaded binary is not Snell v6: ${DOWNLOADED_VERSION:-unknown}"
log "Downloaded: ${DOWNLOADED_VERSION}"

BACKUP_SUFFIX="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -f "$BINARY_FILE" ]]; then
  cp -a -- "$BINARY_FILE" "${BINARY_FILE}.bak.${BACKUP_SUFFIX}"
  log "Existing binary backed up to ${BINARY_FILE}.bak.${BACKUP_SUFFIX}"
fi
if [[ -f "$CONFIG_FILE" && "$KEEP_CONFIG" == false ]]; then
  cp -a -- "$CONFIG_FILE" "${CONFIG_FILE}.bak.${BACKUP_SUFFIX}"
  log "Existing config backed up to ${CONFIG_FILE}.bak.${BACKUP_SUFFIX}"
fi
if [[ -f "$SERVICE_FILE" ]]; then
  cp -a -- "$SERVICE_FILE" "${SERVICE_FILE}.bak.${BACKUP_SUFFIX}"
fi

systemctl stop "$SERVICE_NAME" 2>/dev/null || true
install -m 0755 "$TEMP_DIR/unpacked/snell-server" "$BINARY_FILE"

if [[ "$KEEP_CONFIG" == false ]]; then
  install -d -m 0755 "$CONFIG_DIR"
  TEMP_CONFIG="$(mktemp "${CONFIG_DIR}/snell-v6-server.conf.tmp.XXXXXX")"
  case "$LISTEN_MODE" in
    ipv4) LISTEN_VALUE="0.0.0.0:${PORT}" ;;
    dual) LISTEN_VALUE="0.0.0.0:${PORT},[::]:${PORT}" ;;
    ipv6) LISTEN_VALUE="[::]:${PORT}" ;;
  esac

  {
    printf '[snell-server]\n'
    printf 'listen = %s\n' "$LISTEN_VALUE"
    printf 'psk = %s\n' "$PSK"
    printf 'mode = default\n'
    [[ -n "$DNS_SERVERS" ]] && printf 'dns = %s\n' "$DNS_SERVERS"
    printf 'dns-ip-preference = %s\n' "$DNS_PREFERENCE"
    [[ -n "$EGRESS_INTERFACE" ]] && printf 'egress-interface = %s\n' "$EGRESS_INTERFACE"
  } >"$TEMP_CONFIG"
  chmod 0600 "$TEMP_CONFIG"
  mv -f -- "$TEMP_CONFIG" "$CONFIG_FILE"
fi

TEMP_SERVICE="$(mktemp /etc/systemd/system/snell-v6.service.tmp.XXXXXX)"
cat >"$TEMP_SERVICE" <<EOF
[Unit]
Description=Snell v6 Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=65535
ExecStart=${BINARY_FILE} -c ${CONFIG_FILE}
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$TEMP_SERVICE"
mv -f -- "$TEMP_SERVICE" "$SERVICE_FILE"

log 'Starting Snell v6'
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
if ! systemctl restart "$SERVICE_NAME"; then
  journalctl --no-pager -n 80 -u "$SERVICE_NAME" >&2 || true
  die 'Snell v6 failed to start; review the log above and restore the timestamped backups if needed'
fi

sleep 1
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
  journalctl --no-pager -n 80 -u "$SERVICE_NAME" >&2 || true
  die 'Snell v6 is not active; review the log above and restore the timestamped backups if needed'
fi

EFFECTIVE_LISTEN="$(config_value listen "$CONFIG_FILE")"
EFFECTIVE_PSK="$(config_value psk "$CONFIG_FILE")"
EFFECTIVE_DNS_PREFERENCE="$(config_value dns-ip-preference "$CONFIG_FILE")"
EFFECTIVE_PORT="$PORT"
if [[ "$EFFECTIVE_LISTEN" =~ :([0-9]+)(,|$) ]]; then
  EFFECTIVE_PORT="${BASH_REMATCH[1]}"
fi

printf '\nSnell v6 installation completed.\n'
printf 'Server version: %s\n' "$DOWNLOADED_VERSION"
printf 'Listen: %s\n' "${EFFECTIVE_LISTEN:-see $CONFIG_FILE}"
printf 'DNS preference: %s\n' "${EFFECTIVE_DNS_PREFERENCE:-default}"
printf 'Config: %s\n' "$CONFIG_FILE"
printf '\nSurge policy (replace <SERVER>):\n'
printf 'Snell-v6 = snell, <SERVER>, %s, psk=%s, version=6\n' "${EFFECTIVE_PORT:-<PORT>}" "${EFFECTIVE_PSK:-<PSK>}"
printf '\nUseful commands:\n'
printf '  systemctl status %s\n' "$SERVICE_NAME"
printf '  journalctl -u %s -f\n' "$SERVICE_NAME"
printf '  systemctl restart %s\n' "$SERVICE_NAME"
printf '\nRemember to allow TCP %s in the VPS provider security group.\n' "${EFFECTIVE_PORT:-the configured port}"
warn 'Snell v6 is currently beta. Keep the Surge client and server binary on compatible versions.'
