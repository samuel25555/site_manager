#!/bin/bash
#
# Composer 安装脚本
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root
log_step "安装 Composer..."

# 检查 PHP 是否已安装
if ! command -v php &>/dev/null; then
    log_error "请先安装 PHP"
    exit 1
fi

# 下载并安装 Composer
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    log_error "安装程序验证失败"
    rm composer-setup.php
    exit 1
fi

php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# 验证安装
if ! composer --version &>/dev/null; then
    install_failed "Composer"
fi

# 配置中国镜像
composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/

VERSION=$(composer --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
install_success "Composer" "$VERSION"
