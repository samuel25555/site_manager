#!/bin/bash
# SSL 证书管理

# Cloudflare 凭据文件
CF_CREDENTIALS="${ROOT_DIR:-/opt/site_manager}/config/cloudflare.ini"
SSL_DIR="${SSL_DIR:-/www/ssl}"

# 安装 certbot 和插件
ssl_install() {
    check_root

    if command_exists certbot; then
        log_info "certbot 已安装"
        return 0
    fi

    log_info "安装 certbot..."
    apt-get update -qq
    apt-get install -y -qq certbot python3-certbot-nginx python3-certbot-dns-cloudflare > /dev/null 2>&1

    if command_exists certbot; then
        log_success "certbot 安装成功"
    else
        log_error "certbot 安装失败"
        return 1
    fi
}

# 配置 Cloudflare DNS API
ssl_dns_config() {
    check_root

    local email="$1"
    local api_key="$2"

    if [ -z "$email" ] || [ -z "$api_key" ]; then
        echo "配置 Cloudflare DNS API"
        read -p "Email: " email
        read -p "API Key: " api_key
    fi

    if [ -z "$email" ] || [ -z "$api_key" ]; then
        log_error "Email 和 API Key 不能为空"
        return 1
    fi

    mkdir -p "$(dirname "$CF_CREDENTIALS")"
    cat > "$CF_CREDENTIALS" << EOF
dns_cloudflare_email = $email
dns_cloudflare_api_key = $api_key
EOF
    chmod 600 "$CF_CREDENTIALS"

    log_success "Cloudflare DNS 配置已保存"
}

# 申请 SSL 证书
ssl_request() {
    local domain="$1"
    shift

    check_root

    if [ -z "$domain" ]; then
        log_error "用法: site ssl <domain> [--dns] [--wildcard]"
        return 1
    fi

    # 检查 certbot
    if ! command_exists certbot; then
        log_warn "certbot 未安装，正在安装..."
        ssl_install || return 1
    fi

    local use_dns=false
    local wildcard=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dns) use_dns=true ;;
            --wildcard) wildcard=true; use_dns=true ;;
        esac
        shift
    done

    log_info "申请 SSL 证书: $domain"

    # 创建证书目录
    mkdir -p "$SSL_DIR/$domain"

    if [ "$use_dns" = "true" ]; then
        # DNS 验证 (支持泛域名)
        if [ ! -f "$CF_CREDENTIALS" ]; then
            log_error "Cloudflare 凭据未配置"
            log_info "请先运行: site ssl config"
            return 1
        fi

        # 从凭据文件读取邮箱
        local cf_email=$(grep "dns_cloudflare_email" "$CF_CREDENTIALS" | cut -d'=' -f2 | tr -d ' ')
        local email="${ADMIN_EMAIL:-$cf_email}"

        local domains="-d $domain"
        [ "$wildcard" = "true" ] && domains="$domains -d *.$domain"

        certbot certonly \
            --dns-cloudflare \
            --dns-cloudflare-credentials "$CF_CREDENTIALS" \
            --dns-cloudflare-propagation-seconds 30 \
            $domains \
            --non-interactive --agree-tos --email "$email"
    else
        # HTTP 验证
        if ! site_exists "$domain"; then
            log_error "站点 $domain 不存在，HTTP 验证需要先创建站点"
            log_info "或使用 --dns 参数进行 DNS 验证"
            return 1
        fi
        certbot --nginx -d "$domain" --non-interactive --agree-tos --email "${ADMIN_EMAIL:-admin@$domain}"
    fi

    if [ $? -eq 0 ]; then
        # 复制证书到站点目录
        local cert_domain="$domain"
        [ "$wildcard" = "true" ] && cert_domain="$domain"

        if [ -d "/etc/letsencrypt/live/$cert_domain" ]; then
            cp "/etc/letsencrypt/live/$cert_domain/fullchain.pem" "$SSL_DIR/$domain/"
            cp "/etc/letsencrypt/live/$cert_domain/privkey.pem" "$SSL_DIR/$domain/"
            chmod 644 "$SSL_DIR/$domain/fullchain.pem"
            chmod 600 "$SSL_DIR/$domain/privkey.pem"
        fi

        log_success "SSL 证书申请成功"
        log_info "证书路径: $SSL_DIR/$domain/"
        nginx_reload 2>/dev/null
    else
        log_error "SSL 证书申请失败"
        return 1
    fi
}

ssl_renew() {
    check_root
    
    log_info "续期所有 SSL 证书"
    
    certbot renew --quiet
    
    if [ $? -eq 0 ]; then
        log_success "证书续期完成"
        nginx_reload
    else
        log_warn "部分证书续期可能失败，请检查日志"
    fi
}
