# Nginx Proxy Manager 一键安装脚本

这是一个用于在 Debian 11+ 或 Ubuntu 20.04+ 系统上一键安装 [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) 的 Shell 脚本。它可以帮助你快速部署 NPM，并自动处理依赖安装、Docker环境配置等步骤。

## 功能特点

*   **系统检测**: 自动检测操作系统版本 (推荐 Debian 11+ 或 Ubuntu 20.04+)。
*   **权限检查**: 提示用户是否拥有 root 权限，非 root 用户可能会安装失败。
*   **依赖安装**: 自动更新软件包列表并安装 `wget`, `curl`, `sudo`, `unzip`, `git`。
*   **Docker & Docker Compose**: 自动下载并安装最新版的 Docker 和 Docker Compose。
*   **版本选择**: 允许用户选择安装中文版 (`chishin/nginx-proxy-manager-zh`) 或英文原版 (`jc21/nginx-proxy-manager`) 的 Nginx Proxy Manager。
*   **自动配置**: 在 `/opt/ng` 目录下自动创建 `docker-compose.yml` 文件。
*   **后台启动**: 自动在后台启动 Nginx Proxy Manager 服务。
*   **信息提示**: 安装完成后，清晰显示 NPM 的访问地址和默认登录凭据。

## 系统要求

*   一台VPS（虚拟专用服务器）
*   推荐系统：Debian 11 (Bullseye) 或更高版本，Ubuntu 20.04 (Focal Fossa) 或更高版本。
*   具有 `root` 权限或可以执行 `sudo` 命令的用户。
*   稳定的网络连接。

## 使用方法

1.  **下载脚本**:
    你可以使用 `wget` 或 `curl` 下载脚本。

    ```bash
    # 使用 wget
    wget -O install_npm.sh https://raw.githubusercontent.com/Netflixxp/Nginx-Proxy-Manager/main/ng.sh

    # 或者使用 curl
    # curl -o install_npm.sh https://raw.githubusercontent.com/Netflixxp/Nginx-Proxy-Manager/main/ng.sh
    ```

2.  **赋予执行权限**:

    ```bash
    chmod +x install_npm.sh
    ```

3.  **运行脚本**:
    推荐使用 `root` 用户执行，或者使用 `sudo`。

    ```bash
    sudo ./install_npm.sh
    ```
    脚本会引导你完成后续步骤，包括选择 NPM 版本。

## 安装后

脚本成功执行后，Nginx Proxy Manager 将会启动。

*   **访问地址**: `http://<你的VPS IP地址>:81`
*   **默认登录邮箱**: `admin@example.com`
*   **默认登录密码**: `changeme`

**重要提示**: 首次登录后，请务必立即修改默认的管理员邮箱和密码！

### 防火墙设置

如果你的 VPS 启用了防火墙 (例如 `ufw`)，你需要确保以下端口是开放的：

*   `80/tcp` (HTTP)
*   `81/tcp` (NPM 管理面板)
*   `443/tcp` (HTTPS)

例如，使用 `ufw`:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 81/tcp
sudo ufw allow 443/tcp
sudo ufw reload

版本选择
脚本会提示你选择安装以下任一版本：
中文版:
Docker 镜像: chishin/nginx-proxy-manager-zh:release
特点: 界面汉化，更适合中文用户。
英文原版:
Docker 镜像: jc21/nginx-proxy-manager:latest
特点: 官方最新版本。
