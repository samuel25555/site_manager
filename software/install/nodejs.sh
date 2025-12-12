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
    install_success "Node.js" "$(node --version 2>/dev/null)"
    echo " npm: $(npm --version 2>/dev/null)"
}

uninstall_nodejs() {
    read -p "确定卸载 Node.js? (y/n): " c; [ "$c" != "y" ] && return
    pm2 kill 2>/dev/null
    apt-get remove --purge -y nodejs 2>/dev/null
    rm -rf /usr/local/lib/node_modules ~/.npm
    log_info "Node.js 已卸载"
}

case "$ACTION" in
    install) install_nodejs;; uninstall) uninstall_nodejs;;
    update) apt-get update && apt-get upgrade -y nodejs; npm update -g;;
    *) echo "用法: $0 install|uninstall|update [version]";;
esac
