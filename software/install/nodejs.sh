#!/bin/bash
source /opt/site_manager/software/install/lib.sh
check_root

ACTION="$1"
VERSION="${2:-20}"

install_nodejs() {
    log_step "安装 Node.js $VERSION..."

    case "$PM" in
        apt) curl -fsSL https://deb.nodesource.com/setup_${VERSION}.x | bash - && apt-get install -y nodejs || install_failed "Node.js";;
        yum|dnf) curl -fsSL https://rpm.nodesource.com/setup_${VERSION}.x | bash - && $PM_INSTALL nodejs || install_failed "Node.js";;
    esac

    npm install -g yarn pm2 pnpm 2>/dev/null

    # 配置 PM2 开机自启
    source /opt/site_manager/config/site_manager.conf
    local web_user="${WEB_USER:-www}"
    if id "$web_user" &>/dev/null; then
        # 确定 PM2 home 目录
        local pm2_home
        pm2_home=$(getent passwd "$web_user" | cut -d: -f6)
        [ -z "$pm2_home" ] || [ ! -d "$pm2_home" ] && pm2_home="/www"

        log_step "配置 PM2 开机自启..."
        pm2 startup systemd -u "$web_user" --hp "$pm2_home" 2>/dev/null || true
        sudo -u "$web_user" HOME="$pm2_home" pm2 save 2>/dev/null || true
    fi

    install_success "Node.js" "$(node --version 2>/dev/null)"
    echo "  npm: $(npm --version 2>/dev/null)"
    echo "  pm2: $(pm2 --version 2>/dev/null)"
}

uninstall_nodejs() {
    read -p "确定卸载 Node.js? (y/n): " c; [ "$c" != "y" ] && return

    # 停止并移除 PM2
    pm2 kill 2>/dev/null
    pm2 unstartup systemd 2>/dev/null || true
    rm -f /etc/systemd/system/pm2-*.service
    systemctl daemon-reload 2>/dev/null || true

    apt-get remove --purge -y nodejs 2>/dev/null
    rm -rf /usr/local/lib/node_modules ~/.npm
    log_info "Node.js 已卸载"
}

case "$ACTION" in
    install) install_nodejs;; uninstall) uninstall_nodejs;;
    update) apt-get update && apt-get upgrade -y nodejs; npm update -g;;
    *) echo "用法: $0 install|uninstall|update [version]";;
esac
