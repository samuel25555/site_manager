#!/bin/bash
# Supervisor 安装脚本

source "$(dirname "$0")/lib.sh"

install_supervisor() {
    log_info "安装 Supervisor..."
    
    apt-get update -qq
    apt-get install -y -qq supervisor
    
    # 启动并启用服务
    systemctl enable supervisor
    systemctl start supervisor
    
    # 创建配置目录
    mkdir -p /etc/supervisor/conf.d
    
    log_success "Supervisor 安装完成"
}

uninstall_supervisor() {
    log_info "卸载 Supervisor..."
    
    systemctl stop supervisor 2>/dev/null
    apt-get remove -y supervisor
    apt-get autoremove -y
    
    log_success "Supervisor 卸载完成"
}

case "$1" in
    install) install_supervisor ;;
    uninstall) uninstall_supervisor ;;
    *) echo "用法: $0 {install|uninstall}" ;;
esac
