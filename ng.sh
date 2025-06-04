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

# --- Script ---

echo_info "Nginx Proxy Manager 一键安装脚本启动..."
echo_info "======================================="

# 1. 检测系统和权限
echo_info "1. 检测系统环境和权限..."
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

RECOMMENDED_DISTRO=false
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID

    echo_info "检测到系统: $PRETTY_NAME"

    if [[ "$OS" == "debian" && $(echo "$VERSION >= 11" | bc -l) -eq 1 ]] || \
       [[ "$OS" == "ubuntu" && $(echo "$VERSION >= 20.04" | bc -l) -eq 1 ]]; then
        RECOMMENDED_DISTRO=true
        echo_info "系统版本符合推荐要求。"
    else
        echo_warn "系统版本 ($PRETTY_NAME) 不是推荐的 Debian 11+ 或 Ubuntu 20.04+。脚本将继续尝试，但可能遇到兼容性问题。"
    fi
else
    echo_warn "无法检测到操作系统版本。脚本将继续尝试，但请确保您的系统兼容。"
fi

# 2. 更新系统并安装依赖
echo_info "2. 更新系统软件包列表并安装基础依赖 (wget, curl, sudo, unzip, git)..."
if $ROOT_USER; then
    apt update -y && apt install -y wget curl sudo unzip git
else
    sudo apt update -y && sudo apt install -y wget curl sudo unzip git
fi

if [ $? -ne 0 ]; then
    echo_error "依赖安装失败。请检查错误信息并重试。"
    exit 1
fi
echo_info "基础依赖安装完成。"

# 安装 Docker
echo_info "正在安装 Docker..."
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
    # 将当前用户添加到docker组，避免每次都用sudo (如果不是root)
    if ! $ROOT_USER; then
        echo_info "将当前用户 $(whoami) 添加到 docker 组..."
        sudo usermod -aG docker $(whoami)
        echo_warn "您可能需要重新登录或开启新的终端会话以使 docker 组成员资格生效。"
        echo_warn "或者，您可以暂时使用 'newgrp docker' 命令在当前会话激活，或继续使用 sudo 运行 docker 命令。"
    fi
fi

# 检查 Docker Compose
# 优先使用 docker compose (plugin), 其次 docker-compose (standalone)
COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
    echo_info "检测到 Docker Compose (plugin)。"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
    echo_info "检测到 Docker Compose (standalone)。"
else
    echo_warn "未检测到 Docker Compose. 尝试安装 Docker Compose plugin..."
    if $ROOT_USER; then
        apt install -y docker-compose-plugin
    else
        sudo apt install -y docker-compose-plugin
    fi
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        echo_info "Docker Compose (plugin) 安装成功。"
    else
        echo_error "Docker Compose 安装失败。请手动安装 Docker Compose (plugin 或 standalone) 后重试。"
        echo_info "可以尝试: sudo apt install docker-compose-plugin -y 或者 sudo apt install docker-compose -y"
        exit 1
    fi
fi


# 3. 创建目录和 docker-compose.yml
NPM_DIR="/opt/ng"
echo_info "3. 在 $NPM_DIR 下创建 Nginx Proxy Manager 配置目录..."
if $ROOT_USER; then
    mkdir -p "$NPM_DIR"
    cd "$NPM_DIR" || { echo_error "无法进入目录 $NPM_DIR"; exit 1; }
else
    sudo mkdir -p "$NPM_DIR"
    # 需要sudo来cd并写入文件，或者更改目录权限
    echo_info "后续 docker-compose.yml 将写入 $NPM_DIR。如果不是root用户，请确保您有权限。"
    # 为了简单起见，这里直接使用sudo操作目录，脚本后续操作需要以sudo执行docker-compose
fi

# 4. 用户选择版本
echo_info "4. 请选择 Nginx Proxy Manager 版本:"
echo "   1. 中文版 (chishin/nginx-proxy-manager-zh:release)"
echo "   2. 英文原版 (jc21/nginx-proxy-manager:latest)"
read -p "请输入选项 (1 或 2，默认为2): " NPM_CHOICE

NPM_IMAGE=""
DOCKER_COMPOSE_CONTENT=""

if [[ "$NPM_CHOICE" == "1" ]]; then
    echo_info "您选择了中文版。"
    NPM_IMAGE="chishin/nginx-proxy-manager-zh:release"
    DOCKER_COMPOSE_CONTENT=$(cat <<EOF
version: '3.8'
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
    NPM_IMAGE="jc21/nginx-proxy-manager:latest" # docker.io/ is optional
    DOCKER_COMPOSE_CONTENT=$(cat <<EOF
version: '3.8'
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

# 5. 写入 docker-compose.yml
echo_info "5. 正在写入 docker-compose.yml 到 $NPM_DIR/docker-compose.yml..."
if $ROOT_USER; then
    echo "$DOCKER_COMPOSE_CONTENT" > "${NPM_DIR}/docker-compose.yml"
else
    # 使用sudo tee写入，因为cd可能没有改变当前用户的权限上下文
    echo "$DOCKER_COMPOSE_CONTENT" | sudo tee "${NPM_DIR}/docker-compose.yml" > /dev/null
fi

if [ $? -ne 0 ]; then
    echo_error "写入 docker-compose.yml 失败。"
    exit 1
fi
echo_info "docker-compose.yml 创建成功。"

# 6. 启动 Nginx Proxy Manager
echo_info "6. 进入 $NPM_DIR 目录并启动 Nginx Proxy Manager..."
# 使用 sudo 运行 docker compose 命令，确保有权限操作 Docker daemon 和挂载卷
# cd 的操作对 sudo 内的命令可能无效，所以直接在命令中指定 compose 文件路径或工作目录
DOCKER_COMMAND_PREFIX=""
if ! $ROOT_USER && ! groups $(whoami) | grep -q '\bdocker\b'; then
    echo_warn "当前用户不在 docker 组，将使用 sudo 运行 Docker Compose 命令。"
    DOCKER_COMMAND_PREFIX="sudo "
fi

# 确保在正确的目录下执行，或者使用 -f 指定compose文件，并用 --project-directory 指定工作目录
# 简单起见，如果不是root，则用sudo执行cd和后续命令
if $ROOT_USER; then
    cd "$NPM_DIR" || { echo_error "无法进入目录 $NPM_DIR"; exit 1; }
    $COMPOSE_CMD up -d
else
    # 对于非root，sudo执行整个cd和docker-compose命令块
    sudo bash -c "cd \"$NPM_DIR\" && $COMPOSE_CMD up -d"
fi


if [ $? -ne 0 ]; then
    echo_error "启动 Nginx Proxy Manager 失败。请检查 $NPM_DIR 中的日志或运行 'sudo $COMPOSE_CMD -f $NPM_DIR/docker-compose.yml logs' 查看错误。"
    exit 1
fi

# 7. 打印登录信息
echo_info "7. Nginx Proxy Manager 正在启动中..."
echo_info "等待几秒钟让服务完全启动..."
sleep 10 # 等待容器启动

VPS_IP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org || hostname -I | awk '{print $1}')
if [ -z "$VPS_IP" ]; then
    echo_warn "无法自动获取 VPS 的公网 IP 地址。请手动查找。"
    VPS_IP="<你的VPS IP地址>"
fi

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
    echo_warn "提醒：由于您未使用root用户且未将 $(whoami) 加入docker组并重新登录，"
    echo_warn "后续管理NPM容器（如停止、重启）可能需要使用 'sudo $COMPOSE_CMD ...' 命令，"
    echo_warn "并在 '$NPM_DIR' 目录下执行，或者使用 'sudo $COMPOSE_CMD -f $NPM_DIR/docker-compose.yml ...'。"
fi

exit 0
