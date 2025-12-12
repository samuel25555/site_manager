#!/bin/bash
source /opt/site_manager/software/install/lib.sh
check_root

ACTION="$1"
VERSION="${2:-1.26}"

install_nginx() {
    log_step "安装 Nginx..."
    
    if check_installed "/usr/sbin/nginx"; then
        log_warn "Nginx $(get_installed_version nginx) 已安装"
        read -p "重新安装? (y/n): " c; [ "$c" != "y" ] && return
    fi

    case "$PM" in
        apt)
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /etc/apt/keyrings/nginx.gpg 2>/dev/null
            echo "deb [signed-by=/etc/apt/keyrings/nginx.gpg] http://nginx.org/packages/debian $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
            apt-get update && apt-get install -y nginx || install_failed "Nginx"
            ;;
        yum|dnf)
            cat > /etc/yum.repos.d/nginx.repo << 'REPO'
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
REPO
            $PM_INSTALL nginx || install_failed "Nginx"
            ;;
    esac

    mkdir -p /etc/nginx/sites-{available,enabled} /www/wwwroot /var/log/nginx/sites
    grep -q "sites-enabled" /etc/nginx/nginx.conf || sed -i '/http {/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
    
    service_enable nginx
    service_start nginx
    firewall_allow 80; firewall_allow 443
    install_success "Nginx" "$(get_installed_version nginx)"
}

uninstall_nginx() {
    log_step "卸载 Nginx..."
    read -p "确定卸载? (y/n): " c; [ "$c" != "y" ] && return
    service_stop nginx
    case "$PM" in apt) apt-get remove -y nginx;; *) $PM remove -y nginx;; esac
    log_info "Nginx 已卸载"
}

case "$ACTION" in
    install) install_nginx;; uninstall) uninstall_nginx;;
    update) apt-get update && apt-get upgrade -y nginx 2>/dev/null; service_restart nginx;;
    *) echo "用法: $0 install|uninstall|update [version]";;
esac
