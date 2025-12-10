#!/bin/bash
# SSL 证书管理

ssl_request() {
    local domain="$1"
    shift
    
    check_root
    
    if [ -z "$domain" ]; then
        log_error "用法: site ssl <domain> [--dns]"
        return 1
    fi
    
    if ! site_exists "$domain"; then
        log_error "站点 $domain 不存在"
        return 1
    fi
    
    # 检查 certbot
    if ! command_exists certbot; then
        log_error "certbot 未安装"
        log_info "安装: apt install certbot python3-certbot-nginx"
        return 1
    fi
    
    local use_dns=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dns) use_dns=true ;;
        esac
        shift
    done
    
    log_info "申请 SSL 证书: $domain"
    
    if [ "$use_dns" = "true" ]; then
        certbot certonly --manual --preferred-challenges dns -d "$domain" -d "*.$domain"
    else
        certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL"
    fi
    
    if [ $? -eq 0 ]; then
        # 复制证书到站点目录
        if [ -d "/etc/letsencrypt/live/$domain" ]; then
            cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$SSL_DIR/$domain/"
            cp "/etc/letsencrypt/live/$domain/privkey.pem" "$SSL_DIR/$domain/"
        fi
        
        log_success "SSL 证书申请成功"
        nginx_reload
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
