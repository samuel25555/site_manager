#!/bin/bash
# PHP 版本管理

php_list() {
    echo ""
    echo "已安装的 PHP 版本:"
    echo "-----------------------------------"
    
    for socket in /run/php/php*-fpm.sock; do
        [ -S "$socket" ] || continue
        # 只匹配带版本号的 socket (如 php8.3-fpm.sock)
        local version
        version=$(echo "$socket" | grep -oP "php\K[0-9]+\.[0-9]+")
        [ -z "$version" ] && continue
        
        echo "  PHP $version - active"
    done
    
    echo ""
    echo "默认版本: $DEFAULT_PHP_VERSION"
    echo ""
    return 0
}

php_set() {
    local domain="$1"
    local version="$2"
    
    check_root
    
    if [ -z "$domain" ] || [ -z "$version" ]; then
        log_error "用法: site php set <domain> <version>"
        log_info "示例: site php set example.com 8.1"
        return 1
    fi
    
    local nginx_conf="$NGINX_CONF_DIR/$domain.conf"
    if [ ! -f "$nginx_conf" ]; then
        log_error "站点 $domain 不存在"
        return 1
    fi
    
    local socket="/run/php/php${version}-fpm.sock"
    if [ ! -S "$socket" ]; then
        log_error "PHP $version 未安装或未运行"
        log_info "可用版本:"
        php_list
        return 1
    fi
    
    # 更新 nginx 配置
    sed -i "s|fastcgi_pass unix:/run/php/php.*-fpm.sock|fastcgi_pass unix:$socket|g" "$nginx_conf"
    
    log_success "站点 $domain PHP 版本已设置为 $version"
    log_info "执行 'site nginx reload' 使更改生效"
    return 0
}

php_manage() {
    local action="$1"
    shift
    
    case "$action" in
        list)
            php_list
            return $?
            ;;
        set)
            php_set "$@"
            return $?
            ;;
        *)
            log_error "未知操作: $action"
            echo "用法: site php <list|set>"
            return 1
            ;;
    esac
}
