#!/bin/bash
#
# Site Manager 软件安装公共函数库
#

# 颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
NC="\033[0m"

# 路径
SOFTWARE_DIR="/opt/site_manager/software"
INSTALL_DIR="$SOFTWARE_DIR/install"
LOG_DIR="/www/wwwlogs/site_manager"
mkdir -p "$LOG_DIR"

# ========== 系统检测 ==========
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    fi
    ARCH=$(uname -m)
}

get_package_manager() {
    if command -v apt-get &>/dev/null; then
        PM="apt"
        PM_INSTALL="apt-get install -y"
        PM_UPDATE="apt-get update"
    elif command -v dnf &>/dev/null; then
        PM="dnf"
        PM_INSTALL="dnf install -y"
    elif command -v yum &>/dev/null; then
        PM="yum"
        PM_INSTALL="yum install -y"
    fi
}

# ========== 日志函数 ==========
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}>>> $1${NC}"; }

# ========== 检查函数 ==========
check_root() { [ "$EUID" -ne 0 ] && log_error "请使用 root 权限运行" && exit 1; }
check_installed() { [ -f "$1" ] || [ -x "$1" ]; }

# ========== 服务管理 ==========
service_start() { systemctl start "$1" && log_info "$1 已启动"; }
service_stop() { systemctl stop "$1" && log_info "$1 已停止"; }
service_restart() { systemctl restart "$1" && log_info "$1 已重启"; }
service_enable() { systemctl enable "$1" 2>/dev/null; }

# ========== 版本检测 ==========
get_installed_version() {
    case "$1" in
        nginx) nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+';;
        php) php -v 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+';;
        mysql) mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+';;
        redis) redis-server --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+';;
        nodejs|node) node --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+';;
        docker) docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+';;
        composer) composer --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+';;
        *) echo "未知";;
    esac
}

# ========== 防火墙 ==========
firewall_allow() {
    local port="$1"
    command -v ufw &>/dev/null && ufw allow "$port/tcp" &>/dev/null
}

# ========== 结果显示 ==========
install_success() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} $1 $2 安装成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

install_failed() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED} $1 安装失败!${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
}

# 初始化
get_os_info
get_package_manager
