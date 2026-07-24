#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

# ====================================================
# Snell Server v5.0.1 自动安装脚本 (Debian/CentOS 兼容版)
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { printf "%b[INFO]%b %s\n" "$GREEN" "$NC" "$1"; }
warn() { printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$1"; }
error() { printf "%b[ERROR]%b %s\n" "$RED" "$NC" "$1" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

install_dependencies() {
    local packages=(wget unzip ca-certificates)

    if command_exists apt-get; then
        info "检测到 apt-get，使用 Debian/Ubuntu 方式安装依赖..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update || error "apt 软件源更新失败。"
        apt-get install -y "${packages[@]}" || error "依赖安装失败。"
    elif command_exists dnf; then
        info "检测到 dnf，使用 RHEL/Fedora 方式安装依赖..."
        dnf install -y "${packages[@]}" || error "依赖安装失败。"
    elif command_exists yum; then
        info "检测到 yum，使用 CentOS/RHEL 方式安装依赖..."
        yum install -y "${packages[@]}" || error "依赖安装失败。"
    elif command_exists zypper; then
        info "检测到 zypper，使用 openSUSE 方式安装依赖..."
        zypper --non-interactive install "${packages[@]}" || error "依赖安装失败。"
    else
        error "未找到支持的包管理器，请手动安装: ${packages[*]}"
    fi
}

detect_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            return 1
            ;;
    esac
}

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    error "请以 root 权限运行此脚本。"
fi

if ! command_exists systemctl; then
    error "未检测到 systemctl，本脚本需要在 systemd 系统上运行。"
fi

# 2. 重复安装/配置检查
CONF_FILE="/etc/snell/snell-v5-server.conf"
SERVICE_NAME="snell-v5"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
KEEP_CONFIG=false
SNELL_PORT=""
RANDOM_PSK=""
OBFS_HOST=""
OBFS_SETTING=""

if [ -f "$CONF_FILE" ]; then
    printf "%b检测到已存在配置文件。%b\n" "$YELLOW" "$NC"
    read -r -p "是否保留原有配置（端口、密码、混淆）？(y/n, 默认 y): " KEEP_OLD
    KEEP_OLD=${KEEP_OLD:-y}
    [[ "$KEEP_OLD" == "y" || "$KEEP_OLD" == "Y" ]] && KEEP_CONFIG=true
fi

# 3. 交互式配置
if [ "$KEEP_CONFIG" = false ]; then
    # 端口
    printf "%b请输入监听端口 [默认 80]:%b\n" "$YELLOW" "$NC"
    read -r INPUT_PORT
    SNELL_PORT=${INPUT_PORT:-80}

    # 密码
    printf "%b请输入自定义密码 PSK [留空自动生成]:%b " "$YELLOW" "$NC"
    read -r -s INPUT_PSK
    printf "\n"
    RANDOM_PSK=$INPUT_PSK

    # 混淆选择
    printf "%b是否开启 HTTP 混淆？(y/n, 默认 n):%b\n" "$YELLOW" "$NC"
    read -r ENABLE_OBFS
    ENABLE_OBFS=${ENABLE_OBFS:-n}

    if [[ "$ENABLE_OBFS" == "y" || "$ENABLE_OBFS" == "Y" ]]; then
        printf "%b请输入混淆域名 (obfs-host) [默认 www.bing.com]:%b\n" "$YELLOW" "$NC"
        read -r INPUT_HOST
        OBFS_HOST=${INPUT_HOST:-www.bing.com}
        OBFS_SETTING="obfs = http\nobfs-host = ${OBFS_HOST}"
    else
        OBFS_SETTING="obfs = off"
    fi
fi

# 4. 安装依赖
info "检查依赖..."
install_dependencies

# 5. 下载并安装二进制文件
info "正在下载 Snell v5.0.1..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
SNELL_ARCH=$(detect_arch) || error "暂不支持当前系统架构: $(uname -m)"
DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v5.0.1-linux-${SNELL_ARCH}.zip"
wget -O /tmp/snell.zip "$DOWNLOAD_URL" || error "下载失败。"

unzip -o /tmp/snell.zip -d /usr/local/bin/ || error "解压失败。"
if [ ! -f /usr/local/bin/snell-server ]; then
    error "解压后未找到 /usr/local/bin/snell-server，请检查下载包内容。"
fi
chmod +x /usr/local/bin/snell-server || error "设置执行权限失败。"
rm -f /tmp/snell.zip

# 6. 配置文件生成
if [ "$KEEP_CONFIG" = false ]; then
    mkdir -p /etc/snell
    if [ -z "$RANDOM_PSK" ]; then
        RANDOM_PSK=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n 1)
    fi
    cat > "$CONF_FILE" <<EOF
[snell-server]
listen = 0.0.0.0:${SNELL_PORT}
psk = ${RANDOM_PSK}
ipv6 = false
$(printf "%b" "$OBFS_SETTING")
EOF
    info "新配置文件已生成。"
else
    info "保留原配置文件。"
    # 提取信息用于最后显示
    SNELL_PORT=$(awk -F'[: ]+' '/^[[:space:]]*listen[[:space:]]*=/{print $NF; exit}' "$CONF_FILE")
    RANDOM_PSK=$(awk -F= '/^[[:space:]]*psk[[:space:]]*=/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "$CONF_FILE")
    OBFS_HOST=$(awk -F= '/^[[:space:]]*obfs-host[[:space:]]*=/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "$CONF_FILE")
fi

# 7. Systemd 服务配置
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Snell v5 Proxy Service
After=network.target

[Service]
Type=simple
User=root
LimitNOFILE=65535
ExecStart=/usr/local/bin/snell-server -c ${CONF_FILE}
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

# 8. 启动服务
info "启动服务..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" --now || error "服务启动/启用失败，请检查日志: journalctl -u ${SERVICE_NAME}"

# 9. 结果展示
if systemctl is-active --quiet "$SERVICE_NAME"; then
    printf "\n%b================================================\n" "$GREEN"
    printf "Snell Server 安装/更新 成功！\n"
    printf "端口: %s\n" "$SNELL_PORT"
    printf "密码: %s\n" "$RANDOM_PSK"
    if [ -n "$OBFS_HOST" ]; then
        printf "混淆: http / %s\n" "$OBFS_HOST"
    else
        printf "混淆: 关闭\n"
    fi
    printf "================================================%b\n" "$NC"
    printf "请在控制台安全组放行 TCP %s 端口\n" "$SNELL_PORT"
else
    error "启动失败，请检查日志: journalctl -u ${SERVICE_NAME}"
fi
