#!/bin/bash
#
# Certbot 安装脚本
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root
log_step "安装 Certbot..."

# 安装 Certbot
# 注意：使用系统包而不是 pip 安装，避免 5.x 版本的 DNS 验证 bug
# Debian/Ubuntu 系统包提供的是稳定的 2.x 版本
$PM_UPDATE
$PM_INSTALL python3-certbot python3-certbot-dns-cloudflare python3-certbot-nginx jq

# 验证安装
if ! certbot --version &>/dev/null; then
    install_failed "Certbot"
fi

VERSION=$(certbot --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
install_success "Certbot" "$VERSION"
