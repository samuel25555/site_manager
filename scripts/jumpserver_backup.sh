#!/bin/bash
#===============================================================================
# JumpServer 数据库备份 + FTP 上传 + 本地/FTP 双侧清理
#
# 用法（crontab）：
#   0 5 * * * /usr/local/bin/site cron run "/opt/site_manager/scripts/jumpserver_backup.sh"
#
# 说明：
#   - installer 路径自动探测（不写死版本号），也可用环境变量 JMS_INSTALLER 指定
#   - FTP 凭据从 /opt/site_manager/config/backup.conf 读（FTP_HOST/USER/PASS/PATH）
#   - 本地保留 KEEP_DAYS 天（find -mtime），FTP 保留最近 KEEP_DAYS 份
#   - 历史坑：JumpServer 官方脚本只上传不清 FTP → FTP 侧会无限积累，本脚本已修
#===============================================================================

set -uo pipefail

BACKUP_DIR="${JMS_BACKUP_DIR:-/data/jumpserver/db_backup}"
KEEP_DAYS="${JMS_KEEP_DAYS:-7}"

# 自动探测 jmsctl.sh（容器升级后 installer 目录会换版本号，别写死）
JMSCTL="${JMS_INSTALLER:-}"
if [ -z "$JMSCTL" ]; then
    JMSCTL=$(ls -dt /opt/jumpserver-installer-v*/jmsctl.sh 2>/dev/null | head -1)
fi
[ -z "$JMSCTL" ] && [ -x /opt/jumpserver/jmsctl.sh ] && JMSCTL=/opt/jumpserver/jmsctl.sh

if [ -z "$JMSCTL" ] || [ ! -x "$JMSCTL" ]; then
    echo "[ERROR] 未找到可用的 jmsctl.sh（设 JMS_INSTALLER 指定）"
    exit 1
fi

# 1. 执行备份
"$JMSCTL" backup_db

# 2. 上传最新备份到 FTP
#    注意：新版 JumpServer 产出 .sql.gz（压缩），旧版是 .sql —— 两者都要匹配
LATEST=$(ls -t "$BACKUP_DIR"/jumpserver-*.sql "$BACKUP_DIR"/jumpserver-*.sql.gz 2>/dev/null | head -1)
if [ -n "${LATEST:-}" ] && [ -f "/opt/site_manager/config/backup.conf" ]; then
    source /opt/site_manager/config/backup.conf
    if [ "${FTP_ENABLED:-false}" = "true" ]; then
        curl -s --ftp-create-dirs -T "$LATEST" \
            "ftp://${FTP_USER}:${FTP_PASS}@${FTP_HOST}:${FTP_PORT}${FTP_PATH}/jumpserver/$(basename "$LATEST")"
        if [ $? -eq 0 ]; then
            echo "[OK] FTP 上传成功: $(basename "$LATEST")"
        else
            echo "[ERROR] FTP 上传失败"
        fi
    fi
fi

# 3. 清理本地超过 KEEP_DAYS 天的旧备份（.sql 和 .sql.gz 都清）
find "$BACKUP_DIR" \( -name 'jumpserver-*.sql' -o -name 'jumpserver-*.sql.gz' \) -mtime +"$KEEP_DAYS" -delete 2>/dev/null
echo "[OK] 已清理本地 ${KEEP_DAYS} 天前的备份"

# 4. 清理 FTP 上多于 KEEP_DAYS 份的旧备份（官方脚本缺这一步，会无限积累）
if [ "${FTP_ENABLED:-false}" = "true" ]; then
    FTP_DIR="${FTP_PATH}/jumpserver"
    # 按文件名里的日期段排序（-t- -k4 从 YYYY-MM-DD 段起），避免版本号(v4.10.x)干扰真实时间顺序
    FILES=$(curl -s --list-only "ftp://${FTP_HOST}:${FTP_PORT}${FTP_DIR}/" \
        --user "${FTP_USER}:${FTP_PASS}" 2>/dev/null | grep "^jumpserver-" | sort -t- -k4)
    TOTAL=$(echo "$FILES" | grep -c .)
    if [ "$TOTAL" -gt "$KEEP_DAYS" ]; then
        echo "$FILES" | head -n $((TOTAL - KEEP_DAYS)) | while IFS= read -r f; do
            [ -z "$f" ] && continue
            curl -s "ftp://${FTP_HOST}:${FTP_PORT}/" --user "${FTP_USER}:${FTP_PASS}" \
                --quote "DELE ${FTP_DIR}/${f}" >/dev/null 2>&1
        done
        echo "[OK] 已清理 FTP 旧备份（保留最近 ${KEEP_DAYS} 份）"
    else
        echo "[OK] FTP 备份 ${TOTAL} 份，无需清理"
    fi
fi
