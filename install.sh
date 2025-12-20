#!/bin/bash
#===============================================================================
# Site Manager 安装脚本
# 支持: Debian 10/11/12, Ubuntu 20.04/22.04/24.04
# 用法: curl -sSL https://raw.githubusercontent.com/xxx/site_manager/master/install.sh | bash
#===============================================================================

set -euo pipefail

#---------------------------------------
# 颜色定义
#---------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

#---------------------------------------
# 全局变量
#---------------------------------------
VERSION="2.0.0"
GITHUB_REPO="samuel25555/site_manager"
BASE_DIR="/www"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_MODE=false

# 检测本地模式（从源码目录运行）
if [[ -f "$SCRIPT_DIR/bin/site" && -d "$SCRIPT_DIR/lib" ]]; then
    LOCAL_MODE=true
fi
PANEL_PORT=""
PANEL_PATH=""
ADMIN_USER=""
ADMIN_PASS=""
MYSQL_ROOT_PASS=""

# 选择的软件
INSTALL_NGINX=true
INSTALL_PHP=""
INSTALL_MYSQL=false
INSTALL_REDIS=false
INSTALL_SUPERVISOR=false
INSTALL_DOCKER=false
INSTALL_PYTHON=false

#---------------------------------------
# 工具函数
#---------------------------------------
print_banner() {
    [[ -t 1 ]] && clear 2>/dev/null || true
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║     ███████╗██╗████████╗███████╗    ███╗   ███╗ ██████╗   ║"
    echo "║     ██╔════╝██║╚══██╔══╝██╔════╝    ████╗ ████║██╔════╝   ║"
    echo "║     ███████╗██║   ██║   █████╗      ██╔████╔██║██║  ███╗  ║"
    echo "║     ╚════██║██║   ██║   ██╔══╝      ██║╚██╔╝██║██║   ██║  ║"
    echo "║     ███████║██║   ██║   ███████╗    ██║ ╚═╝ ██║╚██████╔╝  ║"
    echo "║     ╚══════╝╚═╝   ╚═╝   ╚══════╝    ╚═╝     ╚═╝ ╚═════╝   ║"
    echo "║                                                           ║"
    echo "║              Site Manager 安装程序 v${VERSION}               ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测软件是否已安装，返回: 0=安装, 1=跳过
# 用法: check_installed "软件名" "版本信息" && return
check_installed() {
    local name="$1"
    local version="$2"
    log_warn "$name 已安装 ($version)"
    read -p "  [s]跳过 / [r]重装 [s]: " choice
    case "${choice:-s}" in
        r|R) return 1 ;;  # 重装
        *)   log_info "跳过 $name"; return 0 ;;  # 跳过
    esac
}

random_string() {
    local length=${1:-12}
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

random_password() {
    # 生成包含大小写字母、数字和特殊字符的密码
    local length=${1:-16}
    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%'
    local password=""
    for ((i=0; i<length; i++)); do
        password+="${chars:RANDOM%${#chars}:1}"
    done
    echo "$password"
}

random_port() {
    # 生成 10000-60000 之间的随机端口
    local port
    while true; do
        port=$((RANDOM % 50000 + 10000))
        if ! ss -tlnp | grep -q ":$port "; then
            echo "$port"
            return
        fi
    done
}

#---------------------------------------
# 系统检测
#---------------------------------------
check_system() {
    echo ""
    echo -e "${WHITE}[1/6] 检测系统环境...${NC}"
    echo ""

    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
    log_success "root 权限: 是"

    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        log_error "无法检测操作系统"
        exit 1
    fi

    # 验证支持的系统
    case "$OS_ID" in
        debian)
            if [[ "$OS_VERSION" =~ ^(10|11|12)$ ]]; then
                log_success "系统: Debian $OS_VERSION"
            else
                log_error "不支持的 Debian 版本: $OS_VERSION (支持 10/11/12)"
                exit 1
            fi
            ;;
        ubuntu)
            if [[ "$OS_VERSION" =~ ^(20.04|22.04|24.04)$ ]]; then
                log_success "系统: Ubuntu $OS_VERSION"
            else
                log_error "不支持的 Ubuntu 版本: $OS_VERSION (支持 20.04/22.04/24.04)"
                exit 1
            fi
            ;;
        *)
            log_error "不支持的操作系统: $OS_ID (支持 Debian/Ubuntu)"
            exit 1
            ;;
    esac

    # 检测架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    log_success "架构: $ARCH"

    # 检测内存
    MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    log_success "内存: ${MEM_TOTAL}MB"

    # 检测磁盘
    DISK_FREE=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    log_success "磁盘可用: ${DISK_FREE}GB"

    if [[ $DISK_FREE -lt 5 ]]; then
        log_warn "磁盘空间不足 5GB，可能影响安装"
    fi
}

#---------------------------------------
# 选择安装目录
#---------------------------------------
choose_directory() {
    echo ""
    echo -e "${WHITE}[2/6] 安装配置...${NC}"
    echo ""

    read -p "安装目录 [默认: /www]: " input_dir
    BASE_DIR="${input_dir:-/www}"

    if [[ -d "$BASE_DIR" ]]; then
        log_warn "目录 $BASE_DIR 已存在"
        read -p "是否继续? (y/n) [y]: " confirm
        if [[ "${confirm:-y}" != "y" ]]; then
            exit 0
        fi
    fi

    log_success "安装目录: $BASE_DIR"
}

#---------------------------------------
# 选择软件 (交互式复选框)
#---------------------------------------
choose_software() {
    echo ""
    echo -e "${WHITE}[3/6] 选择要安装的软件...${NC}"
    echo ""

    # 检查 whiptail 是否可用
    if ! command -v whiptail &>/dev/null; then
        log_info "安装 whiptail..."
        apt-get install -y -qq whiptail > /dev/null 2>&1
    fi

    # 使用 whiptail 显示复选框
    local choices
    choices=$(whiptail --title "Site Manager 安装程序" \
        --checklist "选择要安装的软件 (空格选择，回车确认):" 20 60 12 \
        "nginx"      "Nginx Web服务器" ON \
        "php83"      "PHP 8.3" OFF \
        "php80"      "PHP 8.0" ON \
        "php74"      "PHP 7.4" OFF \
        "php73"      "PHP 7.3" OFF \
        "mariadb"    "MariaDB 数据库" ON \
        "redis"      "Redis 缓存" OFF \
        "supervisor" "Supervisor 进程守护" ON \
        "docker"     "Docker 容器" OFF \
        "uv"         "uv Python项目管理" OFF \
        3>&1 1>&2 2>&3)

    # 用户取消
    if [[ $? -ne 0 ]]; then
        log_error "安装已取消"
        exit 0
    fi

    # 解析选择
    INSTALL_NGINX=false
    INSTALL_PHP=""
    INSTALL_MYSQL=false
    INSTALL_REDIS=false
    INSTALL_SUPERVISOR=false
    INSTALL_DOCKER=false
    INSTALL_PYTHON=false

    for choice in $choices; do
        choice=$(echo "$choice" | tr -d '"')
        case $choice in
            nginx)      INSTALL_NGINX=true ;;
            php83)      INSTALL_PHP="$INSTALL_PHP 8.3" ;;
            php80)      INSTALL_PHP="$INSTALL_PHP 8.0" ;;
            php74)      INSTALL_PHP="$INSTALL_PHP 7.4" ;;
            php73)      INSTALL_PHP="$INSTALL_PHP 7.3" ;;
            mariadb)    INSTALL_MYSQL=true ;;
            redis)      INSTALL_REDIS=true ;;
            supervisor) INSTALL_SUPERVISOR=true ;;
            docker)     INSTALL_DOCKER=true ;;
            uv)         INSTALL_PYTHON=true ;;
        esac
    done

    INSTALL_PHP=$(echo "$INSTALL_PHP" | xargs)  # trim

    # 显示确认信息
    echo ""
    log_info "已选择的软件:"
    $INSTALL_NGINX && echo "  - Nginx: 是" || echo "  - Nginx: 否"
    [[ -n "$INSTALL_PHP" ]] && echo "  - PHP: $INSTALL_PHP" || echo "  - PHP: 否"
    $INSTALL_MYSQL && echo "  - MariaDB: 是" || echo "  - MariaDB: 否"
    $INSTALL_REDIS && echo "  - Redis: 是" || echo "  - Redis: 否"
    $INSTALL_SUPERVISOR && echo "  - Supervisor: 是" || echo "  - Supervisor: 否"
    $INSTALL_DOCKER && echo "  - Docker: 是" || echo "  - Docker: 否"
    $INSTALL_PYTHON && echo "  - uv: 是" || echo "  - uv: 否"
    echo ""

    read -p "确认安装? (y/n) [y]: " confirm
    if [[ "${confirm:-y}" != "y" ]]; then
        choose_software
    fi
}

#---------------------------------------
# 创建目录结构
#---------------------------------------
create_directories() {
    echo ""
    echo -e "${WHITE}[4/6] 创建目录结构...${NC}"
    echo ""

    # 创建 www 用户
    if ! id -u www &>/dev/null; then
        useradd -r -s /sbin/nologin -d "$BASE_DIR/wwwroot" www
        log_success "创建用户: www"
    else
        log_info "用户 www 已存在"
    fi

    # 创建目录
    local dirs=(
        "$BASE_DIR"
        "$BASE_DIR/wwwroot"
        "$BASE_DIR/wwwlogs"
        "$BASE_DIR/backup/site"
        "$BASE_DIR/backup/db"
        "$BASE_DIR/server"
        "$BASE_DIR/ssl"
        "$BASE_DIR/panel/data"
        "$BASE_DIR/vhost/nginx"
        "$BASE_DIR/vhost/php-fpm"
        "$BASE_DIR/vhost/supervisor"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log_success "创建目录: $dir"
    done

    # 设置权限
    chown -R www:www "$BASE_DIR/wwwroot"
    chown -R www:www "$BASE_DIR/wwwlogs"
    chown -R www:www "$BASE_DIR/backup"
    chmod 755 "$BASE_DIR"

    log_success "目录权限设置完成"
}

#---------------------------------------
# 安装基础依赖
#---------------------------------------
install_dependencies() {
    echo ""
    log_info "更新软件源..."
    apt-get update -qq

    log_info "安装基础依赖..."
    apt-get install -y -qq \
        curl wget git unzip tar gzip \
        ca-certificates gnupg lsb-release \
        supervisor cron \
        ufw \
        > /dev/null 2>&1 || { log_error "依赖安装失败"; exit 1; }

    log_success "基础依赖安装完成"
}

#---------------------------------------
# 安装 Nginx
#---------------------------------------
install_nginx() {
    if ! $INSTALL_NGINX; then return; fi

    echo ""
    # 检测是否已安装
    if command -v nginx &>/dev/null; then
        check_installed "Nginx" "$(nginx -v 2>&1 | cut -d'/' -f2)" && return
    fi

    log_info "安装 Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1 || { log_error "Nginx 安装失败"; exit 1; }

    # 配置 nginx 用户为 www
    sed -i 's/^user .*/user www;/' /etc/nginx/nginx.conf

    # 配置 nginx 包含站点目录
    if ! grep -q "include $BASE_DIR/vhost/nginx" /etc/nginx/nginx.conf; then
        sed -i "/http {/a\\    include $BASE_DIR/vhost/nginx/*.conf;" /etc/nginx/nginx.conf
    fi

    systemctl enable nginx
    systemctl restart nginx

    log_success "Nginx 安装完成"
}

#---------------------------------------
# 安装 PHP
#---------------------------------------
install_php() {
    if [[ -z "$INSTALL_PHP" ]]; then return; fi

    echo ""
    # 添加 PHP 源 (Sury)
    if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then
        log_info "添加 PHP 源..."
        curl -sSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/php-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/php-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        apt-get update -qq
    fi

    local extensions="fpm cli common mysql curl gd mbstring xml zip bcmath redis intl"

    for version in $INSTALL_PHP; do
        # 检测是否已安装
        if command -v "php$version" &>/dev/null; then
            check_installed "PHP $version" "$("php$version" -v 2>&1 | head -1 | cut -d' ' -f2)" && continue
        fi

        log_info "安装 PHP $version..."

        local pkgs=""
        for ext in $extensions; do
            pkgs="$pkgs php${version}-${ext}"
        done

        apt-get install -y -qq $pkgs > /dev/null 2>&1 || { log_error "PHP $version 安装失败"; exit 1; }

        # 配置 PHP-FPM
        local fpm_conf="/etc/php/${version}/fpm/pool.d/www.conf"
        if [[ -f "$fpm_conf" ]]; then
            sed -i "s/^user = .*/user = www/" "$fpm_conf"
            sed -i "s/^group = .*/group = www/" "$fpm_conf"
            sed -i "s/^listen.owner = .*/listen.owner = www/" "$fpm_conf"
            sed -i "s/^listen.group = .*/listen.group = www/" "$fpm_conf"
        fi

        systemctl enable "php${version}-fpm"
        systemctl restart "php${version}-fpm"

        log_success "PHP $version 安装完成"
    done
}

#---------------------------------------
# 安装 MariaDB
#---------------------------------------
install_database() {
    if ! $INSTALL_MYSQL; then return; fi

    echo ""
    # 检测是否已安装
    if command -v mariadb &>/dev/null || command -v mysql &>/dev/null; then
        local db_ver=$(mysql -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        check_installed "MariaDB/MySQL" "$db_ver" && return
    fi

    log_info "安装 MariaDB..."
    MYSQL_ROOT_PASS=$(random_password 16)

    apt-get install -y -qq mariadb-server mariadb-client > /dev/null 2>&1 || { log_error "MariaDB 安装失败"; exit 1; }

    # 启动服务
    systemctl enable mariadb
    systemctl start mariadb

    # 设置 root 密码
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';" 2>/dev/null || \
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MYSQL_ROOT_PASS');" 2>/dev/null || true
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    log_success "MariaDB 安装完成"
}

#---------------------------------------
# 安装 Redis
#---------------------------------------
install_redis() {
    if ! $INSTALL_REDIS; then return; fi

    echo ""
    # 检测是否已安装
    if command -v redis-server &>/dev/null; then
        check_installed "Redis" "$(redis-server --version | grep -oE 'v=[0-9.]+' | cut -d= -f2)" && return
    fi

    log_info "安装 Redis..."
    apt-get install -y -qq redis-server > /dev/null 2>&1 || { log_error "Redis 安装失败"; exit 1; }

    systemctl enable redis-server
    systemctl restart redis-server

    log_success "Redis 安装完成"
}

#---------------------------------------
# 安装 Supervisor
#---------------------------------------
install_supervisor() {
    if ! $INSTALL_SUPERVISOR; then return; fi

    echo ""
    # 检测是否已安装
    if command -v supervisord &>/dev/null; then
        check_installed "Supervisor" "$(supervisord -v 2>&1)" && return
    fi

    log_info "安装 Supervisor..."
    apt-get install -y -qq supervisor > /dev/null 2>&1 || { log_error "Supervisor 安装失败"; exit 1; }

    # 创建配置目录
    mkdir -p "$BASE_DIR/vhost/supervisor"

    # 配置 supervisor 包含自定义目录
    if ! grep -q "$BASE_DIR/vhost/supervisor" /etc/supervisor/supervisord.conf 2>/dev/null; then
        echo "[include]" >> /etc/supervisor/supervisord.conf
        echo "files = $BASE_DIR/vhost/supervisor/*.conf" >> /etc/supervisor/supervisord.conf
    fi

    systemctl enable supervisor
    systemctl restart supervisor

    log_success "Supervisor 安装完成"
}

#---------------------------------------
# 安装 Docker
#---------------------------------------
install_docker() {
    if ! $INSTALL_DOCKER; then return; fi

    echo ""
    # 检测是否已安装
    if command -v docker &>/dev/null; then
        check_installed "Docker" "$(docker -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" && return
    fi

    log_info "安装 Docker..."

    # 获取系统 ID
    source /etc/os-release

    # 安装依赖
    apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1

    # 添加 Docker GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$ID/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加 Docker 仓库
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1 || { log_error "Docker 安装失败"; exit 1; }

    # 启动服务
    systemctl enable docker
    systemctl start docker

    # 添加 www 用户到 docker 组
    usermod -aG docker www 2>/dev/null || true

    log_success "Docker 安装完成"
}

#---------------------------------------
# 安装 uv (Python 项目管理)
#---------------------------------------
install_python() {
    if ! $INSTALL_PYTHON; then return; fi

    echo ""
    # 检测是否已安装
    if command -v uv &>/dev/null; then
        check_installed "uv" "$(uv --version 2>&1 | cut -d' ' -f2)" && return
    fi

    log_info "安装 uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh > /dev/null 2>&1 || { log_error "uv 安装失败"; exit 1; }

    # 创建全局符号链接
    ln -sf /root/.local/bin/uv /usr/local/bin/uv 2>/dev/null || true
    ln -sf /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true

    log_success "uv 安装完成"
}

#---------------------------------------
# 配置防火墙
#---------------------------------------
setup_firewall() {
    echo ""
    log_info "配置防火墙..."

    # 生成随机端口
    PANEL_PORT=$(random_port)

    # 配置 ufw（增量添加规则，不重置已有配置）
    if ! ufw status | grep -q "Status: active"; then
        log_info "启用防火墙..."
        ufw default deny incoming
        ufw default allow outgoing
    else
        log_info "防火墙已启用，添加规则..."
    fi

    # 开放必要端口
    # 检测 SSH 端口
    SSH_PORT=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
    SSH_PORT=${SSH_PORT:-22}
    ufw allow "$SSH_PORT/tcp" comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow "$PANEL_PORT/tcp" comment 'Site Manager Panel'

    # 启用防火墙
    echo "y" | ufw enable > /dev/null 2>&1

    log_success "防火墙配置完成"
    log_success "面板端口: $PANEL_PORT"
}

#---------------------------------------
# 安装面板
#---------------------------------------
install_panel() {
    echo ""
    echo -e "${WHITE}[5/6] 安装 Site Manager 面板...${NC}"
    echo ""

    # 生成安全入口和凭据
    PANEL_PATH="/sm_$(random_string 8)"
    ADMIN_USER="user_$(random_string 6)"
    ADMIN_PASS=$(random_password 16)

    # 下载面板 (这里假设已有预编译的二进制)
    log_info "下载面板程序..."

    local download_url="https://github.com/$GITHUB_REPO/releases/latest/download/site_manager_panel_linux_$ARCH"

    if ! curl -sSL -o "$BASE_DIR/panel/site_manager_panel" "$download_url" 2>/dev/null; then
        log_warn "无法下载预编译版本，尝试从源码编译..."

        # 安装 Go
        if ! command -v go &>/dev/null; then
            log_info "安装 Go..."
            local go_version="1.22.4"
            curl -sSL "https://go.dev/dl/go${go_version}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
            export PATH=$PATH:/usr/local/go/bin
        fi

        # 克隆并编译
        log_info "编译面板..."
        cd /tmp
        rm -rf site_manager
        git clone "https://github.com/$GITHUB_REPO.git" site_manager
        cd site_manager/panel

        # 安装 Node.js 和编译前端
        if ! command -v node &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            apt-get install -y -qq nodejs > /dev/null 2>&1 || { log_error "依赖安装失败"; exit 1; }
        fi

        cd web && npm install && npm run build && cd ..
        CGO_ENABLED=1 go build -o "$BASE_DIR/panel/site_manager_panel" .
    fi

    chmod +x "$BASE_DIR/panel/site_manager_panel"

    # 创建配置文件
    cat > "$BASE_DIR/panel/config.yaml" << EOF
# Site Manager 面板配置
port: $PANEL_PORT
base_path: "$PANEL_PATH"
base_dir: "$BASE_DIR"
jwt_secret: "$(random_string 64)"
cors_origins: "*"
EOF

    # 创建数据库并设置初始用户
    # 面板首次启动时会自动创建
    cat > "$BASE_DIR/panel/init_user.sql" << EOF
INSERT OR REPLACE INTO users (username, password_hash, created_at)
VALUES ('$ADMIN_USER', '$(echo -n "$ADMIN_PASS" | openssl passwd -6 -stdin)', datetime('now'));
EOF

    # 安装 CLI 工具
    log_info "安装命令行工具..."

    if $LOCAL_MODE; then
        # 本地模式：直接从源码目录创建符号链接
        log_info "检测到本地源码目录，使用符号链接..."
        ln -sf "$SCRIPT_DIR/bin/site" /usr/local/bin/site
        chmod +x "$SCRIPT_DIR/bin/site"
        if [[ -f "$SCRIPT_DIR/bin/backup_cron.sh" ]]; then
            chmod +x "$SCRIPT_DIR/bin/backup_cron.sh"
        fi
        log_success "CLI 工具已链接: $SCRIPT_DIR/bin/site -> /usr/local/bin/site"
    else
        # 远程模式：从 GitHub 下载
        if [[ ! -d /tmp/site_manager ]]; then
            log_info "下载 CLI 工具..."
            cd /tmp
            git clone --depth 1 "https://github.com/$GITHUB_REPO.git" site_manager 2>/dev/null || true
        fi

        if [[ -d /tmp/site_manager ]]; then
            cp -r /tmp/site_manager/bin "$BASE_DIR/"
            cp -r /tmp/site_manager/lib "$BASE_DIR/"
            cp -r /tmp/site_manager/config "$BASE_DIR/"

            # 更新配置中的 BASE_DIR
            sed -i "s|BASE_DIR=.*|BASE_DIR=\"$BASE_DIR\"|" "$BASE_DIR/config/site_manager.conf"

            ln -sf "$BASE_DIR/bin/site" /usr/local/bin/site
            chmod +x "$BASE_DIR/bin/site"
            if [[ -f "$BASE_DIR/bin/backup_cron.sh" ]]; then
                chmod +x "$BASE_DIR/bin/backup_cron.sh"
            fi
        fi
    fi

    # 创建 systemd 服务
    cat > /etc/systemd/system/site-manager.service << EOF
[Unit]
Description=Site Manager Panel
After=network.target

[Service]
Type=simple
WorkingDirectory=$BASE_DIR/panel
ExecStart=$BASE_DIR/panel/site_manager_panel
Restart=always
RestartSec=5
Environment=CONFIG_PATH=$BASE_DIR/panel/config.yaml

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    #systemctl enable site-manager  # 默认不自动启动
    #systemctl start site-manager   # 需要时用 sm 1 启动

    log_success "面板安装完成"
}

#---------------------------------------
# 完成安装
#---------------------------------------
finish_install() {
    echo ""
    echo -e "${WHITE}[6/6] 安装完成！${NC}"
    echo ""

    # 获取服务器 IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║           Site Manager 安装成功！                         ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}                                                           ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Web 面板: 默认未启动，需要时执行 sm 1       ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                           ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  用户名: ${YELLOW}${ADMIN_USER}${NC}                               ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  密  码: ${YELLOW}${ADMIN_PASS}${NC}                       ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                           ${GREEN}║${NC}"
    if [[ -n "$MYSQL_ROOT_PASS" ]]; then
    echo -e "${GREEN}║${NC}  MariaDB root 密码: ${YELLOW}${MYSQL_ROOT_PASS}${NC}         ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                           ${GREEN}║${NC}"
    fi
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}                                                           ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${RED}⚠️  请立即保存以上信息！此信息只显示一次！${NC}             ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                           ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  命令行工具: ${CYAN}site --help${NC}                             ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                           ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 保存安装信息到文件
    cat > "$BASE_DIR/panel/install_info.txt" << EOF
Site Manager 安装信息
=====================
安装时间: $(date)
Web 面板: 默认未启动，需要时执行 sm 1
用户名: ${ADMIN_USER}
密码: ${ADMIN_PASS}
$([ -n "$MYSQL_ROOT_PASS" ] && echo "MariaDB root 密码: ${MYSQL_ROOT_PASS}")

请妥善保管此文件！
EOF
    chmod 600 "$BASE_DIR/panel/install_info.txt"

    log_info "安装信息已保存到: $BASE_DIR/panel/install_info.txt"

    # 清理临时文件
    rm -rf /tmp/site_manager 2>/dev/null || true
    log_info "临时文件已清理"
}

#---------------------------------------
# 快速设置（仅配置 CLI 工具）
#---------------------------------------
setup_cli_only() {
    print_banner
    echo ""
    log_info "快速设置模式：仅配置 CLI 工具"
    echo ""

    if ! $LOCAL_MODE; then
        log_error "快速设置仅支持从源码目录运行"
        log_info "请先克隆项目: git clone https://github.com/$GITHUB_REPO.git"
        exit 1
    fi

    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi

    # 创建符号链接
    ln -sf "$SCRIPT_DIR/bin/site" /usr/local/bin/site
    chmod +x "$SCRIPT_DIR/bin/site"
    if [[ -f "$SCRIPT_DIR/bin/backup_cron.sh" ]]; then
        chmod +x "$SCRIPT_DIR/bin/backup_cron.sh"
    fi

    echo ""
    log_success "CLI 工具配置完成！"
    log_success "符号链接: $SCRIPT_DIR/bin/site -> /usr/local/bin/site"
    echo ""
    log_info "现在可以使用 'site' 命令管理站点"
    log_info "运行 'site --help' 查看帮助"
    echo ""
}

#---------------------------------------
# 显示帮助
#---------------------------------------
show_help() {
    echo "Site Manager 安装脚本 v$VERSION"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --setup     快速设置，仅配置 CLI 工具（需从源码目录运行）"
    echo "  --help      显示此帮助信息"
    echo ""
    echo "完整安装:"
    echo "  $0          交互式完整安装（Nginx/PHP/MySQL 等）"
    echo ""
    echo "示例:"
    echo "  git clone https://github.com/$GITHUB_REPO.git /opt/site_manager"
    echo "  cd /opt/site_manager && bash install.sh --setup"
    echo ""
}

#---------------------------------------
# 主流程
#---------------------------------------
main() {
    # 解析命令行参数
    case "${1:-}" in
        --setup)
            setup_cli_only
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac

    print_banner

    # 本地模式提示
    if $LOCAL_MODE; then
        echo ""
        log_info "检测到本地源码目录: $SCRIPT_DIR"
        log_info "提示: 使用 '$0 --setup' 可快速配置 CLI 工具（跳过软件安装）"
        echo ""
    fi

    check_system
    choose_directory
    choose_software

    echo ""
    echo -e "${WHITE}[4/6] 开始安装...${NC}"
    echo ""

    create_directories
    install_dependencies
    setup_firewall
    install_nginx
    install_php
    install_database
    install_redis
    install_supervisor
    install_docker
    install_python
    install_panel

    finish_install
}

# 运行
main "$@"
