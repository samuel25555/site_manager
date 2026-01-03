#!/bin/bash
source /opt/site_manager/software/install/lib.sh
source /opt/site_manager/lib/tune.sh
check_root

ACTION="$1"
VERSION="${2:-8.2}"
PHP_EXTS="cli fpm common mysql curl gd mbstring xml zip bcmath intl soap opcache redis"

install_php() {
    log_step "安装 PHP $VERSION..."

    case "$PM" in
        apt)
            apt-get install -y apt-transport-https lsb-release ca-certificates
            curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/keyrings/php.gpg 2>/dev/null
            echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/php.list
            apt-get update
            
            local pkgs=""
            for ext in $PHP_EXTS; do pkgs="$pkgs php${VERSION}-${ext}"; done
            apt-get install -y $pkgs || install_failed "PHP"
            ;;
        yum|dnf)
            $PM_INSTALL https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm 2>/dev/null
            $PM_INSTALL php php-fpm php-common php-mysqlnd php-curl php-gd php-mbstring php-xml php-zip php-bcmath || install_failed "PHP"
            ;;
    esac

    # 确保 www 用户存在
    id www &>/dev/null || useradd -r -s /sbin/nologin www

    # 生成优化配置
    log_step "生成优化配置..."
    local fpm_conf="/etc/php/$VERSION/fpm/pool.d/www.conf"
    [ -f "$fpm_conf" ] && {
        cp "$fpm_conf" "${fpm_conf}.bak"
        generate_php_fpm_conf "$VERSION" > "$fpm_conf"
    }

    # 生成 OPcache 配置
    local opcache_conf="/etc/php/$VERSION/fpm/conf.d/99-opcache-tuned.ini"
    generate_opcache_conf > "$opcache_conf"

    local fpm_service="php${VERSION}-fpm"
    service_enable "$fpm_service"
    service_start "$fpm_service"
    install_success "PHP" "$(get_installed_version php)"
}

uninstall_php() {
    log_step "卸载 PHP $VERSION..."
    read -p "确定卸载? (y/n): " c; [ "$c" != "y" ] && return
    systemctl stop "php${VERSION}-fpm" 2>/dev/null
    apt-get remove -y "php${VERSION}-*" 2>/dev/null
    log_info "PHP $VERSION 已卸载"
}

case "$ACTION" in
    install) install_php;; uninstall) uninstall_php;;
    update) apt-get update && apt-get upgrade -y "php${VERSION}-*"; systemctl restart "php${VERSION}-fpm";;
    *) echo "用法: $0 install|uninstall|update [version]";;
esac
