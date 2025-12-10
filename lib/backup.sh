#!/bin/bash
# 备份管理

backup_create() {
    local domain="$1"
    
    check_root
    
    if [ -z "$domain" ]; then
        log_error "用法: site backup <domain>"
        return 1
    fi
    
    if ! site_exists "$domain"; then
        log_error "站点 $domain 不存在"
        return 1
    fi
    
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_file="$BACKUP_DIR/${domain}_${timestamp}.tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    
    log_info "备份站点: $domain"
    
    # 创建备份
    tar -czf "$backup_file"         -C "$SITES_DIR" "$domain"         -C "$NGINX_CONF_DIR" "$domain.conf" 2>/dev/null         -C "$NGINX_CONF_DIR" "$domain.conf.disabled" 2>/dev/null         || tar -czf "$backup_file" -C "$SITES_DIR" "$domain"
    
    if [ $? -eq 0 ]; then
        log_success "备份成功: $backup_file"
        ls -lh "$backup_file"
    else
        log_error "备份失败"
        return 1
    fi
}

backup_restore() {
    local domain="$1"
    local file="$2"
    
    check_root
    
    if [ -z "$domain" ] || [ -z "$file" ]; then
        log_error "用法: site restore <domain> <file>"
        return 1
    fi
    
    if [ ! -f "$file" ]; then
        log_error "备份文件不存在: $file"
        return 1
    fi
    
    if site_exists "$domain"; then
        if ! confirm "站点 $domain 已存在，确定要覆盖吗?"; then
            log_info "操作已取消"
            return 0
        fi
    fi
    
    log_info "恢复站点: $domain <- $file"
    
    # 恢复文件
    tar -xzf "$file" -C "$SITES_DIR"
    
    # 恢复配置 (如果存在)
    tar -tzf "$file" | grep -q ".conf" && tar -xzf "$file" -C "$NGINX_CONF_DIR" --wildcards "*.conf*" 2>/dev/null
    
    # 设置权限
    set_permissions "$SITES_DIR/$domain"
    
    nginx_reload
    
    log_success "站点恢复成功"
}

backup_list() {
    local domain="$1"
    
    echo ""
    echo "备份列表:"
    echo "-----------------------------------"
    
    if [ -n "$domain" ]; then
        ls -lht "$BACKUP_DIR/${domain}_"*.tar.gz 2>/dev/null || echo "没有找到 $domain 的备份"
    else
        ls -lht "$BACKUP_DIR/"*.tar.gz 2>/dev/null || echo "没有备份"
    fi
    
    echo ""
}
