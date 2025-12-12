#!/bin/bash
#
# Site Manager 定时备份脚本
# 用法: backup_cron.sh db|site|path [保留份数] [路径]
#

source /opt/site_manager/config/backup.conf 2>/dev/null
BACKUP_DIR="${BACKUP_DIR:-/www/backup}"
SITES_DIR="/www/wwwroot"
LOG_FILE="/var/log/site_manager/backup.log"
EXCLUDE_CONF="/opt/site_manager/config/backup_exclude.conf"

# 按类型分目录
DB_BACKUP_DIR="$BACKUP_DIR/database"
SITE_BACKUP_DIR="$BACKUP_DIR/site"
PATH_BACKUP_DIR="$BACKUP_DIR/path"

mkdir -p "$DB_BACKUP_DIR" "$SITE_BACKUP_DIR" "$PATH_BACKUP_DIR" "$(dirname $LOG_FILE)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 生成 tar 排除参数
get_exclude_args() {
    local args=""
    if [ -f "$EXCLUDE_CONF" ]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            args="$args --exclude=$line"
        done < "$EXCLUDE_CONF"
    fi
    echo "$args"
}

# 上传到 FTP
upload_ftp() {
    local file="$1"
    local subdir="$2"
    [ "$FTP_ENABLED" != "true" ] && return 0
    [ -z "$FTP_HOST" ] && return 0
    
    log "上传FTP: $(basename "$file")"
    curl -s -T "$file" "ftp://${FTP_HOST}:${FTP_PORT}${FTP_PATH}/${subdir}/$(basename "$file")" \
        --user "${FTP_USER}:${FTP_PASS}" --ftp-create-dirs 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "FTP上传成功"
        [ "$FTP_DELETE_LOCAL" = "true" ] && rm -f "$file"
    else
        log "FTP上传失败"
    fi
}

# 清理旧备份
cleanup() {
    local dir="$1"
    local pattern="$2"
    local keep="$3"
    local count=$(ls -1 $dir/${pattern}* 2>/dev/null | wc -l)
    if [ "$count" -gt "$keep" ]; then
        local del_count=$((count - keep))
        ls -1t $dir/${pattern}* 2>/dev/null | tail -n +$((keep+1)) | xargs rm -f
        log "清理旧备份: 删除 $del_count 份，保留 $keep 份"
    fi
}

# 备份所有数据库
backup_all_db() {
    local keep="${1:-10}"
    log "========== 开始备份数据库 =========="
    
    local db_count=0
    while read -r db; do
        [[ "$db" =~ ^(Database|information_schema|performance_schema|mysql|sys)$ ]] && continue
        local file="$DB_BACKUP_DIR/${db}_$(date +%Y%m%d_%H%M%S).sql"
        
        mysqldump --single-transaction --quick "$db" > "$file" 2>/dev/null
        if [ $? -eq 0 ] && [ -s "$file" ]; then
            gzip -f "$file"
            local size=$(du -h "${file}.gz" | cut -f1)
            log "备份成功: $db ($size)"
            upload_ftp "${file}.gz" "database"
            cleanup "$DB_BACKUP_DIR" "${db}_" "$keep"
            ((db_count++))
        else
            rm -f "$file"
            log "备份失败: $db"
        fi
    done < <(mysql -N -e "SHOW DATABASES;" 2>/dev/null)
    
    log "数据库备份完成: 共 $db_count 个"
    log ""
}

# 备份站点目录
backup_all_sites() {
    local keep="${1:-7}"
    log "========== 开始备份站点 =========="
    
    local exclude_args=$(get_exclude_args)
    local site_count=0
    
    for site_dir in "$SITES_DIR"/*/; do
        [ -d "$site_dir" ] || continue
        local site=$(basename "$site_dir")
        local file="$SITE_BACKUP_DIR/${site}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        eval tar -czf "$file" $exclude_args -C "$SITES_DIR" "$site" 2>/dev/null
        
        if [ $? -eq 0 ] && [ -s "$file" ]; then
            local size=$(du -h "$file" | cut -f1)
            log "备份成功: $site ($size)"
            upload_ftp "$file" "site"
            cleanup "$SITE_BACKUP_DIR" "${site}_" "$keep"
            ((site_count++))
        else
            rm -f "$file"
            log "备份失败: $site"
        fi
    done
    
    log "站点备份完成: 共 $site_count 个"
    log ""
}

# 备份指定路径
backup_path() {
    local keep="${1:-7}"
    local target_path="$2"
    
    [ -z "$target_path" ] && log "错误: 未指定路径" && return 1
    [ ! -e "$target_path" ] && log "错误: 路径不存在 $target_path" && return 1
    
    log "========== 开始备份路径 =========="
    log "路径: $target_path"
    
    local exclude_args=$(get_exclude_args)
    local name=$(basename "$target_path")
    local parent=$(dirname "$target_path")
    local file="$PATH_BACKUP_DIR/${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    eval tar -czf "$file" $exclude_args -C "$parent" "$name" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -s "$file" ]; then
        local size=$(du -h "$file" | cut -f1)
        log "备份成功: $name ($size)"
        upload_ftp "$file" "path"
        cleanup "$PATH_BACKUP_DIR" "${name}_" "$keep"
    else
        rm -f "$file"
        log "备份失败: $target_path"
    fi
    
    log ""
}

case "$1" in
    db|database) backup_all_db "${2:-10}";;
    site) backup_all_sites "${2:-7}";;
    path) backup_path "${2:-7}" "$3";;
    all) backup_all_db "${2:-10}"; backup_all_sites "${3:-7}";;
    *)
        echo "用法:"
        echo "  $0 db [保留份数]           备份所有数据库"
        echo "  $0 site [保留份数]         备份所有站点"
        echo "  $0 path [保留份数] <路径>  备份指定路径"
        echo "  $0 all [db保留] [site保留] 备份全部"
        ;;
esac
