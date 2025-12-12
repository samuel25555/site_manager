#!/bin/bash
# 站点管理函数

# 创建站点
site_create() {
    local domain="$1"
    local type="$2"
    shift 2
    
    check_root
    
    if [ -z "$domain" ] || [ -z "$type" ]; then
        log_error "用法: site create <domain> <type>"
        log_info "类型: php|php:7.3|php:8.1|php:8.3|static|node|node:static|python|docker|proxy"
        return 1
    fi
    
    if site_exists "$domain"; then
        log_error "站点 $domain 已存在"
        return 1
    fi
    
    log_info "创建站点: $domain (类型: $type)"
    
    # 解析选项
    local php_version="$DEFAULT_PHP_VERSION"
    local port=""
    local target=""
    local websocket=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --php=*) php_version="${1#*=}" ;;
            --port=*) port="${1#*=}" ;;
            --target=*) target="${1#*=}" ;;
            --ws) websocket=true ;;
        esac
        shift
    done
    
    # 创建目录
    mkdir -p "$SITES_DIR/$domain"
    mkdir -p "$LOGS_DIR/nginx"
    mkdir -p "$SSL_DIR/$domain"
    
    # 根据类型创建配置
    case "$type" in
        php|php:*)
            if [[ "$type" == php:* ]]; then
                php_version="${type#php:}"
            fi
            _create_php_site "$domain" "$php_version"
            ;;
        static)
            _create_static_site "$domain"
            ;;
        node)
            port="${port:-$(find_available_port 3000)}"
            _create_node_site "$domain" "$port"
            ;;
        node:static)
            _create_static_site "$domain"
            ;;
        python)
            port="${port:-$(find_available_port 8000)}"
            _create_python_site "$domain" "$port"
            ;;
        docker)
            _create_docker_site "$domain"
            ;;
        proxy)
            if [ -z "$target" ]; then
                log_error "代理站点需要 --target=<url> 参数"
                return 1
            fi
            _create_proxy_site "$domain" "$target" "$websocket"
            ;;
        *)
            log_error "未知站点类型: $type"
            return 1
            ;;
    esac
    
    # 设置权限
    set_permissions "$SITES_DIR/$domain"
    
    # 重载 nginx
    nginx_reload
    
    log_success "站点 $domain 创建成功"
    site_info "$domain"
}

# PHP 站点
_create_php_site() {
    local domain="$1"
    local php_version="$2"
    local socket="/run/php/php$php_version-fpm.sock"
    
    # 检查 PHP-FPM
    if [ ! -S "$socket" ]; then
        log_warn "PHP $php_version FPM socket 不存在: $socket"
    fi
    
    # 创建默认文件
    echo "<?php phpinfo();" > "$SITES_DIR/$domain/index.php"
    
    # 创建 nginx 配置
    cat > "$NGINX_CONF_DIR/$domain.conf" << EOF
server {
    listen 80;
    server_name $domain;
    root $SITES_DIR/$domain;
    index index.php index.html;

    access_log $LOGS_DIR/nginx/$domain.access.log;
    error_log $LOGS_DIR/nginx/$domain.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:$socket;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. {
        deny all;
    }
}
EOF
}

# 静态站点
_create_static_site() {
    local domain="$1"
    
    echo "<h1>Welcome to $domain</h1>" > "$SITES_DIR/$domain/index.html"
    
    cat > "$NGINX_CONF_DIR/$domain.conf" << EOF
server {
    listen 80;
    server_name $domain;
    root $SITES_DIR/$domain;
    index index.html;

    access_log $LOGS_DIR/nginx/$domain.access.log;
    error_log $LOGS_DIR/nginx/$domain.error.log;

    location / {
        try_files \$uri \$uri/ \$uri.html /index.html;
    }

    location ~ /\. {
        deny all;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
}

# Node.js 站点
_create_node_site() {
    local domain="$1"
    local port="$2"
    
    cat > "$NGINX_CONF_DIR/$domain.conf" << EOF
server {
    listen 80;
    server_name $domain;

    access_log $LOGS_DIR/nginx/$domain.access.log;
    error_log $LOGS_DIR/nginx/$domain.error.log;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    mkdir -p "$LOGS_DIR/supervisor"
    
    cat > "$SUPERVISOR_CONF_DIR/$domain.conf" << EOF
[program:$domain]
directory=$SITES_DIR/$domain
command=node server.js
user=$WEB_USER
autostart=true
autorestart=true
stderr_logfile=$LOGS_DIR/supervisor/$domain.err.log
stdout_logfile=$LOGS_DIR/supervisor/$domain.out.log
environment=NODE_ENV="production",PORT="$port"
EOF

    log_info "Node.js 站点使用端口: $port"
}

# Python 站点
_create_python_site() {
    local domain="$1"
    local port="$2"
    
    mkdir -p "$RUNTIME_DIR/python/$domain"
    
    cat > "$NGINX_CONF_DIR/$domain.conf" << EOF
server {
    listen 80;
    server_name $domain;

    access_log $LOGS_DIR/nginx/$domain.access.log;
    error_log $LOGS_DIR/nginx/$domain.error.log;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /static {
        alias $SITES_DIR/$domain/static;
        expires 1y;
    }
}
EOF

    mkdir -p "$LOGS_DIR/supervisor"
    
    cat > "$SUPERVISOR_CONF_DIR/$domain.conf" << EOF
[program:$domain]
directory=$SITES_DIR/$domain
command=$RUNTIME_DIR/python/$domain/.venv/bin/uvicorn main:app --host 127.0.0.1 --port $port
user=$WEB_USER
autostart=true
autorestart=true
stderr_logfile=$LOGS_DIR/supervisor/$domain.err.log
stdout_logfile=$LOGS_DIR/supervisor/$domain.out.log
environment=PYTHONPATH="$SITES_DIR/$domain"
EOF

    log_info "Python 站点使用端口: $port"
    log_info "虚拟环境: $RUNTIME_DIR/python/$domain"
}

# Docker 站点
_create_docker_site() {
    local domain="$1"
    
    mkdir -p "$DOCKER_DIR/$domain"
    
    cat > "$DOCKER_DIR/$domain/docker-compose.yml" << EOF
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - $SITES_DIR/$domain:/app
    restart: unless-stopped
EOF

    cat > "$NGINX_CONF_DIR/$domain.conf" << EOF
server {
    listen 80;
    server_name $domain;

    access_log $LOGS_DIR/nginx/$domain.access.log;
    error_log $LOGS_DIR/nginx/$domain.error.log;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    log_info "Docker 配置: $DOCKER_DIR/$domain/docker-compose.yml"
}

# 代理站点
_create_proxy_site() {
    local domain="$1"
    local target="$2"
    local websocket="$3"
    
    local ws_config=""
    if [ "$websocket" = "true" ]; then
        ws_config="
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';"
    fi
    
    cat > "$NGINX_CONF_DIR/$domain.conf" << EOF
server {
    listen 80;
    server_name $domain;

    access_log $LOGS_DIR/nginx/$domain.access.log;
    error_log $LOGS_DIR/nginx/$domain.error.log;

    location / {
        proxy_pass $target;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;$ws_config
    }
}
EOF
}

# 删除站点
site_delete() {
    local domain="$1"
    
    check_root
    
    if [ -z "$domain" ]; then
        log_error "用法: site delete <domain>"
        return 1
    fi
    
    if ! site_exists "$domain"; then
        log_error "站点 $domain 不存在"
        return 1
    fi
    
    if ! confirm "确定要删除站点 $domain 吗? 此操作不可恢复!"; then
        log_info "操作已取消"
        return 0
    fi
    
    log_info "删除站点: $domain"
    
    rm -f "$NGINX_CONF_DIR/$domain.conf"
    rm -f "$NGINX_CONF_DIR/$domain.conf.disabled"
    
    if [ -f "$SUPERVISOR_CONF_DIR/$domain.conf" ]; then
        supervisorctl stop "$domain" 2>/dev/null || true
        rm -f "$SUPERVISOR_CONF_DIR/$domain.conf"
        supervisor_reload
    fi
    
    if [ -d "$DOCKER_DIR/$domain" ]; then
        cd "$DOCKER_DIR/$domain" && docker-compose down 2>/dev/null || true
        rm -rf "$DOCKER_DIR/$domain"
    fi
    
    rm -rf "$SITES_DIR/$domain"
    rm -rf "$RUNTIME_DIR/python/$domain"
    
    nginx_reload
    
    log_success "站点 $domain 已删除"
}

# 启用站点
site_enable() {
    local domain="$1"
    
    check_root
    
    if [ -z "$domain" ]; then
        log_error "用法: site enable <domain>"
        return 1
    fi
    
    if [ ! -f "$NGINX_CONF_DIR/$domain.conf.disabled" ]; then
        if [ -f "$NGINX_CONF_DIR/$domain.conf" ]; then
            log_info "站点 $domain 已经是启用状态"
            return 0
        fi
        log_error "站点 $domain 不存在"
        return 1
    fi
    
    mv "$NGINX_CONF_DIR/$domain.conf.disabled" "$NGINX_CONF_DIR/$domain.conf"
    
    if [ -f "$SUPERVISOR_CONF_DIR/$domain.conf" ]; then
        supervisorctl start "$domain" 2>/dev/null || true
    fi
    
    nginx_reload
    
    log_success "站点 $domain 已启用"
}

# 禁用站点
site_disable() {
    local domain="$1"
    
    check_root
    
    if [ -z "$domain" ]; then
        log_error "用法: site disable <domain>"
        return 1
    fi
    
    if [ ! -f "$NGINX_CONF_DIR/$domain.conf" ]; then
        if [ -f "$NGINX_CONF_DIR/$domain.conf.disabled" ]; then
            log_info "站点 $domain 已经是禁用状态"
            return 0
        fi
        log_error "站点 $domain 不存在"
        return 1
    fi
    
    mv "$NGINX_CONF_DIR/$domain.conf" "$NGINX_CONF_DIR/$domain.conf.disabled"
    
    if [ -f "$SUPERVISOR_CONF_DIR/$domain.conf" ]; then
        supervisorctl stop "$domain" 2>/dev/null || true
    fi
    
    nginx_reload
    
    log_success "站点 $domain 已禁用"
}

# 列出站点
site_list() {
    echo ""
    printf "%-30s %-10s %-10s %s\n" "站点" "类型" "状态" "路径"
    printf "%-30s %-10s %-10s %s\n" "----" "----" "----" "----"
    
    for conf in "$NGINX_CONF_DIR"/*; do
        [ -f "$conf" ] || continue
        
        local filename="$(basename "$conf")"
        # 跳过 default 和备份文件
        [[ "$filename" == "default" ]] && continue
        [[ "$filename" == *.bak ]] && continue
        
        local domain="${filename%.conf}"
        domain="${domain%.disabled}"
        local type="$(get_site_type "$domain")"
        local status="enabled"
        
        if [[ "$filename" == *.disabled ]]; then
            status="disabled"
        fi
        
        # 检查是否在 sites-enabled 中
        if [ \! -L "$NGINX_ENABLED_DIR/$domain" ] && [ \! -L "$NGINX_ENABLED_DIR/${domain}.conf" ]; then
            status="disabled"
        fi
        
        printf "%-30s %-10s %-10s %s\n" "$domain" "$type" "$status" "$SITES_DIR/$domain"
    done
    echo ""
}

# 站点详情
site_info() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        log_error "用法: site info <domain>"
        return 1
    fi
    
    if ! site_exists "$domain"; then
        log_error "站点 $domain 不存在"
        return 1
    fi
    
    local type="$(get_site_type "$domain")"
    local status="disabled"
    [ -f "$NGINX_CONF_DIR/$domain.conf" ] && status="enabled"
    
    echo ""
    echo -e "${GREEN}站点信息: $domain${NC}"
    echo "-----------------------------------"
    echo "类型: $type"
    echo "状态: $status"
    echo "目录: $SITES_DIR/$domain"
    echo "配置: $NGINX_CONF_DIR/$domain.conf"
    
    if [ -d "$SITES_DIR/$domain" ]; then
        local size="$(du -sh "$SITES_DIR/$domain" 2>/dev/null | cut -f1)"
        echo "大小: $size"
    fi
    
    if [ -f "$SSL_DIR/$domain/fullchain.pem" ]; then
        local expiry="$(openssl x509 -enddate -noout -in "$SSL_DIR/$domain/fullchain.pem" 2>/dev/null | cut -d= -f2)"
        echo "SSL: 已启用 (到期: $expiry)"
    else
        echo "SSL: 未启用"
    fi
    
    echo ""
}

# 站点状态
site_status() {
    local domain="$1"
    
    if [ -n "$domain" ]; then
        site_info "$domain"
        
        if [ -f "$SUPERVISOR_CONF_DIR/$domain.conf" ]; then
            echo "进程状态:"
            supervisorctl status "$domain" 2>/dev/null || echo "  未运行"
        fi
        
        if [ -d "$DOCKER_DIR/$domain" ]; then
            echo "Docker 状态:"
            cd "$DOCKER_DIR/$domain" && docker-compose ps 2>/dev/null || echo "  未运行"
        fi
    else
        echo ""
        echo -e "${GREEN}服务状态${NC}"
        echo "-----------------------------------"
        echo -n "Nginx: "
        systemctl is-active nginx
        echo -n "PHP-FPM: "
        systemctl is-active "php*-fpm" 2>/dev/null || echo "未安装"
        echo -n "Supervisor: "
        systemctl is-active supervisor
        echo ""
        
        site_list
    fi
}
