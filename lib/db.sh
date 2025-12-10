#!/bin/bash
# 数据库管理

db_create() {
    local name="$1"
    
    check_root
    
    if [ -z "$name" ]; then
        log_error "用法: site db create <name>"
        return 1
    fi
    
    local password="$(random_string 16)"
    
    log_info "创建数据库: $name"
    
    mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS \`$name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$name'@'localhost' IDENTIFIED BY '$password';
GRANT ALL PRIVILEGES ON \`$name\`.* TO '$name'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        log_success "数据库创建成功"
        echo ""
        echo "数据库名: $name"
        echo "用户名: $name"
        echo "密码: $password"
        echo "主机: localhost"
        echo ""
    else
        log_error "数据库创建失败"
        return 1
    fi
}

db_drop() {
    local name="$1"
    
    check_root
    
    if [ -z "$name" ]; then
        log_error "用法: site db drop <name>"
        return 1
    fi
    
    if ! confirm "确定要删除数据库 $name 吗? 此操作不可恢复!"; then
        log_info "操作已取消"
        return 0
    fi
    
    log_info "删除数据库: $name"
    
    mysql -u root << EOF
DROP DATABASE IF EXISTS \`$name\`;
DROP USER IF EXISTS '$name'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        log_success "数据库已删除"
    else
        log_error "数据库删除失败"
        return 1
    fi
}

db_import() {
    local name="$1"
    local file="$2"
    
    check_root
    
    if [ -z "$name" ] || [ -z "$file" ]; then
        log_error "用法: site db import <name> <file>"
        return 1
    fi
    
    if [ ! -f "$file" ]; then
        log_error "文件不存在: $file"
        return 1
    fi
    
    log_info "导入数据库: $name <- $file"
    
    if [[ "$file" == *.gz ]]; then
        gunzip -c "$file" | mysql -u root "$name"
    else
        mysql -u root "$name" < "$file"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "数据库导入成功"
    else
        log_error "数据库导入失败"
        return 1
    fi
}

db_export() {
    local name="$1"
    
    check_root
    
    if [ -z "$name" ]; then
        log_error "用法: site db export <name>"
        return 1
    fi
    
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local file="$BACKUP_DIR/db_${name}_${timestamp}.sql.gz"
    
    mkdir -p "$BACKUP_DIR"
    
    log_info "导出数据库: $name -> $file"
    
    mysqldump -u root "$name" | gzip > "$file"
    
    if [ $? -eq 0 ]; then
        log_success "数据库导出成功: $file"
        ls -lh "$file"
    else
        log_error "数据库导出失败"
        return 1
    fi
}

db_list() {
    echo ""
    echo "数据库列表:"
    echo "-----------------------------------"
    mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$"
    echo ""
}

db_backup_all() {
    check_root
    
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$BACKUP_DIR/db"
    
    mkdir -p "$backup_dir"
    
    log_info "备份所有数据库..."
    
    local databases=$(mysql -u root -N -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(information_schema|performance_schema|mysql|sys)$")
    
    local count=0
    for db in $databases; do
        local file="$backup_dir/${db}_${timestamp}.sql.gz"
        mysqldump -u root "$db" 2>/dev/null | gzip > "$file"
        if [ $? -eq 0 ]; then
            log_success "  $db -> $file"
            ((count++))
        else
            log_error "  $db 备份失败"
        fi
    done
    
    log_success "共备份 $count 个数据库"
    
    # 清理旧备份 (保留最近 N 天)
    local keep_days="${DB_BACKUP_KEEP_DAYS:-7}"
    find "$backup_dir" -name "*.sql.gz" -mtime +$keep_days -delete 2>/dev/null
    local deleted=$?
    if [ $deleted -eq 0 ]; then
        log_info "已清理 $keep_days 天前的旧备份"
    fi
}

db_cron_setup() {
    local interval="$1"  # hourly, daily, weekly
    
    check_root
    
    if [ -z "$interval" ]; then
        echo "用法: site db cron <hourly|daily|weekly|off>"
        echo ""
        echo "  hourly  - 每小时备份一次"
        echo "  daily   - 每天凌晨 3 点备份"
        echo "  weekly  - 每周日凌晨 3 点备份"
        echo "  off     - 关闭自动备份"
        echo ""
        echo "当前状态:"
        if [ -f /etc/cron.d/site-db-backup ]; then
            cat /etc/cron.d/site-db-backup
        else
            echo "  未配置自动备份"
        fi
        return 0
    fi
    
    local cron_file="/etc/cron.d/site-db-backup"
    local cmd="/usr/local/bin/site-new db backup-all > /dev/null 2>&1"
    
    case "$interval" in
        hourly)
            echo "0 * * * * root $cmd" > "$cron_file"
            log_success "已设置每小时自动备份数据库"
            ;;
        daily)
            echo "0 3 * * * root $cmd" > "$cron_file"
            log_success "已设置每天凌晨 3 点自动备份数据库"
            ;;
        weekly)
            echo "0 3 * * 0 root $cmd" > "$cron_file"
            log_success "已设置每周日凌晨 3 点自动备份数据库"
            ;;
        off)
            rm -f "$cron_file"
            log_success "已关闭自动备份"
            ;;
        *)
            log_error "无效的间隔: $interval"
            echo "有效选项: hourly, daily, weekly, off"
            return 1
            ;;
    esac
    
    # 重载 cron
    systemctl reload cron 2>/dev/null || service cron reload 2>/dev/null
}

db_backups() {
    local name="$1"
    local backup_dir="$BACKUP_DIR/db"
    
    echo ""
    echo "数据库备份列表:"
    echo "-----------------------------------"
    
    if [ -n "$name" ]; then
        ls -lh "$backup_dir"/${name}_*.sql.gz 2>/dev/null || echo "没有找到 $name 的备份"
    else
        ls -lh "$backup_dir"/*.sql.gz 2>/dev/null || echo "没有备份文件"
    fi
    echo ""
}
