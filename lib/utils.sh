#!/bin/bash
# 工具函数

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检查是否 root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行"
        exit 1
    fi
}

# 确认操作
confirm() {
    local msg="${1:-确定要继续吗?}"
    read -p "$msg (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# 生成随机字符串
random_string() {
    local length="${1:-16}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# 检查端口是否被占用
port_in_use() {
    local port="$1"
    netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "
}

# 查找可用端口
find_available_port() {
    local start="${1:-3000}"
    local port=$start
    while port_in_use $port; do
        ((port++))
    done
    echo $port
}

# 获取站点类型
get_site_type() {
    local domain="$1"
    local conf="$NGINX_CONF_DIR/$domain.conf"
    
    if [ ! -f "$conf" ]; then
        echo "unknown"
        return
    fi
    
    if grep -q "fastcgi_pass" "$conf"; then
        echo "php"
    elif grep -q "proxy_pass" "$conf"; then
        if [ -f "$SUPERVISOR_CONF_DIR/$domain.conf" ]; then
            if grep -q "python\|uvicorn\|gunicorn" "$SUPERVISOR_CONF_DIR/$domain.conf"; then
                echo "python"
            else
                echo "node"
            fi
        else
            echo "proxy"
        fi
    elif [ -f "$DOCKER_DIR/$domain/docker-compose.yml" ]; then
        echo "docker"
    else
        echo "static"
    fi
}

# 检查站点是否存在
site_exists() {
    local domain="$1"
    [ -d "$SITES_DIR/$domain" ] || [ -f "$NGINX_CONF_DIR/$domain.conf" ]
}

# 设置目录权限
set_permissions() {
    local path="$1"
    local user="${2:-$WEB_USER}"
    local group="${3:-$WEB_GROUP}"
    local dir_perm="${4:-755}"
    local file_perm="${5:-644}"
    
    chown -R "$user:$group" "$path"
    find "$path" -type d -exec chmod "$dir_perm" {} \;
    find "$path" -type f -exec chmod "$file_perm" {} \;
}

# Nginx 测试并重载
nginx_reload() {
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        return 0
    else
        log_error "Nginx 配置测试失败"
        nginx -t
        return 1
    fi
}

# Supervisor 重载
supervisor_reload() {
    supervisorctl reread
    supervisorctl update
}

# Nginx 管理
nginx_manage() {
    local action="$1"
    
    check_root
    
    case "$action" in
        test)
            nginx -t
            ;;
        reload)
            nginx_reload
            ;;
        restart)
            systemctl restart nginx
            log_success "Nginx 已重启"
            ;;
        *)
            echo "用法: site nginx <test|reload|restart>"
            ;;
    esac
}

# Supervisor 管理
supervisor_manage() {
    local action="$1"
    
    check_root
    
    case "$action" in
        reload)
            supervisor_reload
            log_success "Supervisor 已重载"
            ;;
        restart)
            systemctl restart supervisor
            log_success "Supervisor 已重启"
            ;;
        *)
            echo "用法: site supervisor <reload|restart>"
            ;;
    esac
}

# 重启所有服务
services_restart() {
    check_root
    
    log_info "重启所有服务"
    
    systemctl restart nginx
    systemctl restart php*-fpm 2>/dev/null || true
    systemctl restart supervisor
    
    log_success "所有服务已重启"
}
