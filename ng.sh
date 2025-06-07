#!/bin/bash

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE_BG_WHITE_FG='\033[44;37m' # Blue background, White foreground
BOLD='\033[1m'
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

echo_highlight() {
    echo -e "${BLUE_BG_WHITE_FG}${BOLD}$1${NC}"
}


# --- Global Variables ---
NPM_DIR="/opt/ng"
DOCKER_COMPOSE_YML_PATH="${NPM_DIR}/docker-compose.yml"
ROOT_USER=false
CURRENT_USER_IN_DOCKER_GROUP=false # Is the current non-root user in the docker group?
COMPOSE_CMD="" # To be detected (docker compose or docker-compose)

# --- Docker and System Check Functions ---
check_root_status() {
    if [ "$(id -u)" -eq 0 ]; then
        ROOT_USER=true
    else
        ROOT_USER=false
    fi
}

check_docker_group_membership() {
    if ! $ROOT_USER && groups "$(whoami)" | grep -q '\bdocker\b'; then
        CURRENT_USER_IN_DOCKER_GROUP=true
    else
        CURRENT_USER_IN_DOCKER_GROUP=false
    fi
}

# Determine the command prefix for general sudo operations
get_sudo_prefix() {
    local prefix=""
    if ! $ROOT_USER; then
        prefix="sudo "
    fi
    echo "$prefix"
}

# Determine the command prefix specifically for Docker/Compose commands
get_docker_command_prefix() {
    local prefix=""
    if ! $ROOT_USER && ! $CURRENT_USER_IN_DOCKER_GROUP; then
        prefix="sudo " # Needs sudo if not root AND not in docker group
    fi
    echo "$prefix"
}

detect_compose_command() {
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD="" # Will be handled if needed
    fi
}


# --- Installation Function ---
install_npm() {
    echo_info "Nginx Proxy Manager 安装流程启动..."
    echo_info "======================================="

    SUDO_PREFIX=$(get_sudo_prefix) # General sudo prefix

    # 1. 检测系统和权限
    echo_info "1. 检测系统环境和权限..."
    if $ROOT_USER; then
        echo_info "当前用户是 root 用户。"
    else
        echo_warn "当前用户不是 root 用户。脚本将尝试使用 'sudo' 执行需要权限的命令。"
        if ! sudo -n true 2>/dev/null && ! $ROOT_USER ; then # Check if sudo requires password
             echo_warn "当前用户没有免密 sudo 权限，后续步骤中可能会提示输入密码。"
        fi
    fi

    RECOMMENDED_DISTRO=false
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID

        echo_info "检测到系统: $PRETTY_NAME"

        if ! command -v bc &> /dev/null; then
            echo_info "安装 'bc' 用于版本比较..."
            ${SUDO_PREFIX}apt update -y >/dev/null 2>&1
            ${SUDO_PREFIX}apt install -y bc
            if ! command -v bc &> /dev/null; then
                echo_error "'bc' 安装失败。无法进行精确的版本比较。"
            fi
        fi

        if command -v bc &> /dev/null; then
            if [[ "$OS" == "debian" && $(echo "$VERSION >= 11" | bc -l) -eq 1 ]] || \
               [[ "$OS" == "ubuntu" && $(echo "$VERSION >= 20.04" | bc -l) -eq 1 ]]; then
                RECOMMENDED_DISTRO=true
                echo_info "系统版本符合推荐要求。"
            else
                echo_warn "系统版本 ($PRETTY_NAME) 不是推荐的 Debian 11+ 或 Ubuntu 20.04+。脚本将继续尝试，但可能遇到兼容性问题。"
            fi
        else
            echo_warn "无法使用 'bc' 进行精确的版本比较。请手动确认系统版本。"
        fi
    else
        echo_warn "无法检测到操作系统版本。脚本将继续尝试，但请确保您的系统兼容。"
    fi

    # 2. 更新系统并安装依赖
    echo_info "2. 更新系统软件包列表并安装基础依赖 (wget, curl, sudo, unzip, git)..."
    ${SUDO_PREFIX}apt update -y && ${SUDO_PREFIX}apt install -y wget curl sudo unzip git

    if [ $? -ne 0 ]; then
        echo_error "依赖安装失败。请检查错误信息并重试。"
        exit 1
    fi
    echo_info "基础依赖安装完成。"

    echo_info "正在安装 Docker..."
    if command -v docker &> /dev/null; then
        echo_info "Docker 已经安装。"
    else
        ${SUDO_PREFIX}curl -fsSL https://get.docker.com | ${SUDO_PREFIX}bash -s docker
        if [ $? -ne 0 ]; then
            echo_error "Docker 安装失败。请检查错误信息并重试。"
            exit 1
        fi
        echo_info "Docker 安装成功。"
        if ! $ROOT_USER; then
            echo_info "将当前用户 $(whoami) 添加到 docker 组..."
            sudo usermod -aG docker "$(whoami)"
            echo_warn "您可能需要重新登录或开启新的终端会话以使 docker 组成员资格生效。"
            echo_warn "或者，您可以暂时使用 'newgrp docker' 命令在当前会话激活。"
            check_docker_group_membership
        fi
    fi
    check_docker_group_membership

    if [ -z "$COMPOSE_CMD" ]; then
        detect_compose_command
    fi

    if [ -z "$COMPOSE_CMD" ]; then
        echo_warn "未检测到 Docker Compose. 尝试安装 Docker Compose plugin..."
        ${SUDO_PREFIX}apt install -y docker-compose-plugin
        detect_compose_command
        if [ -n "$COMPOSE_CMD" ]; then
            echo_info "Docker Compose (plugin) 安装成功: $COMPOSE_CMD"
        else
            echo_error "Docker Compose 安装失败。请手动安装 Docker Compose (plugin 或 standalone) 后重试。"
            echo_info "可以尝试: sudo apt install docker-compose-plugin -y 或者 sudo apt install docker-compose -y"
            exit 1
        fi
    else
         echo_info "检测到 Docker Compose: $COMPOSE_CMD"
    fi


    # 3. 创建目录
    echo_info "3. 在 $NPM_DIR 下创建 Nginx Proxy Manager 配置目录..."
    ${SUDO_PREFIX}mkdir -p "$NPM_DIR"

    # 4. 用户选择版本 - Enhanced visibility
    echo_info "4. 请选择 Nginx Proxy Manager 版本:"
    echo -e "   ${BLUE_BG_WHITE_FG}${BOLD} 1) 中文版 ${NC} (镜像: chishin/nginx-proxy-manager-zh:release)"
    echo -e "   ${BLUE_BG_WHITE_FG}${BOLD} 2) 英文原版 ${NC} (镜像: jc21/nginx-proxy-manager:latest)"
    read -p "请输入选项 (1 或 2，默认为2): " NPM_CHOICE_INPUT

    NPM_IMAGE_VAR=""
    DOCKER_COMPOSE_CONTENT_VAR=""

    # Removed 'version' attribute from docker-compose.yml content
    if [[ "$NPM_CHOICE_INPUT" == "1" ]]; then
        echo_info "您选择了中文版。"
        NPM_IMAGE_VAR="chishin/nginx-proxy-manager-zh:release"
        DOCKER_COMPOSE_CONTENT_VAR=$(cat <<EOF
services:
  app:
    image: '${NPM_IMAGE_VAR}'
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
        NPM_IMAGE_VAR="jc21/nginx-proxy-manager:latest"
        DOCKER_COMPOSE_CONTENT_VAR=$(cat <<EOF
services:
  app:
    image: '${NPM_IMAGE_VAR}'
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
    echo_info "5. 正在写入 docker-compose.yml 到 ${DOCKER_COMPOSE_YML_PATH}..."
    echo "$DOCKER_COMPOSE_CONTENT_VAR" | ${SUDO_PREFIX}tee "${DOCKER_COMPOSE_YML_PATH}" > /dev/null

    if [ $? -ne 0 ]; then
        echo_error "写入 docker-compose.yml 失败。"
        exit 1
    fi
    echo_info "docker-compose.yml 创建成功。"

    # 6. 启动 Nginx Proxy Manager
    echo_info "6. 进入 $NPM_DIR 目录并启动 Nginx Proxy Manager..."
    DOCKER_CMD_EXEC_PREFIX=$(get_docker_command_prefix)

    COMMAND_TO_RUN="cd \"$NPM_DIR\" && $COMPOSE_CMD up -d"
    if ! ${DOCKER_CMD_EXEC_PREFIX}bash -c "$COMMAND_TO_RUN"; then
        echo_error "启动 Nginx Proxy Manager 失败。"
        echo_error "请检查日志: '${DOCKER_CMD_EXEC_PREFIX}bash -c \"cd \\\"$NPM_DIR\\\" && $COMPOSE_CMD logs\"'"
        exit 1
    fi

    # 7. 打印登录信息
    echo_info "7. Nginx Proxy Manager 正在启动中..."
    echo_info "等待几秒钟让服务完全启动..."
    sleep 10

    VPS_IP=$(curl -s4 --connect-timeout 5 ifconfig.me || curl -s4 --connect-timeout 5 api.ipify.org || hostname -I | awk '{print $1}')
    if [ -z "$VPS_IP" ]; then
        echo_warn "无法自动获取 VPS 的公网 IP 地址。请手动查找。"
        VPS_IP="<你的VPS IP地址>"
    fi

    echo_info "============================================================"
    echo_highlight "Nginx Proxy Manager 安装并启动成功！"
    echo_info "请通过浏览器访问管理面板:"
    echo -e "${GREEN}URL:      http://${VPS_IP}:81${NC}"
    echo_info "默认登录凭据:"
    echo -e "${GREEN}Email:    admin@example.com${NC}"
    echo -e "${GREEN}Password: changeme${NC}"
    echo_warn "首次登录后，请务必修改默认的邮箱和密码！如果无法打开，请检查vps防护墙81端口是否打开！"
    echo_info "============================================================"

    if ! $ROOT_USER && ! $CURRENT_USER_IN_DOCKER_GROUP; then
        echo_warn "提醒：由于您未使用root用户且当前会话可能未将 $(whoami) 加入docker组，"
        echo_warn "后续管理NPM容器（如停止、重启）可能需要使用 '${DOCKER_CMD_EXEC_PREFIX}$COMPOSE_CMD ...' 命令，"
        echo_warn "并在 '$NPM_DIR' 目录下执行，或者使用 '${DOCKER_CMD_EXEC_PREFIX}$COMPOSE_CMD -f $DOCKER_COMPOSE_YML_PATH ...'。"
    fi
}

# --- Uninstallation Function ---
uninstall_npm() {
    echo_info "Nginx Proxy Manager 卸载流程启动..."
    echo_info "==================================="

    SUDO_PREFIX=$(get_sudo_prefix)
    DOCKER_CMD_EXEC_PREFIX=$(get_docker_command_prefix)

    if [ -z "$COMPOSE_CMD" ]; then
        detect_compose_command
    fi

    if [ ! -f "$DOCKER_COMPOSE_YML_PATH" ]; then
        echo_warn "在 ${NPM_DIR} 未找到 docker-compose.yml 文件。"
        echo_warn "Nginx Proxy Manager 可能未通过此脚本安装，或者配置文件已被移除。"
        if [ -d "$NPM_DIR" ]; then
            read -p "是否尝试清理 ${NPM_DIR} 目录及其所有内容? (y/N): " clean_dir_anyway
            if [[ "$clean_dir_anyway" == "y" || "$clean_dir_anyway" == "Y" ]]; then
                read -p "$(echo_warn "警告：这将删除 ${NPM_DIR} 及其所有内容。确定吗?") (y/N): " confirm_delete_dir
                if [[ "$confirm_delete_dir" == "y" || "$confirm_delete_dir" == "Y" ]]; then
                    echo_info "正在删除目录 ${NPM_DIR}..."
                    ${SUDO_PREFIX}rm -rf "$NPM_DIR"
                    echo_info "目录 ${NPM_DIR} 已删除。"
                else
                    echo_info "保留目录 ${NPM_DIR}。"
                fi
            else
                echo_info "保留目录 ${NPM_DIR}。"
            fi
        else
            echo_info "目录 ${NPM_DIR} 不存在，无需操作。"
        fi
        echo_info "卸载操作完成。"
        exit 0
    fi

    if [ -n "$COMPOSE_CMD" ]; then
        echo_info "正在进入 ${NPM_DIR} 并停止/移除 Nginx Proxy Manager 容器..."
        COMMAND_TO_RUN="cd \"$NPM_DIR\" && $COMPOSE_CMD down --remove-orphans"
        if ${DOCKER_CMD_EXEC_PREFIX}bash -c "$COMMAND_TO_RUN"; then
            echo_info "Nginx Proxy Manager 容器已成功停止并移除。"
        else
            echo_error "停止/移除容器失败。请检查错误信息。"
            read -p "是否仍要继续卸载（删除文件和目录）? (y/N): " continue_uninstall
            if [[ "$continue_uninstall" != "y" && "$continue_uninstall" != "Y" ]]; then
                echo_info "卸载操作已中止。"
                exit 1
            fi
        fi
    else
        echo_warn "未检测到 Docker Compose 命令 ($COMPOSE_CMD 未设置)。"
        echo_warn "无法自动停止和移除 Docker 容器。您可能需要手动操作。"
        read -p "是否仍要继续卸载（删除文件和目录）? (y/N): " continue_uninstall_no_compose
        if [[ "$continue_uninstall_no_compose" != "y" && "$continue_uninstall_no_compose" != "Y" ]]; then
            echo_info "卸载操作已中止。"
            exit 1
        fi
    fi

    read -p "是否删除 Nginx Proxy Manager 的数据卷 (${NPM_DIR}/data, ${NPM_DIR}/letsencrypt)? (y/N): " remove_volumes_q
    if [[ "$remove_volumes_q" == "y" || "$remove_volumes_q" == "Y" ]]; then
        echo_info "正在删除数据卷..."
        ${SUDO_PREFIX}rm -rf "${NPM_DIR}/data"
        ${SUDO_PREFIX}rm -rf "${NPM_DIR}/letsencrypt"
        echo_info "数据卷已删除。"
    else
        echo_info "保留数据卷。"
    fi

    read -p "是否删除 Nginx Proxy Manager 的配置文件 (${DOCKER_COMPOSE_YML_PATH})? (y/N): " remove_compose_file_q
    if [[ "$remove_compose_file_q" == "y" || "$remove_compose_file_q" == "Y" ]]; then
        echo_info "正在删除 ${DOCKER_COMPOSE_YML_PATH}..."
        ${SUDO_PREFIX}rm -f "${DOCKER_COMPOSE_YML_PATH}"
        echo_info "${DOCKER_COMPOSE_YML_PATH} 已删除。"
    else
        echo_info "保留 ${DOCKER_COMPOSE_YML_PATH}。"
    fi

    if [ -d "$NPM_DIR" ]; then
        dir_is_empty=false
        if [ -z "$(${SUDO_PREFIX}ls -A $NPM_DIR)" ]; then
            dir_is_empty=true
        fi

        if $dir_is_empty; then
            echo_info "目录 ${NPM_DIR} 现在为空。"
            read -p "是否删除空的 Nginx Proxy Manager 主目录 ${NPM_DIR}? (y/N): " remove_empty_main_dir
            if [[ "$remove_empty_main_dir" == "y" || "$remove_empty_main_dir" == "Y" ]]; then
                echo_info "正在删除主目录 ${NPM_DIR}..."
                ${SUDO_PREFIX}rmdir "${NPM_DIR}"
                if [ $? -eq 0 ]; then
                    echo_info "主目录 ${NPM_DIR} 已删除。"
                else
                    echo_warn "删除目录 ${NPM_DIR} 失败 (使用 rmdir)。可能目录非空或权限问题。请手动检查。"
                fi
            else
                echo_info "保留主目录 ${NPM_DIR}。"
            fi
        elif [[ "$remove_volumes_q" == "y" || "$remove_volumes_q" == "Y" ]] || [[ "$remove_compose_file_q" == "y" || "$remove_compose_file_q" == "Y" ]]; then
             read -p "$(echo_warn "目录 ${NPM_DIR} 中可能还包含其他文件或子目录。是否强制删除整个 ${NPM_DIR} 目录及其所有内容?") (y/N): " remove_non_empty_main_dir
            if [[ "$remove_non_empty_main_dir" == "y" || "$remove_non_empty_main_dir" == "Y" ]]; then
                echo_info "正在强制删除主目录 ${NPM_DIR} 及其所有内容..."
                ${SUDO_PREFIX}rm -rf "${NPM_DIR}"
                echo_info "主目录 ${NPM_DIR} 已删除。"
            else
                echo_info "保留主目录 ${NPM_DIR}。"
            fi
        else
             echo_info "由于未选择删除其主要内容 (数据卷、配置文件)，且目录非空或未确认删除，${NPM_DIR} 目录将保留。"
        fi
    fi
    echo_info "Nginx Proxy Manager 卸载流程完成。"
}


# --- Main Menu Function ---
main_menu() {
    check_root_status
    check_docker_group_membership
    detect_compose_command

    echo_highlight "Nginx Proxy Manager 管理脚本"
    echo_info "==============================="
    echo "请选择操作:"
    echo -e "  ${BLUE_BG_WHITE_FG}${BOLD} 1) 安装 Nginx Proxy Manager ${NC}"
    echo -e "  ${BLUE_BG_WHITE_FG}${BOLD} 2) 卸载 Nginx Proxy Manager ${NC}"
    echo -e "  ${BLUE_BG_WHITE_FG}${BOLD} 3) 退出脚本 ${NC}"
    read -p "请输入选项 [1-3]: " main_choice_input

    case $main_choice_input in
        1)
            install_npm
            ;;
        2)
            uninstall_npm
            ;;
        3)
            echo_info "退出脚本。"
            exit 0
            ;;
        *)
            echo_error "无效选项。请输入 1, 2 或 3。"
            main_menu
            ;;
    esac
}

# --- Script Entry Point ---
main_menu
