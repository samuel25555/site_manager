#!/bin/bash
# FTP 备份脚本 - 备份到远程FTP服务器
# 数据库: 每小时备份，保留51份
# wwwroot: 每天备份，保留7份

# FTP 配置
FTP_HOST="116.213.38.2"
FTP_PORT="2100"
FTP_USER="data_other_backup"
FTP_PASS="EeAxuguKD9aqjp"
FTP_BASE="/UFA"

# 本地配置
MYSQL_USER="root"
MYSQL_PASS=$(cat /www/server/panel/data/default.pl 2>/dev/null || echo "")
WWWROOT_DIR="/www/wwwroot"
TMP_DIR="/tmp/backup_ftp"
LOCAL_BACKUP_DIR="/www/backup"
LOCAL_DB_DIR="$LOCAL_BACKUP_DIR/database"
LOCAL_WWW_DIR="$LOCAL_BACKUP_DIR/wwwroot"

# 保留策略
DB_KEEP=51
WWW_KEEP=7

# 要备份的数据库
DATABASES=("ufa")

# 要备份的站点目录
SITES=("admin.ufa611.com" "h5.ufa612.com" "ufa619.com")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 创建目录
mkdir -p "$TMP_DIR"
mkdir -p "$LOCAL_DB_DIR"
mkdir -p "$LOCAL_WWW_DIR"

# 备份数据库
backup_database() {
    local db="$1"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local filename="${db}_${timestamp}.sql.gz"
    local local_file="$TMP_DIR/$filename"
    local remote_dir="$FTP_BASE/database/mysql/$db"

    log "备份数据库: $db"

    # 导出并压缩
    mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASS" --single-transaction --quick "$db" 2>/dev/null | gzip > "$local_file"

    if [ ! -s "$local_file" ]; then
        log "错误: 数据库备份失败 $db"
        rm -f "$local_file"
        return 1
    fi

    # 上传到FTP
    curl -s -T "$local_file" --ftp-create-dirs \
        "ftp://$FTP_USER:$FTP_PASS@$FTP_HOST:$FTP_PORT$remote_dir/$filename"

    if [ $? -eq 0 ]; then
        log "上传成功: $filename"
    else
        log "错误: 上传失败 $filename"
    fi

    # 保留本地备份
    mv "$local_file" "$LOCAL_DB_DIR/"
    log "本地备份: $LOCAL_DB_DIR/$filename"

    # 清理本地旧备份
    cleanup_local "$LOCAL_DB_DIR" "$DB_KEEP" "${db}_"

    # 清理远程旧备份
    cleanup_ftp "$remote_dir" "$DB_KEEP" "${db}_"
}

# 备份网站目录
backup_wwwroot() {
    local site="$1"
    local timestamp=$(date '+%Y%m%d')
    local filename="${site}_${timestamp}.tar.gz"
    local local_file="$TMP_DIR/$filename"
    local remote_dir="$FTP_BASE/path/wwwroot"
    local site_dir="$WWWROOT_DIR/$site"

    if [ ! -d "$site_dir" ]; then
        log "警告: 站点目录不存在 $site_dir"
        return 1
    fi

    log "备份站点: $site"

    # 打包压缩
    tar -czf "$local_file" -C "$WWWROOT_DIR" "$site" 2>/dev/null

    if [ ! -s "$local_file" ]; then
        log "错误: 站点备份失败 $site"
        rm -f "$local_file"
        return 1
    fi

    # 上传到FTP
    curl -s -T "$local_file" --ftp-create-dirs \
        "ftp://$FTP_USER:$FTP_PASS@$FTP_HOST:$FTP_PORT$remote_dir/$filename"

    if [ $? -eq 0 ]; then
        log "上传成功: $filename ($(du -h "$local_file" | cut -f1))"
    else
        log "错误: 上传失败 $filename"
    fi

    # 保留本地备份
    mv "$local_file" "$LOCAL_WWW_DIR/"
    log "本地备份: $LOCAL_WWW_DIR/$filename"

    # 清理本地旧备份
    cleanup_local "$LOCAL_WWW_DIR" "$WWW_KEEP" "${site}_"

    # 清理远程旧备份
    cleanup_ftp "$remote_dir" "$WWW_KEEP" "${site}_"
}

# 清理本地旧备份
cleanup_local() {
    local dir="$1"
    local keep="$2"
    local prefix="$3"

    local files=$(ls -1 "$dir" 2>/dev/null | grep "^${prefix}" | sort -r)

    local count=0
    for file in $files; do
        count=$((count + 1))
        if [ $count -gt $keep ]; then
            log "删除本地旧备份: $file"
            rm -f "$dir/$file"
        fi
    done
}

# 清理FTP旧备份
cleanup_ftp() {
    local remote_dir="$1"
    local keep="$2"
    local prefix="$3"

    # 获取文件列表
    local files=$(curl -s --list-only "ftp://$FTP_USER:$FTP_PASS@$FTP_HOST:$FTP_PORT$remote_dir/" 2>/dev/null | grep "^${prefix}" | sort -r)

    local count=0
    for file in $files; do
        count=$((count + 1))
        if [ $count -gt $keep ]; then
            log "删除旧备份: $file"
            curl -s -Q "-DELE $remote_dir/$file" "ftp://$FTP_USER:$FTP_PASS@$FTP_HOST:$FTP_PORT/" >/dev/null 2>&1
        fi
    done
}

# 主逻辑
case "$1" in
    database|db)
        log "=== 开始数据库备份 ==="
        for db in "${DATABASES[@]}"; do
            backup_database "$db"
        done
        log "=== 数据库备份完成 ==="
        ;;
    wwwroot|www)
        log "=== 开始站点备份 ==="
        for site in "${SITES[@]}"; do
            backup_wwwroot "$site"
        done
        log "=== 站点备份完成 ==="
        ;;
    all)
        log "=== 开始全部备份 ==="
        for db in "${DATABASES[@]}"; do
            backup_database "$db"
        done
        for site in "${SITES[@]}"; do
            backup_wwwroot "$site"
        done
        log "=== 全部备份完成 ==="
        ;;
    *)
        echo "用法: $0 {database|wwwroot|all}"
        echo "  database - 备份数据库 (每小时，保留${DB_KEEP}份)"
        echo "  wwwroot  - 备份站点目录 (每天，保留${WWW_KEEP}份)"
        echo "  all      - 备份全部"
        exit 1
        ;;
esac

# 清理临时目录
rmdir "$TMP_DIR" 2>/dev/null
