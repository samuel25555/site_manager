#!/bin/bash
# 日志查看

logs_view() {
    local domain="$1"
    shift
    
    if [ -z "$domain" ]; then
        log_error "用法: site logs <domain> [-f] [-e]"
        return 1
    fi
    
    local follow=false
    local error=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow) follow=true ;;
            -e|--error) error=true ;;
        esac
        shift
    done
    
    local log_file
    if [ "$error" = "true" ]; then
        log_file="$LOGS_DIR/nginx/$domain.error.log"
    else
        log_file="$LOGS_DIR/nginx/$domain.access.log"
    fi
    
    if [ ! -f "$log_file" ]; then
        log_error "日志文件不存在: $log_file"
        return 1
    fi
    
    if [ "$follow" = "true" ]; then
        tail -f "$log_file"
    else
        tail -100 "$log_file"
    fi
}
