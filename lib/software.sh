#!/bin/bash
#===============================================================================
# Site Manager - 软件安装模块
# 支持: nginx, php, mysql, mariadb, redis, memcached, mongodb
#===============================================================================

# 获取系统信息
get_os_info() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID:$VERSION_ID"
    fi
}

# 检查软件是否已安装
is_installed() {
    local software="$1"
    case "$software" in
        nginx)
            command -v nginx &>/dev/null && systemctl is-active --quiet nginx
            ;;
        php*)
            local version="${software#php}"
            [[ -z "$version" ]] && version="8.3"
            command -v "php${version}" &>/dev/null
            ;;
        mysql)
            command -v mysql &>/dev/null && systemctl is-active --quiet mysql
            ;;
        mariadb)
            command -v mysql &>/dev/null && systemctl is-active --quiet mariadb
            ;;
        redis)
            command -v redis-server &>/dev/null && systemctl is-active --quiet redis-server
            ;;
        memcached)
            command -v memcached &>/dev/null && systemctl is-active --quiet memcached
            ;;
        mongodb)
            command -v mongod &>/dev/null && systemctl is-active --quiet mongod
            ;;
        *)
            return 1
            ;;
    esac
}

# 获取软件版本
get_version() {
    local software="$1"
    case "$software" in
        nginx)
            nginx -v 2>&1 | grep -oP 'nginx/\K[\d.]+'
            ;;
        php*)
            local version="${software#php}"
            [[ -z "$version" ]] && version="8.3"
            php${version} -v 2>/dev/null | head -1 | grep -oP 'PHP \K[\d.]+'
            ;;
        mysql|mariadb)
            mysql --version 2>/dev/null | grep -oP '[\d.]+' | head -1
            ;;
        redis)
            redis-server --version 2>/dev/null | grep -oP 'v=\K[\d.]+'
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

#---------------------------------------
# 安装 Nginx
#---------------------------------------
software_install_nginx() {
    log_info "安装 Nginx..."

    apt-get update -qq
    apt-get install -y nginx > /dev/null 2>&1

    # 配置包含站点目录
    local include_line="include ${BASE_DIR}/vhost/nginx/*.conf;"
    if ! grep -q "$include_line" /etc/nginx/nginx.conf; then
        sed -i "/http {/a\\    $include_line" /etc/nginx/nginx.conf
    fi

    # 设置用户
    sed -i 's/^user .*/user www;/' /etc/nginx/nginx.conf

    systemctl enable nginx
    systemctl restart nginx

    log_success "Nginx 安装完成 (版本: $(get_version nginx))"
}

#---------------------------------------
# 安装 PHP
#---------------------------------------
software_install_php() {
    local version="$1"
    [[ -z "$version" ]] && version="8.3"

    # 验证版本
    if [[ ! "$version" =~ ^(7\.4|8\.0|8\.1|8\.2|8\.3)$ ]]; then
        log_error "不支持的 PHP 版本: $version (支持: 7.4, 8.0, 8.1, 8.2, 8.3)"
        return 1
    fi

    log_info "安装 PHP $version..."

    # 添加 Sury 源
    if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then
        log_info "添加 PHP 软件源..."
        apt-get install -y -qq apt-transport-https lsb-release ca-certificates curl > /dev/null 2>&1
        curl -sSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/php-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/php-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        apt-get update -qq
    fi

    # 安装 PHP 及扩展
    local extensions="fpm cli common mysql curl gd mbstring xml zip bcmath redis intl soap opcache"
    local pkgs=""
    for ext in $extensions; do
        pkgs="$pkgs php${version}-${ext}"
    done

    apt-get install -y $pkgs > /dev/null 2>&1

    # 配置 PHP-FPM 池
    local pool_conf="/etc/php/${version}/fpm/pool.d/www.conf"
    if [[ -f "$pool_conf" ]]; then
        sed -i "s/^user = .*/user = www/" "$pool_conf"
        sed -i "s/^group = .*/group = www/" "$pool_conf"
        sed -i "s/^listen.owner = .*/listen.owner = www/" "$pool_conf"
        sed -i "s/^listen.group = .*/listen.group = www/" "$pool_conf"
        sed -i "s/^listen.mode = .*/listen.mode = 0660/" "$pool_conf"
    fi

    # 优化 PHP 配置
    local php_ini="/etc/php/${version}/fpm/php.ini"
    if [[ -f "$php_ini" ]]; then
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$php_ini"
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$php_ini"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$php_ini"
        sed -i 's/^max_input_time = .*/max_input_time = 300/' "$php_ini"
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$php_ini"
    fi

    systemctl enable "php${version}-fpm"
    systemctl restart "php${version}-fpm"

    log_success "PHP $version 安装完成"
}

#---------------------------------------
# 安装 MySQL
#---------------------------------------
software_install_mysql() {
    if is_installed mariadb; then
        log_error "MariaDB 已安装，无法同时安装 MySQL"
        return 1
    fi

    log_info "安装 MySQL 8.0..."

    # 生成 root 密码
    local root_pass=$(tr -dc 'a-zA-Z0-9!@#$%' < /dev/urandom | head -c 16)

    # 预设密码
    debconf-set-selections <<< "mysql-server mysql-server/root_password password $root_pass"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $root_pass"

    apt-get install -y mysql-server mysql-client > /dev/null 2>&1

    systemctl enable mysql
    systemctl restart mysql

    # 保存密码到文件
    echo "$root_pass" > "${BASE_DIR}/panel/.mysql_root_password"
    chmod 600 "${BASE_DIR}/panel/.mysql_root_password"

    log_success "MySQL 8.0 安装完成"
    log_info "root 密码已保存到: ${BASE_DIR}/panel/.mysql_root_password"
    echo ""
    echo -e "  ${YELLOW}MySQL root 密码: $root_pass${NC}"
    echo ""
}

#---------------------------------------
# 安装 MariaDB
#---------------------------------------
software_install_mariadb() {
    if is_installed mysql; then
        log_error "MySQL 已安装，无法同时安装 MariaDB"
        return 1
    fi

    log_info "安装 MariaDB..."

    apt-get install -y mariadb-server mariadb-client > /dev/null 2>&1

    # 生成并设置 root 密码
    local root_pass=$(tr -dc 'a-zA-Z0-9!@#$%' < /dev/urandom | head -c 16)

    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_pass';" 2>/dev/null
    mysql -u root -p"$root_pass" -e "FLUSH PRIVILEGES;" 2>/dev/null

    systemctl enable mariadb
    systemctl restart mariadb

    # 保存密码
    echo "$root_pass" > "${BASE_DIR}/panel/.mysql_root_password"
    chmod 600 "${BASE_DIR}/panel/.mysql_root_password"

    log_success "MariaDB 安装完成"
    log_info "root 密码已保存到: ${BASE_DIR}/panel/.mysql_root_password"
    echo ""
    echo -e "  ${YELLOW}MariaDB root 密码: $root_pass${NC}"
    echo ""
}

#---------------------------------------
# 安装 Redis
#---------------------------------------
software_install_redis() {
    log_info "安装 Redis..."

    apt-get install -y redis-server > /dev/null 2>&1

    # 配置 Redis
    local redis_conf="/etc/redis/redis.conf"
    if [[ -f "$redis_conf" ]]; then
        # 设置最大内存
        sed -i 's/^# maxmemory .*/maxmemory 256mb/' "$redis_conf"
        sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' "$redis_conf"
    fi

    systemctl enable redis-server
    systemctl restart redis-server

    log_success "Redis 安装完成 (版本: $(get_version redis))"
}

#---------------------------------------
# 安装 Memcached
#---------------------------------------
software_install_memcached() {
    log_info "安装 Memcached..."

    apt-get install -y memcached libmemcached-tools > /dev/null 2>&1

    systemctl enable memcached
    systemctl restart memcached

    log_success "Memcached 安装完成"
}

#---------------------------------------
# 安装 MongoDB
#---------------------------------------
software_install_mongodb() {
    log_info "安装 MongoDB..."

    # 添加 MongoDB 源
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
    echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] http://repo.mongodb.org/apt/debian $(lsb_release -sc)/mongodb-org/7.0 main" > /etc/apt/sources.list.d/mongodb-org-7.0.list

    apt-get update -qq
    apt-get install -y mongodb-org > /dev/null 2>&1

    systemctl enable mongod
    systemctl start mongod

    log_success "MongoDB 安装完成"
}

#---------------------------------------
# 卸载软件
#---------------------------------------
software_uninstall() {
    local software="$1"
    local version="$2"

    case "$software" in
        nginx)
            log_info "卸载 Nginx..."
            systemctl stop nginx
            apt-get remove -y --purge nginx nginx-common > /dev/null 2>&1
            log_success "Nginx 已卸载"
            ;;
        php)
            if [[ -z "$version" ]]; then
                log_error "请指定 PHP 版本，例如: site uninstall php 8.3"
                return 1
            fi
            log_info "卸载 PHP $version..."
            systemctl stop "php${version}-fpm" 2>/dev/null
            apt-get remove -y --purge "php${version}-*" > /dev/null 2>&1
            log_success "PHP $version 已卸载"
            ;;
        mysql)
            log_info "卸载 MySQL..."
            systemctl stop mysql
            apt-get remove -y --purge mysql-server mysql-client mysql-common > /dev/null 2>&1
            log_success "MySQL 已卸载"
            ;;
        mariadb)
            log_info "卸载 MariaDB..."
            systemctl stop mariadb
            apt-get remove -y --purge mariadb-server mariadb-client mariadb-common > /dev/null 2>&1
            log_success "MariaDB 已卸载"
            ;;
        redis)
            log_info "卸载 Redis..."
            systemctl stop redis-server
            apt-get remove -y --purge redis-server > /dev/null 2>&1
            log_success "Redis 已卸载"
            ;;
        memcached)
            log_info "卸载 Memcached..."
            systemctl stop memcached
            apt-get remove -y --purge memcached > /dev/null 2>&1
            log_success "Memcached 已卸载"
            ;;
        mongodb)
            log_info "卸载 MongoDB..."
            systemctl stop mongod
            apt-get remove -y --purge mongodb-org* > /dev/null 2>&1
            log_success "MongoDB 已卸载"
            ;;
        *)
            log_error "未知软件: $software"
            return 1
            ;;
    esac

    apt-get autoremove -y > /dev/null 2>&1
}

#---------------------------------------
# 列出已安装软件
#---------------------------------------
software_list() {
    echo ""
    echo "已安装的软件:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-15s %-10s %-10s\n" "软件" "版本" "状态"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Nginx
    if command -v nginx &>/dev/null; then
        local status=$(systemctl is-active nginx 2>/dev/null || echo "stopped")
        printf "%-15s %-10s %-10s\n" "Nginx" "$(get_version nginx)" "$status"
    fi

    # PHP
    for version in 7.4 8.0 8.1 8.2 8.3; do
        if command -v "php${version}" &>/dev/null; then
            local status=$(systemctl is-active "php${version}-fpm" 2>/dev/null || echo "stopped")
            printf "%-15s %-10s %-10s\n" "PHP $version" "$(get_version php${version})" "$status"
        fi
    done

    # MySQL
    if command -v mysql &>/dev/null; then
        local db_type="MySQL"
        local status="stopped"
        if systemctl is-active --quiet mysql 2>/dev/null; then
            status="active"
        elif systemctl is-active --quiet mariadb 2>/dev/null; then
            db_type="MariaDB"
            status="active"
        fi
        printf "%-15s %-10s %-10s\n" "$db_type" "$(get_version mysql)" "$status"
    fi

    # Redis
    if command -v redis-server &>/dev/null; then
        local status=$(systemctl is-active redis-server 2>/dev/null || echo "stopped")
        printf "%-15s %-10s %-10s\n" "Redis" "$(get_version redis)" "$status"
    fi

    # Memcached
    if command -v memcached &>/dev/null; then
        local status=$(systemctl is-active memcached 2>/dev/null || echo "stopped")
        printf "%-15s %-10s %-10s\n" "Memcached" "-" "$status"
    fi

    # MongoDB
    if command -v mongod &>/dev/null; then
        local status=$(systemctl is-active mongod 2>/dev/null || echo "stopped")
        printf "%-15s %-10s %-10s\n" "MongoDB" "-" "$status"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#---------------------------------------
# 列出可安装软件
#---------------------------------------
software_available() {
    echo ""
    echo "可安装的软件:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-15s %-40s\n" "软件" "说明"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-15s %-40s\n" "nginx" "高性能 Web 服务器"
    printf "%-15s %-40s\n" "php 8.3" "PHP 8.3 (最新稳定版)"
    printf "%-15s %-40s\n" "php 8.1" "PHP 8.1 (LTS)"
    printf "%-15s %-40s\n" "php 7.4" "PHP 7.4 (旧版兼容)"
    printf "%-15s %-40s\n" "mysql" "MySQL 8.0 数据库"
    printf "%-15s %-40s\n" "mariadb" "MariaDB 数据库"
    printf "%-15s %-40s\n" "redis" "Redis 缓存服务"
    printf "%-15s %-40s\n" "memcached" "Memcached 缓存服务"
    printf "%-15s %-40s\n" "mongodb" "MongoDB 文档数据库"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "安装命令: site install <软件名> [版本]"
    echo "例如: site install php 8.3"
    echo ""
}

#---------------------------------------
# 主入口
#---------------------------------------
software_main() {
    local action="$1"
    shift

    case "$action" in
        install)
            local software="$1"
            local version="$2"

            if [[ -z "$software" ]]; then
                log_error "请指定要安装的软件"
                software_available
                return 1
            fi

            case "$software" in
                nginx)      software_install_nginx ;;
                php)        software_install_php "$version" ;;
                mysql)      software_install_mysql ;;
                mariadb)    software_install_mariadb ;;
                redis)      software_install_redis ;;
                memcached)  software_install_memcached ;;
                mongodb)    software_install_mongodb ;;
                *)
                    log_error "未知软件: $software"
                    software_available
                    return 1
                    ;;
            esac
            ;;
        uninstall)
            software_uninstall "$@"
            ;;
        list)
            software_list
            ;;
        available)
            software_available
            ;;
        *)
            echo "软件管理命令:"
            echo "  site install <软件> [版本]  - 安装软件"
            echo "  site uninstall <软件>       - 卸载软件"
            echo "  site software list          - 列出已安装软件"
            echo "  site software available     - 列出可安装软件"
            ;;
    esac
}
