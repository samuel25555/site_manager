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
