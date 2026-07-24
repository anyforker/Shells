# install-snellv5.sh

`install-snellv5.sh` 用于在 systemd Linux 服务器上一键安装或更新 Snell Server v5.0.1。

## 适用环境

- Debian / Ubuntu：使用 `apt-get` 安装依赖。
- CentOS / RHEL / Fedora：使用 `yum` 或 `dnf` 安装依赖。
- openSUSE：使用 `zypper` 安装依赖。
- CPU 架构：`linux-amd64`、`linux-aarch64`。
- 需要 systemd。
- 需要 root 权限或通过 `sudo` 执行。

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

- 监听端口，默认 `80`。
- 自定义 PSK 密码，留空则自动生成。
- 是否开启 HTTP 混淆。
- 混淆域名，默认 `www.bing.com`。

如果检测到已有配置文件 `/etc/snell/snell-v5-server.conf`，脚本会询问是否保留原配置。

## 安装位置

脚本会写入：

- Snell 二进制：`/usr/local/bin/snell-server`
- 配置文件：`/etc/snell/snell-v5-server.conf`
- systemd 服务：`/etc/systemd/system/snell-v5.service`

## 服务管理

查看状态：

```bash
systemctl status snell-v5
```

重启服务：

```bash
sudo systemctl restart snell-v5
```

查看日志：

```bash
journalctl -u snell-v5 -e
```

停止服务：

```bash
sudo systemctl stop snell-v5
```

## 注意事项

- 安装完成后，需要在云服务器安全组或防火墙中放行对应 TCP 端口。
- 如果下载失败，请确认服务器可以访问 `https://dl.nssurge.com`。
- 如果已有配置文件并选择保留配置，脚本会继续更新 Snell 二进制和 systemd 服务。
