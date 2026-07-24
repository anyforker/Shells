# install-snellv6.sh

`install-snellv6.sh` 用于在 systemd Linux 服务器上安装或更新 Snell Server v6，并生成对应的 v6 服务端配置。

Snell v6 当前仍是 Beta。脚本默认安装官方 `v6.0.0rc`，并允许通过参数覆盖版本或下载地址。

## 适用环境

- Debian / Ubuntu：使用 `apt-get` 安装依赖。
- CentOS / RHEL / Fedora：使用 `yum` 或 `dnf` 安装依赖。
- openSUSE：使用 `zypper` 安装依赖。
- CPU 架构：`linux-amd64`、`linux-aarch64`、`linux-i386`。
- 需要 systemd。
- 需要 root 权限或通过 `sudo` 执行。
- 客户端需要支持 Snell v6，例如 Surge Mac 6.7.0+ 或 Surge iOS 5.20.0+。

## 使用方法

交互式安装：

```bash
wget https://raw.githubusercontent.com/anyforker/Shells/main/install-snellv6.sh
chmod +x install-snellv6.sh
sudo ./install-snellv6.sh
```

也可以通过参数执行：

```bash
sudo bash install-snellv6.sh \
  --port 8443 \
  --listen-mode dual \
  --dns-preference prefer-ipv6
```

非交互式安装：

```bash
sudo bash install-snellv6.sh -y \
  --port 8443 \
  --psk 'replace-with-a-long-random-secret' \
  --listen-mode ipv4 \
  --dns-preference ipv4-only
```

## 参数和交互项

| 参数 | 可选值 / 格式 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `--port` | `1-65535` | `80` | Snell TCP 监听端口 |
| `--psk` | 12-255 个安全 ASCII 字符 | 自动生成 | 客户端与服务端共享密钥 |
| `--listen-mode` | `ipv4` / `dual` / `ipv6` | `ipv4` | 服务端入站监听地址族 |
| `--dns-preference` | 见下表 | `ipv4-only` | 服务端连接目标站点时的地址族策略 |
| `--dns` | 逗号分隔的 DNS 地址 | 系统 DNS | 自定义服务端 DNS |
| `--egress-interface` | 网卡名 | 自动选择 | 绑定出站 TCP、UDP 和 DNS 网卡 |
| `--version` | 官方版本字符串 | `6.0.0rc` | 下载指定 Snell v6 包 |
| `--download-url` | HTTPS URL | 官方地址 | 覆盖下载地址 |
| `--replace-config` | 开关 | - | 重新生成已有的 Snell v6 配置 |
| `-y`, `--yes` | 开关 | 关闭 | 使用默认值并关闭交互 |

`--dns-preference` 支持：

- `default`：由 Snell 自动选择。
- `prefer-ipv4`：优先 IPv4，必要时可使用 IPv6。
- `prefer-ipv6`：优先 IPv6，必要时可使用 IPv4。
- `ipv4-only`：只连接 IPv4 目标。
- `ipv6-only`：只连接 IPv6 目标。

入站监听地址族与目标站点出站地址族相互独立。例如，`--listen-mode ipv4 --dns-preference prefer-ipv6` 表示客户端通过 IPv4 连接 VPS，但 VPS 优先通过 IPv6 连接目标站点。

对应的环境变量为：

```text
SNELLV6_PORT
SNELLV6_PSK
SNELLV6_LISTEN_MODE
SNELLV6_DNS_PREFERENCE
SNELLV6_DNS_SERVERS
SNELLV6_EGRESS_INTERFACE
SNELLV6_VERSION
SNELLV6_DOWNLOAD_URL
```

如果检测到已有 Snell v6 配置，交互模式会询问是否原样保留，非交互模式默认保留。使用 `--replace-config` 可以重新生成。脚本不会读取、迁移或修改 Snell v5 配置。

## 安装位置和影响范围

- Snell v6 二进制：`/usr/local/bin/snell-server-v6`
- Snell v6 配置文件：`/etc/snell/snell-v6-server.conf`
- systemd 服务：`/etc/systemd/system/snell-v6.service`
- 旧文件备份：原路径后追加 `.bak.<UTC 时间戳>`
- 网络端口：所选端口的 TCP 入站

v5 与 v6 共用 `/etc/snell/` 目录，但分别使用 `snell-v5-server.conf` 和 `snell-v6-server.conf`；systemd 服务分别为 `snell-v5.service` 和 `snell-v6.service`。v6 仍使用独立的 `/usr/local/bin/snell-server-v6`，因此可以与 v5 并存。客户端必须使用 `version=6`。

## Surge 客户端配置

安装完成后，脚本会输出类似配置：

```ini
Snell-v6 = snell, server.example.com, 8443, psk=YOUR_PSK, version=6
```

Snell v6 不支持 v5 的专用 QUIC Proxy Mode。普通 UDP Relay 仍由 Surge/Snell v6 支持，但通常建议在 Surge 中阻止 QUIC，让应用回退到 HTTP/2 over TCP。

## 服务管理

查看状态：

```bash
systemctl status snell-v6
```

查看日志：

```bash
journalctl -u snell-v6 -f
```

重启服务：

```bash
sudo systemctl restart snell-v6
```

## 注意事项

- Snell v6 目前仍是 Beta，后续版本可能发生不兼容修改；服务端和 Surge 客户端需要保持兼容。
- 安装完成后，需要在 VPS 提供商安全组以及本机防火墙中放行对应 TCP 端口。
- 选择 `dual` 或 `ipv6` 监听前，确认 VPS 已配置可用的 IPv6 地址。
- 选择 `prefer-ipv6` 或 `ipv6-only` 前，确认 VPS 存在公网 IPv6 地址、IPv6 默认路由和可用 DNS。
- 脚本不会自动修改 UFW、firewalld、nftables 或云平台安全组。
- 脚本不会读取或修改 Snell v5 的二进制、配置及 systemd 服务。
- v5 与 v6 并存时必须使用不同监听端口；如果 v5 已使用 TCP 80，请为 v6 选择其他端口。
- 已存在 v6 配置时，如需通过参数修改配置，必须同时使用 `--replace-config`，避免参数被静默忽略。
