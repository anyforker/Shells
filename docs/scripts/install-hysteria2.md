# install-hysteria2.sh

`install-hysteria2.sh` 用于在 Debian 13 服务器上安装并配置 Hysteria 2 服务端。脚本调用 Hysteria 官方安装器，配置 ACME 自动证书、密码认证、HTTP/3 伪装和 systemd 服务，并生成客户端连接配置。

## 适用环境

- 操作系统：Debian 13。其他 Debian 系发行版会显示警告，且不保证可用。
- 服务管理：systemd。
- 包管理器：`apt-get`。
- CPU 架构：以 Hysteria 官方安装器支持的架构为准。
- 权限要求：必须使用 root 用户或通过 `sudo` 执行。
- 网络要求：域名已添加 A/AAAA 记录并解析到当前服务器。

## 使用前准备

1. 准备一个完整域名，例如 `hy2.example.com`，并将其直接解析到服务器。
2. 在云服务商安全组中放行 Hysteria 的 UDP 监听端口，默认是 UDP `443`。
3. 根据 ACME 验证方式放行 TCP `80`（默认的 HTTP 验证）或 TCP `443`（TLS-ALPN 验证）。
4. 确认所选 ACME TCP 端口未被 Nginx、Apache 等其他程序占用。

> Hysteria 的默认监听端口是 UDP `443`，与 ACME TLS 验证使用的 TCP `443` 协议不同，可以同时使用。

## 使用方法

下载脚本后交互安装：

```bash
wget https://raw.githubusercontent.com/anyforker/Shells/main/install-hysteria2.sh
chmod +x install-hysteria2.sh
sudo ./install-hysteria2.sh
```

脚本会提示输入域名和 ACME 邮箱；其他配置使用默认值。

也可以直接通过 Bash 执行：

```bash
sudo bash install-hysteria2.sh
```

非交互安装示例：

```bash
sudo bash install-hysteria2.sh \
  --domain hy2.example.com \
  --email admin@example.com \
  --yes
```

启用 Salamander 混淆并指定连接密码：

```bash
sudo bash install-hysteria2.sh \
  --domain hy2.example.com \
  --email admin@example.com \
  --password 'replace-with-a-long-password' \
  --obfs-password 'replace-with-an-obfs-password'
```

## 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--domain DOMAIN` | 无 | 指向服务器的完整域名，必填；交互模式下可由提示输入。 |
| `--email EMAIL` | 无 | 申请 ACME 证书使用的邮箱，必填；交互模式下可由提示输入。 |
| `--port PORT` | `443` | Hysteria 2 的 UDP 监听端口，范围为 `1` 到 `65535`。 |
| `--password PASSWORD` | 自动生成 | 客户端认证密码，至少 16 个字符。 |
| `--masquerade URL` | `https://news.ycombinator.com/` | HTTP/3 伪装的上游 HTTP(S) 地址。 |
| `--acme-type http\|tls` | `http` | ACME 验证方式；`http` 使用 TCP `80`，`tls` 使用 TCP `443`。 |
| `--obfs-password PASSWORD` | 不启用 | 设置后启用 Salamander 混淆，密码至少 16 个字符。 |
| `--version VERSION` | 官方最新版 | 安装指定 Hysteria 版本，例如 `v2.9.2`。 |
| `--skip-dns-check` | 关闭 | 跳过脚本执行前的域名解析检查；不会绕过 ACME 对正确 DNS 解析的要求。 |
| `-y`, `--yes` | 关闭 | 非交互模式；此时必须通过参数或环境变量提供域名和邮箱。 |
| `-h`, `--help` | - | 显示帮助。 |

自定义密码仅允许字母、数字、点号、下划线、波浪线和短横线，并且至少包含 16 个字符。

## 环境变量

以下环境变量与对应参数等效：

| 环境变量 | 对应参数 |
| --- | --- |
| `HY2_DOMAIN` | `--domain` |
| `HY2_EMAIL` | `--email` |
| `HY2_PORT` | `--port` |
| `HY2_PASSWORD` | `--password` |
| `HY2_MASQUERADE_URL` | `--masquerade` |
| `HY2_ACME_TYPE` | `--acme-type` |
| `HY2_OBFS_PASSWORD` | `--obfs-password` |

例如：

```bash
sudo env \
  HY2_DOMAIN=hy2.example.com \
  HY2_EMAIL=admin@example.com \
  HY2_PORT=8443 \
  bash install-hysteria2.sh --yes
```

## 安装过程与生成文件

脚本会执行以下操作：

- 使用 `apt-get` 安装 `ca-certificates`、`curl`、`openssl`、`libcap2-bin` 和 `iproute2`。
- 下载并执行 Hysteria 官方安装器。
- 写入服务端配置 `/etc/hysteria/config.yaml`。
- 启用并重启 `hysteria-server.service`。
- 如果检测到已启用的 UFW 或 firewalld，自动放行 Hysteria UDP 端口和 ACME TCP 端口。
- 生成官方 Hysteria 客户端配置 `/root/hysteria2-client.yaml`。
- 生成 Mihomo/Velo 节点片段 `/root/hysteria2-mihomo.yaml`。
- 在安装结束时输出 `hysteria2://` 分享链接。

如果 `/etc/hysteria/config.yaml` 已存在，脚本会先将其备份为带 UTC 时间戳的 `config.yaml.bak.*` 文件，再写入新配置。两个 `/root` 下的客户端配置会直接更新。

## 客户端配置

安装完成后，可查看生成的配置：

```bash
sudo cat /root/hysteria2-client.yaml
sudo cat /root/hysteria2-mihomo.yaml
```

- `hysteria2-client.yaml` 供 Hysteria 官方客户端使用，默认在本机监听 SOCKS5 `127.0.0.1:1080`。
- `hysteria2-mihomo.yaml` 是 Mihomo/Velo 的 `proxies` 节点片段，可合并到现有配置中。
- 终端输出的分享链接可导入兼容 `hysteria2://` URI 的客户端。

这些文件和分享链接包含认证密码，应按敏感信息保管。

## 服务管理

查看状态：

```bash
systemctl status hysteria-server.service
```

实时查看日志：

```bash
journalctl -u hysteria-server.service -f
```

重启服务：

```bash
sudo systemctl restart hysteria-server.service
```

停止服务：

```bash
sudo systemctl stop hysteria-server.service
```

## 注意事项

- 脚本中的 DNS 检查只确认域名能够解析；请自行确认解析结果确实指向当前服务器，否则 ACME 证书申请会失败。
- 使用 CDN 或开启代理的 DNS 记录通常无法让 Hysteria 客户端直接连接源服务器，域名应直接解析到服务器地址。
- 脚本只自动配置已启用的 UFW 或 firewalld。使用 nftables、云安全组或其他防火墙时，需要手动放行端口。
- 选择 `--acme-type http` 时需保持 TCP `80` 可用；选择 `--acme-type tls` 时需保持 TCP `443` 可用。
- 重复执行会重新生成服务端和客户端配置；如果未显式传入 `--password`，每次都会生成新的认证密码。
- 脚本没有提供卸载参数。卸载前建议保存所需配置，并参考 Hysteria 官方安装器的卸载方式。
