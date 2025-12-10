#!/bin/bash
# 代理管理

proxy_manage() {
    local domain="$1"
    local action="$2"
    local value="$3"
    
    check_root
    
    if [ -z "$domain" ] || [ -z "$action" ]; then
        log_error "用法: site proxy <domain> <action> [value]"
        log_info "操作: target <url>, upstream add|remove <server>"
        return 1
    fi
    
    case "$action" in
        target)
            proxy_set_target "$domain" "$value"
            ;;
        upstream)
            proxy_upstream "$domain" "$value" "$4"
            ;;
        *)
            log_error "未知操作: $action"
            ;;
    esac
}

proxy_set_target() {
    local domain="$1"
    local target="$2"
    
    if [ -z "$target" ]; then
        log_error "请指定代理目标 URL"
        return 1
    fi
    
    local conf="$NGINX_CONF_DIR/$domain.conf"
    if [ ! -f "$conf" ]; then
        log_error "站点配置不存在: $conf"
        return 1
    fi
    
    log_info "设置代理目标: $domain -> $target"
    
    sed -i "s|proxy_pass .*|proxy_pass $target;|g" "$conf"
    
    nginx_reload
    
    log_success "代理目标已更新"
}

proxy_upstream() {
    local domain="$1"
    local action="$2"
    local server="$3"
    
    if [ -z "$action" ] || [ -z "$server" ]; then
        log_error "用法: site proxy <domain> upstream add|remove <server>"
        return 1
    fi
    
    local conf="$NGINX_CONF_DIR/$domain.conf"
    local upstream_name="upstream_${domain//./_}"
    
    case "$action" in
        add)
            log_info "添加上游服务器: $server"
            
            # 检查是否已有 upstream 块
            if ! grep -q "upstream $upstream_name" "$conf"; then
                # 创建 upstream 块
                sed -i "1i upstream $upstream_name {\n    server $server;\n}" "$conf"
                # 更新 proxy_pass
                sed -i "s|proxy_pass http://.*|proxy_pass http://$upstream_name;|g" "$conf"
            else
                # 添加到现有 upstream
                sed -i "/upstream $upstream_name {/a\    server $server;" "$conf"
            fi
            ;;
        remove)
            log_info "移除上游服务器: $server"
            sed -i "/server $server;/d" "$conf"
            ;;
    esac
    
    nginx_reload
    log_success "上游服务器已更新"
}
