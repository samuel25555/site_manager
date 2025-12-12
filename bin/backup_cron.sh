#!/bin/bash
#
# Site Manager 定时备份脚本
# 用法: backup_cron.sh db|site
#

source /opt/site_manager/config/backup.conf 2>/dev/null
BACKUP_DIR="${BACKUP_DIR:-/www/backup}"
SITES_DIR="/www/wwwroot"
LOG_FILE="/var/log/site_manager/backup.log"

mkdir -p "$BACKUP_DIR" "$(dirname $LOG_FILE)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 上传到 FTP
upload_ftp() {
    local file="$1"
    [ "$FTP_ENABLED" != "true" ] && return 0
    [ -z "$FTP_HOST" ] && return 0
    
    curl -s -T "$file" "ftp://${FTP_HOST}:${FTP_PORT}${FTP_PATH}/$(basename "$file")" \
        --user "${FTP_USER}:${FTP_PASS}" --ftp-create-dirs 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "FTP上传成功: $(basename "$file")"
        [ "$FTP_DELETE_LOCAL" = "true" ] && rm -f "$file"
    else
        log "FTP上传失败: $(basename "$file")"
    fi
}

# 清理旧备份
cleanup() {
    local pattern="$1"
    local keep="$2"
    local count=$(ls -1 $BACKUP_DIR/${pattern}* 2>/dev/null | wc -l)
    if [ "$count" -gt "$keep" ]; then
        ls -1t $BACKUP_DIR/${pattern}* 2>/dev/null | tail -n +$((keep+1)) | xargs rm -f
        log "清理旧备份: $pattern*, 保留 $keep 份"
    fi
}

# 备份所有数据库
backup_all_db() {
    local keep="${1:-10}"
    log "开始备份数据库..."
    
    while read -r db; do
        [[ "$db" =~ ^(Database|information_schema|performance_schema|mysql|sys)$ ]] && continue
        local file="$BACKUP_DIR/db_${db}_$(date +%Y%m%d_%H%M%S).sql"
        mysqldump "$db" > "$file" 2>/dev/null
        if [ $? -eq 0 ]; then
            gzip "$file"
            log "数据库备份成功: $db"
            upload_ftp "${file}.gz"
            cleanup "db_${db}_" "$keep"
        else
            rm -f "$file"
            log "数据库备份失败: $db"
        fi
    done < <(mysql -N -e "SHOW DATABASES;" 2>/dev/null)
    
    log "数据库备份完成"
}

# 备份站点目录
backup_all_sites() {
    local keep="${1:-7}"
    log "开始备份站点目录..."
    
    for site_dir in "$SITES_DIR"/*/; do
        [ -d "$site_dir" ] || continue
        local site=$(basename "$site_dir")
        local file="$BACKUP_DIR/site_${site}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        tar -czf "$file" -C "$SITES_DIR" "$site" 2>/dev/null
        if [ $? -eq 0 ]; then
            log "站点备份成功: $site"
            upload_ftp "$file"
            cleanup "site_${site}_" "$keep"
        else
            rm -f "$file"
            log "站点备份失败: $site"
        fi
    done
    
    log "站点备份完成"
}

case "$1" in
    db) backup_all_db "${2:-10}";;
    site) backup_all_sites "${2:-7}";;
    *) echo "用法: $0 db|site [保留份数]";;
esac
