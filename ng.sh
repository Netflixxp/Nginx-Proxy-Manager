#!/bin/bash

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---
echo_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

echo_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

echo_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Function to check if a port is in use
check_port_usage() {
    local port_to_check=$1
    if ss -tuln | grep -q ":${port_to_check}\b"; then # \b for word boundary
        echo_error "端口 ${port_to_check} 已被占用。"
        echo_info "请先停止占用该端口的服务。你可以使用以下命令查找占用进程:"
        echo_info "  sudo ss -tulnp | grep ':${port_to_check}'"
        echo_info "  sudo netstat -tulnp | grep ':${port_to_check}' (如果 ss 不可用)"
        return 1 # Port is in use
    fi
    return 0 # Port is free
}


# --- Script ---

echo_info "Nginx Proxy Manager 一键安装脚本启动..."
echo_info "======================================="

# 1. 检测用户权限
echo_info "1. 检测用户权限..."
ROOT_USER=false
if [ "$(id -u)" -eq 0 ]; then
    ROOT_USER=true
    echo_info "当前用户是 root 用户。"
else
    echo_warn "当前用户不是 root 用户。部分操作可能需要 sudo 权限，或者安装可能会失败。"
    if ! sudo -n true 2>/dev/null; then
        echo_warn "当前用户没有免密 sudo 权限，后续步骤中可能会提示输入密码。"
    fi
fi

# 2. 更新系统并安装依赖 (包括 bc)
echo_info "2. 更新系统软件包列表并安装基础依赖 (wget, curl, sudo, unzip, git, bc, net-tools)..."
# net-tools is for netstat as a fallback for ss
PACKAGES_TO_INSTALL="wget curl sudo unzip git bc net-tools"
if $ROOT_USER; then
    apt update -y && apt install -y $PACKAGES_TO_INSTALL
else
    sudo apt update -y && sudo apt install -y $PACKAGES_TO_INSTALL
fi

if [ $? -ne 0 ]; then
    echo_error "基础依赖安装失败。请检查错误信息并重试。"
    exit 1
fi
echo_info "基础依赖安装完成。"

# 3. 检测系统版本
echo_info "3. 检测系统版本..."
RECOMMENDED_DISTRO=false
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID

    echo_info "检测到系统: $PRETTY_NAME"

    if command -v bc &> /dev/null; then
        IS_DEBIAN_OK=0
        IS_UBUNTU_OK=0
        if [[ "$OS" == "debian" && $(echo "$VERSION >= 11" | bc -l) -eq 1 ]]; then IS_DEBIAN_OK=1; fi
        if [[ "$OS" == "ubuntu" && $(echo "$VERSION >= 20.04" | bc -l) -eq 1 ]]; then IS_UBUNTU_OK=1; fi

        if [[ $IS_DEBIAN_OK -eq 1 || $IS_UBUNTU_OK -eq 1 ]]; then
            RECOMMENDED_DISTRO=true
            echo_info "系统版本符合推荐要求。"
        else
            echo_warn "系统版本 ($PRETTY_NAME) 不是推荐的 Debian 11+ 或 Ubuntu 20.04+。脚本将继续尝试，但可能遇到兼容性问题。"
        fi
    else
        echo_warn "无法找到 'bc' 命令。无法精确判断系统版本是否满足推荐要求。脚本将继续尝试。"
    fi
else
    echo_warn "无法读取 /etc/os-release。无法检测到操作系统版本。脚本将继续尝试。"
fi


# 4. 安装 Docker
echo_info "4. 正在安装 Docker..."
if command -v docker &> /dev/null; then
    echo_info "Docker 已经安装。"
else
    if $ROOT_USER; then
        curl -fsSL https://get.docker.com | bash -s docker
    else
        curl -fsSL https://get.docker.com | sudo bash -s docker
    fi

    if [ $? -ne 0 ]; then
        echo_error "Docker 安装失败。请检查错误信息并重试。"
        exit 1
    fi
    echo_info "Docker 安装成功。"
    if ! $ROOT_USER; then
        echo_info "将当前用户 $(whoami) 添加到 docker 组..."
        sudo usermod -aG docker $(whoami)
        echo_warn "您可能需要重新登录或开启新的终端会话以使 docker 组成员资格生效。"
    fi
fi

# 检查 Docker Compose
COMPOSE_CMD=""
echo_info "检查 Docker Compose..."
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
    echo_info "检测到 Docker Compose (plugin)。"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
    echo_info "检测到 Docker Compose (standalone)。"
else
    echo_warn "未检测到 Docker Compose. 尝试安装 Docker Compose plugin..."
    if $ROOT_USER; then apt install -y docker-compose-plugin; else sudo apt install -y docker-compose-plugin; fi
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"; echo_info "Docker Compose (plugin) 安装成功。"
    else
        echo_error "Docker Compose 安装失败。请手动安装 Docker Compose (plugin 或 standalone) 后重试。"
        exit 1
    fi
fi


# 5. 创建目录
NPM_DIR="/opt/ng"
echo_info "5. 在 $NPM_DIR 下创建 Nginx Proxy Manager 配置目录..."
if $ROOT_USER; then mkdir -p "$NPM_DIR"; else sudo mkdir -p "$NPM_DIR"; fi

# 6. 用户选择版本
echo_info "6. 请选择 Nginx Proxy Manager 版本:"
echo "   1. 中文版 (chishin/nginx-proxy-manager-zh:release)"
echo "   2. 英文原版 (jc21/nginx-proxy-manager:latest)"
read -p "请输入选项 (1 或 2，默认为2): " NPM_CHOICE

# Removed 'version' attribute from docker-compose content
if [[ "$NPM_CHOICE" == "1" ]]; then
    echo_info "您选择了中文版。"
    NPM_IMAGE="chishin/nginx-proxy-manager-zh:release"
    DOCKER_COMPOSE_CONTENT=$(cat <<EOF
services:
  app:
    image: '${NPM_IMAGE}'
    restart: always
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
)
else
    echo_info "您选择了英文原版 (或输入无效，默认选择英文版)。"
    NPM_IMAGE="jc21/nginx-proxy-manager:latest"
    DOCKER_COMPOSE_CONTENT=$(cat <<EOF
services:
  app:
    image: '${NPM_IMAGE}'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
)
fi

# 7. 写入 docker-compose.yml
echo_info "7. 正在写入 docker-compose.yml 到 $NPM_DIR/docker-compose.yml..."
if $ROOT_USER; then
    echo "$DOCKER_COMPOSE_CONTENT" > "${NPM_DIR}/docker-compose.yml"
else
    echo "$DOCKER_COMPOSE_CONTENT" | sudo tee "${NPM_DIR}/docker-compose.yml" > /dev/null
fi
if [ $? -ne 0 ]; then echo_error "写入 docker-compose.yml 失败。"; exit 1; fi
echo_info "docker-compose.yml 创建成功。"

# 8. 检查端口占用
echo_info "8. 检查所需端口 (80, 81, 443) 是否被占用..."
PORTS_TO_CHECK=(80 81 443)
PORT_CONFLICT=false
for port in "${PORTS_TO_CHECK[@]}"; do
    if ! check_port_usage "$port"; then
        PORT_CONFLICT=true
    fi
done

if $PORT_CONFLICT; then
    echo_error "存在端口冲突，无法继续安装。请解决端口占用问题后重试。"
    exit 1
else
    echo_info "所需端口均未被占用。"
fi

# 9. 启动 Nginx Proxy Manager
echo_info "9. 进入 $NPM_DIR 目录并启动 Nginx Proxy Manager..."
DOCKER_COMMAND_PREFIX=""
if ! $ROOT_USER && ! groups $(whoami) | grep -q '\bdocker\b'; then
    DOCKER_COMMAND_PREFIX="sudo "
fi

if $ROOT_USER; then
    (cd "$NPM_DIR" && $DOCKER_COMMAND_PREFIX$COMPOSE_CMD up -d)
else
    sudo bash -c "cd \"$NPM_DIR\" && $COMPOSE_CMD up -d"
fi

if [ $? -ne 0 ]; then
    echo_error "启动 Nginx Proxy Manager 失败。请检查 $NPM_DIR 中的日志或运行 '${DOCKER_COMMAND_PREFIX}${COMPOSE_CMD} -f $NPM_DIR/docker-compose.yml logs' 查看错误。"
    exit 1
fi

# 10. 打印登录信息
echo_info "10. Nginx Proxy Manager 正在启动中..."
echo_info "等待几秒钟让服务完全启动..."
sleep 10

VPS_IP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org || hostname -I | awk '{print $1}')
if [ -z "$VPS_IP" ]; then VPS_IP="<你的VPS IP地址>"; fi

echo_info "============================================================"
echo_info "Nginx Proxy Manager 安装并启动成功！"
echo_info "请通过浏览器访问管理面板:"
echo_info "URL:      http://${VPS_IP}:81"
echo_info "默认登录凭据:"
echo_info "Email:    admin@example.com"
echo_info "Password: changeme"
echo_info "首次登录后，请务必修改默认的邮箱和密码！"
echo_info "============================================================"

if ! $ROOT_USER && ! groups $(whoami) | grep -q '\bdocker\b'; then
    echo_warn "提醒：后续管理NPM容器可能需要使用 'sudo $COMPOSE_CMD ...' 命令。"
fi

exit 0
