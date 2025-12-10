#!/bin/bash
# Web 面板管理

panel_manage() {
    local action="$1"
    shift
    
    case "$action" in
        start)
            panel_start "$@"
            ;;
        stop)
            panel_stop
            ;;
        status)
            panel_status
            ;;
        password)
            panel_password
            ;;
        port)
            panel_port "$1"
            ;;
        *)
            echo "用法: site panel <start|stop|status|password|port>"
            ;;
    esac
}

panel_start() {
    check_root
    
    local port="$PANEL_PORT"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port=*) port="${1#*=}" ;;
        esac
        shift
    done
    
    if pgrep -f "site_manager_panel" > /dev/null; then
        log_info "面板已在运行"
        panel_status
        return 0
    fi
    
    log_info "启动 Web 面板 (端口: $port)"
    
    # 检查面板程序是否存在
    if [ ! -f "$PANEL_DIR/site_manager_panel" ]; then
        log_error "面板程序不存在: $PANEL_DIR/site_manager_panel"
        log_info "请先构建面板: cd $PANEL_DIR && go build -o site_manager_panel"
        return 1
    fi
    
    # 启动面板
    cd "$PANEL_DIR" && nohup ./site_manager_panel --port=$port > "$LOGS_DIR/panel/panel.log" 2>&1 &
    
    sleep 2
    
    if pgrep -f "site_manager_panel" > /dev/null; then
        log_success "面板已启动"
        echo ""
        echo "访问地址: http://$(hostname -I | awk '{print $1}'):$port"
        echo ""
    else
        log_error "面板启动失败，请查看日志: $LOGS_DIR/panel/panel.log"
        return 1
    fi
}

panel_stop() {
    check_root
    
    if ! pgrep -f "site_manager_panel" > /dev/null; then
        log_info "面板未运行"
        return 0
    fi
    
    log_info "停止 Web 面板"
    
    pkill -f "site_manager_panel"
    
    log_success "面板已停止"
}

panel_status() {
    echo ""
    echo "面板状态:"
    echo "-----------------------------------"
    
    if pgrep -f "site_manager_panel" > /dev/null; then
        echo -e "状态: ${GREEN}运行中${NC}"
        local pid="$(pgrep -f 'site_manager_panel')"
        echo "PID: $pid"
        
        # 获取端口
        local port="$(ss -tlnp 2>/dev/null | grep "$pid" | awk '{print $4}' | grep -oP ':\K[0-9]+' | head -1)"
        if [ -n "$port" ]; then
            echo "端口: $port"
            echo "地址: http://$(hostname -I | awk '{print $1}'):$port"
        fi
    else
        echo -e "状态: ${RED}未运行${NC}"
    fi
    
    echo ""
}

panel_password() {
    check_root
    
    local new_password="$(random_string 12)"
    
    log_info "重置面板密码"
    
    # 更新配置文件
    if [ -f "$PANEL_DIR/config.yaml" ]; then
        sed -i "s/password:.*/password: $new_password/" "$PANEL_DIR/config.yaml"
    fi
    
    echo ""
    echo "新密码: $new_password"
    echo ""
    
    log_info "请重启面板使密码生效: site panel stop && site panel start"
}

panel_port() {
    local new_port="$1"
    
    check_root
    
    if [ -z "$new_port" ]; then
        log_error "用法: site panel port <port>"
        return 1
    fi
    
    log_info "更新面板端口为: $new_port"
    
    # 更新配置
    sed -i "s/^PANEL_PORT=.*/PANEL_PORT=$new_port/" "$CONFIG_DIR/site_manager.conf"
    
    if [ -f "$PANEL_DIR/config.yaml" ]; then
        sed -i "s/port:.*/port: $new_port/" "$PANEL_DIR/config.yaml"
    fi
    
    log_success "端口已更新"
    log_info "请重启面板使配置生效: site panel stop && site panel start"
}
