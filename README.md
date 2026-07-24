# Shells

常用服务器脚本集合。

根目录保留可直接下载执行的脚本入口，详细使用文档放在 `docs/scripts/`。后续新增脚本时，同步新增一份对应文档，并在下面的索引里登记。

## 脚本索引

| 脚本 | 分类 | 用途 | 适用环境 | 文档 |
| --- | --- | --- | --- | --- |
| `install-hysteria2.sh` | 网络代理 / 服务安装 | 安装并配置 Hysteria 2 服务端 | Debian 13、systemd、`apt-get` | [使用文档](docs/scripts/install-hysteria2.md) |
| `install-snellv5.sh` | 网络代理 / 服务安装 | 安装或更新 Snell Server v5.0.1 | systemd Linux，支持 `apt-get` / `dnf` / `yum` / `zypper`，支持 `linux-amd64` / `linux-aarch64` | [使用文档](docs/scripts/install-snellv5.md) |
| `install-snellv6.sh` | 网络代理 / 服务安装 | 独立安装或更新 Snell Server v6 Beta | systemd Linux，支持 `apt-get` / `dnf` / `yum` / `zypper`，支持 `linux-amd64` / `linux-aarch64` / `linux-i386` | [使用文档](docs/scripts/install-snellv6.md) |

## 快速使用

以 `install-snellv5.sh` 为例：

```bash
wget https://raw.githubusercontent.com/anyforker/Shells/main/install-snellv5.sh
chmod +x install-snellv5.sh
sudo ./install-snellv5.sh
```

也可以直接用 Bash 执行：

```bash
sudo bash install-snellv5.sh
```

安装 Hysteria 2 前，需要先将域名解析到服务器。脚本可交互输入域名和 ACME 邮箱：

```bash
wget https://raw.githubusercontent.com/anyforker/Shells/main/install-hysteria2.sh
sudo bash install-hysteria2.sh
```

也可以通过参数执行：

```bash
sudo bash install-hysteria2.sh \
  --domain hy2.example.com \
  --email admin@example.com
```

## 目录约定

- `*.sh`：可直接下载执行的脚本。
- `docs/scripts/*.md`：每个脚本对应的使用文档。
- `docs/scripts/_template.md`：新增脚本文档模板。
- `README.md`：脚本总索引、目录规范和新增脚本流程。

## 新增脚本流程

1. 在根目录新增脚本，脚本名使用小写短横线命名，例如 `install-example.sh`。
2. 确认脚本可执行，并尽量让脚本具备明确的错误提示和重复执行处理。
3. 复制 `docs/scripts/_template.md`，在 `docs/scripts/` 下新增同名文档，例如 `docs/scripts/install-example.md`。
4. 文档建议包含：用途、适用环境、使用方法、交互项或参数、安装/写入位置、服务管理、注意事项。
5. 在 README 的“脚本索引”中新增一行，链接到对应文档。
