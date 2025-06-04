# Nginx Proxy Manager 一键安装脚本
[![作者](https://img.shields.io/badge/作者-jcnf--那坨-blue.svg)](https://ybfl.net)
[![TG频道](https://img.shields.io/badge/TG频道-@mffjc-宗绿色.svg)](https://t.me/mffjc)
[![TG交流群](https://img.shields.io/badge/TG交流群-点击加入-yellow.svg)](https://t.me/+TDz0jE2WcAvfgmLi)

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
*   具有 `root` 权限或可以执行 `sudo` 命令的用户 (脚本内部会尝试使用`sudo`提权)。
*   稳定的网络连接。

## 使用方法

### 快速开始 (一键安装)

选择以下任一命令在你的服务器上执行即可。脚本会自动下载并运行。
```bash
wget -O ng.sh https://raw.githubusercontent.com/Netflixxp/Nginx-Proxy-Manager/main/ng.sh && chmod +x ng.sh && ./ng.sh
```
或者
```bash
bash <(curl -sSL https://raw.githubusercontent.com/Netflixxp/Nginx-Proxy-Manager/main/ng.sh)
```
