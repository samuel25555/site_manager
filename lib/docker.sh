#!/bin/bash
# Docker 管理

docker_up() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        log_error "用法: site docker up <domain>"
        return 1
    fi
    
    local compose_dir="$DOCKER_DIR/$domain"
    
    if [ ! -f "$compose_dir/docker-compose.yml" ]; then
        log_error "Docker 配置不存在: $compose_dir/docker-compose.yml"
        return 1
    fi
    
    log_info "启动容器: $domain"
    
    cd "$compose_dir" && docker-compose up -d
    
    if [ $? -eq 0 ]; then
        log_success "容器已启动"
        docker-compose ps
    else
        log_error "容器启动失败"
        return 1
    fi
}

docker_down() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        log_error "用法: site docker down <domain>"
        return 1
    fi
    
    local compose_dir="$DOCKER_DIR/$domain"
    
    if [ ! -f "$compose_dir/docker-compose.yml" ]; then
        log_error "Docker 配置不存在"
        return 1
    fi
    
    log_info "停止容器: $domain"
    
    cd "$compose_dir" && docker-compose down
    
    log_success "容器已停止"
}

docker_logs() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        log_error "用法: site docker logs <domain>"
        return 1
    fi
    
    local compose_dir="$DOCKER_DIR/$domain"
    
    if [ ! -f "$compose_dir/docker-compose.yml" ]; then
        log_error "Docker 配置不存在"
        return 1
    fi
    
    cd "$compose_dir" && docker-compose logs -f --tail=100
}
