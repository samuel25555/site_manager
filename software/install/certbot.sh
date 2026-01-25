#!/bin/bash
#
# Certbot 安装脚本
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root
log_step "安装 Certbot..."

# 安装 Certbot
$PM_UPDATE
$PM_INSTALL python3 python3-venv libaugeas0

# 安装 Certbot 和 Cloudflare 插件
python3 -m venv /opt/certbot
/opt/certbot/bin/pip install --upgrade pip
/opt/certbot/bin/pip install certbot certbot-dns-cloudflare

# 创建符号链接
ln -sf /opt/certbot/bin/certbot /usr/bin/certbot

# 验证安装
if ! certbot --version &>/dev/null; then
    install_failed "Certbot"
fi

VERSION=$(certbot --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
install_success "Certbot" "$VERSION"
