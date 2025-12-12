#!/bin/bash
source /opt/site_manager/software/install/lib.sh
check_root

ACTION="$1"

install_redis() {
    log_step "安装 Redis..."
    
    local redis_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)

    case "$PM" in
        apt) apt-get update && apt-get install -y redis-server || install_failed "Redis";;
        yum|dnf) $PM_INSTALL redis || install_failed "Redis";;
    esac

    # 配置
    local conf="/etc/redis/redis.conf"
    [ ! -f "$conf" ] && conf="/etc/redis.conf"
    [ -f "$conf" ] && {
        sed -i 's/^bind .*/bind 127.0.0.1/' "$conf"
        sed -i "s/^# requirepass.*/requirepass $redis_pass/" "$conf"
        sed -i 's/^appendonly no/appendonly yes/' "$conf"
    }

    service_enable redis-server 2>/dev/null || service_enable redis 2>/dev/null
    service_start redis-server 2>/dev/null || service_start redis 2>/dev/null

    echo "$redis_pass" > /root/.redis_password
    chmod 600 /root/.redis_password

    install_success "Redis" "$(get_installed_version redis)"
    echo -e " 密码: ${YELLOW}$redis_pass${NC}"
    echo " 密码已保存到 /root/.redis_password"
}

uninstall_redis() {
    read -p "确定卸载 Redis? (y/n): " c; [ "$c" != "y" ] && return
    service_stop redis-server 2>/dev/null || service_stop redis 2>/dev/null
    apt-get remove --purge -y redis-server 2>/dev/null
    log_info "Redis 已卸载"
}

case "$ACTION" in
    install) install_redis;; uninstall) uninstall_redis;;
    update) apt-get update && apt-get upgrade -y redis-server; service_restart redis-server 2>/dev/null;;
    *) echo "用法: $0 install|uninstall|update";;
esac
