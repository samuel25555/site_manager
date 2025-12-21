#!/bin/bash
#
# Site Manager 通用备份脚本
#
# 用法:
#   backup_cron.sh db [name] [保留份数]     备份数据库
#   backup_cron.sh site [name] [保留份数]   备份网站（wwwroot下）
#   backup_cron.sh path [目录] [保留份数]   备份目录
#   backup_cron.sh all                      备份全部

# 加载配置
source /opt/site_manager/config/backup.conf 2>/dev/null
source /opt/site_manager/config/site_manager.conf 2>/dev/null

# 默认值
BACKUP_DIR="${BACKUP_DIR:-/www/backup}"
SITES_DIR="/www/wwwroot"
DEFAULT_BACKUP_PATH="${DEFAULT_BACKUP_PATH:-/www/wwwroot}"
LOG_FILE="/www/wwwlogs/site_manager/backup.log"
EXCLUDE_CONF="/opt/site_manager/config/backup_exclude.conf"

# 默认保留份数
DB_KEEP="${DB_KEEP:-51}"
SITE_KEEP="${SITE_KEEP:-7}"
PATH_KEEP="${PATH_KEEP:-7}"

# MySQL 认证
MYSQL_PWD_FILE="${MYSQL_DEFAULTS_FILE:-/www/server/mysql_root.pwd}"
MYSQL_USER="root"
[ -f "$MYSQL_PWD_FILE" ] && MYSQL_PASS="$(cat "$MYSQL_PWD_FILE")"

# 备份子目录
DB_BACKUP_DIR="$BACKUP_DIR/database"
SITE_BACKUP_DIR="$BACKUP_DIR/site"
PATH_BACKUP_DIR="$BACKUP_DIR/path"

mkdir -p "$DB_BACKUP_DIR" "$SITE_BACKUP_DIR" "$PATH_BACKUP_DIR" "$(dirname $LOG_FILE)"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# 生成排除参数
get_exclude_args() {
    local args=""
    [ -f "$EXCLUDE_CONF" ] && while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        args="$args --exclude=$line"
    done < "$EXCLUDE_CONF"
    echo "$args"
}

# FTP上传
upload_ftp() {
    local file="$1" subdir="$2"
    [ "$FTP_ENABLED" != "true" ] || [ -z "$FTP_HOST" ] && return 0
    log "上传FTP: $(basename "$file")"
    if curl -s -T "$file" "ftp://${FTP_HOST}:${FTP_PORT}${FTP_PATH}/${subdir}/$(basename "$file")" \
        --user "${FTP_USER}:${FTP_PASS}" --ftp-create-dirs 2>/dev/null; then
        log "FTP上传成功"
        [ "$FTP_DELETE_LOCAL" = "true" ] && rm -f "$file"
    else
        log "FTP上传失败"
    fi
}

# 清理旧备份
cleanup() {
    local dir="$1" pattern="$2" keep="$3"
    local count=$(ls -1 "$dir"/${pattern}* 2>/dev/null | wc -l)
    if [ "$count" -gt "$keep" ]; then
        ls -1t "$dir"/${pattern}* | tail -n +$((keep+1)) | xargs rm -f
        log "清理旧备份: 删除 $((count-keep)) 份，保留 $keep 份"
    fi
}

# ==================== 数据库备份 ====================
backup_db_one() {
    local db="$1" keep="${2:-$DB_KEEP}"
    [ -z "$MYSQL_PASS" ] && { log "错误: 未找到MySQL密码"; return 1; }
    
    local file="$DB_BACKUP_DIR/${db}_$(date +%Y%m%d_%H%M%S).sql"
    mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASS" --single-transaction --quick "$db" > "$file" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -s "$file" ]; then
        gzip -f "$file"
        log "备份成功: $db ($(du -h "${file}.gz" | cut -f1))"
        upload_ftp "${file}.gz" "database"
        cleanup "$DB_BACKUP_DIR" "${db}_" "$keep"
    else
        rm -f "$file"; log "备份失败: $db"; return 1
    fi
}

backup_db_all() {
    local keep="${1:-$DB_KEEP}"
    log "========== 备份所有数据库 =========="
    [ -z "$MYSQL_PASS" ] && { log "错误: 未找到MySQL密码"; return 1; }
    
    local count=0
    while read -r db; do
        [[ "$db" =~ ^(Database|information_schema|performance_schema|mysql|sys)$ ]] && continue
        backup_db_one "$db" "$keep" && ((count++))
    done < <(mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW DATABASES;" 2>/dev/null)
    log "数据库备份完成: 共 $count 个"; log ""
}

backup_database() {
    if [ -z "$1" ]; then backup_db_all "${2:-$DB_KEEP}"
    else log "========== 备份数据库: $1 =========="; backup_db_one "$1" "${2:-$DB_KEEP}"; log ""
    fi
}

# ==================== 网站备份 ====================
backup_site_one() {
    local site="$1" keep="${2:-$SITE_KEEP}"
    local site_path="$SITES_DIR/$site"
    [ ! -d "$site_path" ] && { log "错误: 网站不存在 $site"; return 1; }
    
    local exclude_args=$(get_exclude_args)
    local file="$SITE_BACKUP_DIR/${site}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    eval tar -czf "$file" $exclude_args -C "$SITES_DIR" "$site" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -s "$file" ]; then
        log "备份成功: $site ($(du -h "$file" | cut -f1))"
        upload_ftp "$file" "site"
        cleanup "$SITE_BACKUP_DIR" "${site}_" "$keep"
    else
        rm -f "$file"; log "备份失败: $site"; return 1
    fi
}

backup_site_all() {
    local keep="${1:-$SITE_KEEP}"
    log "========== 备份所有网站 =========="
    
    local exclude_args=$(get_exclude_args)
    local file="$SITE_BACKUP_DIR/wwwroot_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log "打包: $SITES_DIR"
    eval tar -czf "$file" $exclude_args -C "$(dirname $SITES_DIR)" "$(basename $SITES_DIR)" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -s "$file" ]; then
        log "备份成功: wwwroot ($(du -h "$file" | cut -f1))"
        upload_ftp "$file" "site"
        cleanup "$SITE_BACKUP_DIR" "wwwroot_" "$keep"
    else
        rm -f "$file"; log "备份失败: $SITES_DIR"
    fi
    log ""
}

backup_site() {
    if [ -z "$1" ]; then backup_site_all "${2:-$SITE_KEEP}"
    else log "========== 备份网站: $1 =========="; backup_site_one "$1" "${2:-$SITE_KEEP}"; log ""
    fi
}

# ==================== 目录备份 ====================
backup_path() {
    local target="${1:-$DEFAULT_BACKUP_PATH}" keep="${2:-$PATH_KEEP}"
    
    [ ! -e "$target" ] && { log "错误: 目录不存在 $target"; return 1; }
    
    log "========== 备份目录 =========="
    log "目录: $target"
    
    local exclude_args=$(get_exclude_args)
    local name=$(basename "$target")
    local file="$PATH_BACKUP_DIR/${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    eval tar -czf "$file" $exclude_args -C "$(dirname $target)" "$name" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -s "$file" ]; then
        log "备份成功: $name ($(du -h "$file" | cut -f1))"
        upload_ftp "$file" "path"
        cleanup "$PATH_BACKUP_DIR" "${name}_" "$keep"
    else
        rm -f "$file"; log "备份失败: $target"
    fi
    log ""
}

# ==================== 帮助 ====================
show_help() {
    echo "Site Manager 通用备份脚本"
    echo ""
    echo "用法:"
    echo "  $0 db [name] [保留数]    备份数据库（默认全部，保留${DB_KEEP}份）"
    echo "  $0 site [name] [保留数]  备份网站（默认全部，保留${SITE_KEEP}份）"
    echo "  $0 path [目录] [保留数]  备份目录（默认${DEFAULT_BACKUP_PATH}，保留${PATH_KEEP}份）"
    echo "  $0 all                   备份全部"
    echo ""
    echo "示例:"
    echo "  $0 db                    备份所有数据库"
    echo "  $0 db ufa 10             备份ufa库，保留10份"
    echo "  $0 site                  备份所有网站"
    echo "  $0 site admin.xxx.com    备份指定网站"
    echo "  $0 path                  备份默认目录 ${DEFAULT_BACKUP_PATH}"
    echo "  $0 path /opt/app 5       备份指定目录，保留5份"
}

# ==================== 主入口 ====================
case "$1" in
    db|database) backup_database "$2" "$3" ;;
    site)        backup_site "$2" "$3" ;;
    path)        backup_path "$2" "$3" ;;
    all)         backup_db_all; backup_site_all ;;
    *)           show_help ;;
esac
