#!/bin/bash
# 系统配置检测和参数优化

# 获取系统内存 (MB)
get_memory_mb() {
    free -m | awk '/Mem:/ {print $2}'
}

# 获取 CPU 核心数
get_cpu_cores() {
    nproc
}

# 根据内存计算 Nginx 参数
calc_nginx_params() {
    local mem_mb=$(get_memory_mb)
    local cores=$(get_cpu_cores)

    if [ "$mem_mb" -ge 65536 ]; then
        NGINX_WORKER_CONNECTIONS=51200
        NGINX_WORKER_RLIMIT=65535
    elif [ "$mem_mb" -ge 16384 ]; then
        NGINX_WORKER_CONNECTIONS=30720
        NGINX_WORKER_RLIMIT=51200
    elif [ "$mem_mb" -ge 8192 ]; then
        NGINX_WORKER_CONNECTIONS=20480
        NGINX_WORKER_RLIMIT=30720
    elif [ "$mem_mb" -ge 4096 ]; then
        NGINX_WORKER_CONNECTIONS=10240
        NGINX_WORKER_RLIMIT=20480
    else
        NGINX_WORKER_CONNECTIONS=4096
        NGINX_WORKER_RLIMIT=10240
    fi
}

# 根据内存计算 MariaDB 参数
calc_mariadb_params() {
    local mem_mb=$(get_memory_mb)

    if [ "$mem_mb" -ge 65536 ]; then
        MYSQL_INNODB_BUFFER="32G"
        MYSQL_MAX_CONNECTIONS=500
        MYSQL_KEY_BUFFER="1024M"
        MYSQL_TMP_TABLE="512M"
    elif [ "$mem_mb" -ge 16384 ]; then
        MYSQL_INNODB_BUFFER="4G"
        MYSQL_MAX_CONNECTIONS=300
        MYSQL_KEY_BUFFER="512M"
        MYSQL_TMP_TABLE="256M"
    elif [ "$mem_mb" -ge 8192 ]; then
        MYSQL_INNODB_BUFFER="2G"
        MYSQL_MAX_CONNECTIONS=200
        MYSQL_KEY_BUFFER="256M"
        MYSQL_TMP_TABLE="128M"
    elif [ "$mem_mb" -ge 4096 ]; then
        MYSQL_INNODB_BUFFER="1G"
        MYSQL_MAX_CONNECTIONS=150
        MYSQL_KEY_BUFFER="128M"
        MYSQL_TMP_TABLE="64M"
    else
        MYSQL_INNODB_BUFFER="512M"
        MYSQL_MAX_CONNECTIONS=100
        MYSQL_KEY_BUFFER="64M"
        MYSQL_TMP_TABLE="32M"
    fi
}

# 根据内存计算 PHP-FPM 参数
calc_php_params() {
    local mem_mb=$(get_memory_mb)

    if [ "$mem_mb" -ge 65536 ]; then
        PHP_MAX_CHILDREN=300
        PHP_START_SERVERS=30
        PHP_MIN_SPARE=20
        PHP_MAX_SPARE=50
        PHP_OPCACHE_MEM=512
    elif [ "$mem_mb" -ge 16384 ]; then
        PHP_MAX_CHILDREN=150
        PHP_START_SERVERS=20
        PHP_MIN_SPARE=10
        PHP_MAX_SPARE=30
        PHP_OPCACHE_MEM=256
    elif [ "$mem_mb" -ge 8192 ]; then
        PHP_MAX_CHILDREN=80
        PHP_START_SERVERS=10
        PHP_MIN_SPARE=5
        PHP_MAX_SPARE=20
        PHP_OPCACHE_MEM=192
    elif [ "$mem_mb" -ge 4096 ]; then
        PHP_MAX_CHILDREN=50
        PHP_START_SERVERS=5
        PHP_MIN_SPARE=3
        PHP_MAX_SPARE=10
        PHP_OPCACHE_MEM=128
    else
        PHP_MAX_CHILDREN=20
        PHP_START_SERVERS=3
        PHP_MIN_SPARE=2
        PHP_MAX_SPARE=5
        PHP_OPCACHE_MEM=64
    fi
}

# 生成 Nginx 配置
generate_nginx_conf() {
    calc_nginx_params
    cat << EOF
user www www;
worker_processes auto;
worker_rlimit_nofile ${NGINX_WORKER_RLIMIT};
pid /run/nginx.pid;
error_log /var/log/nginx/error.log crit;
include /etc/nginx/modules-enabled/*.conf;

events {
    use epoll;
    worker_connections ${NGINX_WORKER_CONNECTIONS};
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server_names_hash_bucket_size 512;
    client_header_buffer_size 32k;
    large_client_header_buffers 4 32k;
    client_max_body_size 50m;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 60;

    fastcgi_connect_timeout 300;
    fastcgi_send_timeout 300;
    fastcgi_read_timeout 300;
    fastcgi_buffer_size 64k;
    fastcgi_buffers 4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 256k;
    fastcgi_intercept_errors on;

    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 16k;
    gzip_http_version 1.1;
    gzip_comp_level 5;
    gzip_types text/plain application/javascript application/x-javascript text/javascript text/css application/xml application/json image/jpeg image/gif image/png font/ttf font/otf image/svg+xml application/xml+rss;
    gzip_vary on;
    gzip_proxied expired no-cache no-store private auth;
    gzip_disable "MSIE [1-6]\.";

    server_tokens off;
    limit_conn_zone \$binary_remote_addr zone=perip:10m;
    limit_conn_zone \$server_name zone=perserver:10m;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
}

# 生成 MariaDB 配置
generate_mariadb_conf() {
    calc_mariadb_params
    cat << EOF
# 自动生成的 MariaDB 优化配置
[mysqld]
max_connections = ${MYSQL_MAX_CONNECTIONS}
max_connect_errors = 100
open_files_limit = 65535

key_buffer_size = ${MYSQL_KEY_BUFFER}
max_allowed_packet = 100M
table_open_cache = 4096
sort_buffer_size = 16M
read_buffer_size = 16M
read_rnd_buffer_size = 256K
thread_cache_size = 128
tmp_table_size = ${MYSQL_TMP_TABLE}
max_heap_table_size = ${MYSQL_TMP_TABLE}

innodb_buffer_pool_size = ${MYSQL_INNODB_BUFFER}
innodb_log_file_size = 512M
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_lock_wait_timeout = 50
innodb_read_io_threads = 8
innodb_write_io_threads = 8
innodb_file_per_table = 1

slow_query_log = 1
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 3
EOF
}

# 生成 PHP-FPM pool 配置
generate_php_fpm_conf() {
    local version="${1:-8.0}"
    calc_php_params
    cat << EOF
[www]
user = www
group = www
listen = /run/php/php${version}-fpm.sock
listen.owner = www
listen.group = www
listen.mode = 0660
listen.backlog = 8192

pm = dynamic
pm.max_children = ${PHP_MAX_CHILDREN}
pm.start_servers = ${PHP_START_SERVERS}
pm.min_spare_servers = ${PHP_MIN_SPARE}
pm.max_spare_servers = ${PHP_MAX_SPARE}

request_terminate_timeout = 100
request_slowlog_timeout = 30
slowlog = /var/log/php${version}-fpm-slow.log
EOF
}

# 生成 OPcache 配置
generate_opcache_conf() {
    calc_php_params
    cat << EOF
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=${PHP_OPCACHE_MEM}
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=50000
opcache.max_wasted_percentage=10
opcache.validate_timestamps=1
opcache.revalidate_freq=60
opcache.save_comments=1
opcache.fast_shutdown=1
EOF
}

# 生成系统限制配置
generate_limits_conf() {
    cat << EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
www soft nofile 65535
www hard nofile 65535
EOF
}

# 生成 sysctl 配置
generate_sysctl_conf() {
    cat << EOF
fs.file-max = 65535
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
EOF
}
