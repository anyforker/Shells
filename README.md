# Shells

一些常用服务器安装脚本。

## install-snellv5.sh

`install-snellv5.sh` 用于在 systemd Linux 服务器上一键安装或更新 Snell Server v5.0.1。

已适配：

- Debian 12.7 / Ubuntu: `apt-get`
- CentOS / RHEL: `yum` 或 `dnf`
- openSUSE: `zypper`
- `linux-amd64`
- `linux-aarch64`

## 使用方法

在服务器上执行：

```bash
wget https://raw.githubusercontent.com/anyforker/Shells/main/install-snellv5.sh
chmod +x install-snellv5.sh
sudo ./install-snellv5.sh
```

也可以直接用 Bash 执行：

```bash
sudo bash install-snellv5.sh
```

## 安装过程

脚本会交互提示：

- 监听端口，默认 `80`
- 自定义 PSK 密码，留空则自动生成
- 是否开启 HTTP 混淆
- 混淆域名，默认 `www.bing.com`

如果检测到已有配置文件 `/etc/snell/snell-server.conf`，会询问是否保留原配置。

## 安装位置

脚本会写入：

- Snell 二进制：`/usr/local/bin/snell-server`
- 配置文件：`/etc/snell/snell-server.conf`
- systemd 服务：`/etc/systemd/system/snell.service`

## 服务管理

查看状态：

```bash
systemctl status snell
```

重启服务：

```bash
sudo systemctl restart snell
```

查看日志：

```bash
journalctl -u snell -e
```

停止服务：

```bash
sudo systemctl stop snell
```

## 注意事项

- 需要 root 权限或通过 `sudo` 执行。
- 服务器需要使用 systemd。
- 安装完成后，请在云服务器安全组或防火墙中放行对应 TCP 端口。
- 如果下载失败，请确认服务器可以访问 `https://dl.nssurge.com`。
