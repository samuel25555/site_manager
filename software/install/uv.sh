#!/bin/bash
# uv (Python 包管理器) 安装脚本

source "$(dirname "$0")/lib.sh"

install_uv() {
    log_info "安装 uv..."
    
    # 使用官方安装脚本
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # 添加到 PATH
    if [ -f /root/.local/bin/uv ]; then
        ln -sf /root/.local/bin/uv /usr/local/bin/uv
        ln -sf /root/.local/bin/uvx /usr/local/bin/uvx
    fi
    
    # 验证安装
    if command -v uv &>/dev/null; then
        log_success "uv 安装完成: $(uv --version)"
    else
        log_error "uv 安装失败"
        return 1
    fi
}

uninstall_uv() {
    log_info "卸载 uv..."
    
    rm -f /usr/local/bin/uv /usr/local/bin/uvx
    rm -rf /root/.local/bin/uv /root/.local/bin/uvx
    rm -rf ~/.cache/uv
    
    log_success "uv 卸载完成"
}

case "$1" in
    install) install_uv ;;
    uninstall) uninstall_uv ;;
    *) echo "用法: $0 {install|uninstall}" ;;
esac
