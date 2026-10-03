#!/bin/bash
#===============================================================================
# 服务器配置备份（灾备用）——补齐 db/site/path 备份之外"重建一台机器"所需的全部配置
#
# 打包内容（tar 内为去掉前导 / 的绝对路径，恢复时 tar -xzpf 包 -C / 指定路径即可）：
#   nginx/vhost/证书(/www/ssl + /etc/letsencrypt)、site_manager 配置(DNS/FTP 凭据)、
#   cron、supervisor、PHP/MySQL/Redis 配置、UFW/SSH/systemd/sysctl/limits、
#   docker compose 编排与 .env、/usr/local/bin 小脚本、/root/tools
# 另生成 _meta/ 清单：MySQL 账号与授权(库备份不含 mysql 系统库)、包清单、PHP 扩展、
#   监听端口、防火墙规则、docker 现状、site list、磁盘布局 —— 新机照着装软件
#
# 输出: $BACKUP_DIR/server/server_<主机>_YYYYMMDD_HHMMSS.tar.gz (600 权限)
# FTP:  $FTP_PATH/server/ （与 db/site/path 同一 FTP 账号）
# 用法: server_config_backup.sh [保留份数]   (默认 30)
#===============================================================================
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

source /opt/site_manager/config/backup.conf 2>/dev/null
source /opt/site_manager/config/site_manager.conf 2>/dev/null

BACKUP_DIR="${BACKUP_DIR:-/www/backup}"
KEEP="${1:-${SERVER_KEEP:-30}}"
DEST="$BACKUP_DIR/server"
LOG_FILE="/www/wwwlogs/site_manager/backup.log"
HOST="${FTP_PATH##*/}"; HOST="${HOST:-$(hostname -s)}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$DEST/server_${HOST}_${TS}.tar.gz"

mkdir -p "$DEST" "$(dirname "$LOG_FILE")"
chmod 700 "$DEST"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

STAGE="$(mktemp -d /tmp/server_backup_XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
META="$STAGE/_meta"
mkdir -p "$META"

log "========== 备份服务器配置: $HOST =========="

# ---------- 1. 清单（命令输出，失败不影响整体） ----------
run() { local f="$1"; shift; { "$@"; } > "$META/$f" 2>&1 || true; }

run system.txt bash -c 'hostname -f; echo; cat /etc/os-release; echo; uname -a; echo; ip -br addr; echo; ip route; echo; cat /etc/resolv.conf'
run disks.txt bash -c 'df -hT; echo; lsblk -f; echo; cat /etc/fstab'
run packages.txt dpkg --get-selections
run packages_manual.txt apt-mark showmanual
run listen_ports.txt ss -lntup
run systemd_enabled.txt systemctl list-unit-files --state=enabled --no-pager
run nginx_version.txt nginx -V
run ufw_status.txt ufw status verbose
run iptables.rules iptables-save
run ip6tables.rules ip6tables-save
run site_list.txt /usr/local/bin/site list
run crontab_root.txt crontab -l
for v in /etc/php/*/; do
    v="$(basename "$v")"
    command -v "php$v" >/dev/null && run "php${v}_modules.txt" "php$v" -m
done
if command -v docker >/dev/null; then
    run docker_ps.txt docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    run docker_compose_ls.txt docker compose ls -a
    run docker_volumes.txt docker volume ls
    run docker_images.txt docker images
fi

# MySQL 账号 + 授权：每库 dump 不含 mysql 系统库，新机恢复后应用连不上库就是缺这个
MYSQL_PWD_FILE="${MYSQL_DEFAULTS_FILE:-/www/server/mysql_root.pwd}"
if command -v mysql >/dev/null && [ -f "$MYSQL_PWD_FILE" ]; then
    export MYSQL_PWD="$(cat "$MYSQL_PWD_FILE")"
    {
        echo "-- MySQL 账号与授权 @ $HOST $(date '+%F %T')"
        echo "-- 恢复: mysql -uroot -p < mysql_grants.sql （已存在的账号会报错，可忽略或先删）"
        mysql -uroot -N -e "SELECT CONCAT(QUOTE(user),'@',QUOTE(host)) FROM mysql.user WHERE user NOT IN ('','mariadb.sys','mysql.sys','mysql.session','mysql.infoschema')" 2>/dev/null |
        while read -r u; do
            mysql -uroot -N -e "SHOW CREATE USER $u" 2>/dev/null | sed 's/$/;/'
            mysql -uroot -N -e "SHOW GRANTS FOR $u" 2>/dev/null | sed 's/$/;/'
            echo
        done
    } > "$META/mysql_grants.sql"
    mysql -uroot -e "SELECT table_schema db, ROUND(SUM(data_length+index_length)/1048576,1) size_mb, COUNT(*) tables FROM information_schema.tables GROUP BY table_schema" \
        > "$META/mysql_databases.txt" 2>&1
    mysql -uroot -e "SELECT VERSION()" > "$META/mysql_version.txt" 2>&1
    unset MYSQL_PWD
fi

cat > "$META/RESTORE.md" <<'EOF'
# 用本包恢复一台服务器（概要，详见 site_manager/docs/disaster-recovery.md）

1. 新机装好系统 → 装 site_manager（install.sh），软件按 _meta/packages_manual.txt、php*_modules.txt 补齐
2. 解包到临时目录先看：  mkdir /root/restore && tar -xzpf server_*.tar.gz -C /root/restore
3. 按需拷回（不要整包盲目覆盖 /etc，网卡/fstab/ssh 端口要和新机核对）：
   - nginx:      etc/nginx  www/vhost  www/ssl  etc/letsencrypt
   - site_manager 配置: opt/site_manager/config
   - cron:       var/spool/cron/crontabs/root  etc/cron.d
   - supervisor: etc/supervisor
   - PHP/MySQL/Redis: etc/php  etc/mysql  etc/redis  root/.mysql_root_password
   - docker:     opt/**/docker-compose.yml  .env
4. 代码: 从 FTP path/wwwroot 包解到 /www/wwwroot；数据库: 从 database/mysql/<库> 最新包导入
5. MySQL 账号: mysql -uroot -p < _meta/mysql_grants.sql
6. nginx -t && systemctl reload nginx；supervisorctl reread && supervisorctl update；ufw 按 _meta/ufw_status.txt 放行
7. 改 CF DNS 到新 IP（/domain 技能 批量换 IP）
EOF

# ---------- 2. 配置文件 ----------
PATHS=(
    /etc/nginx /www/vhost /www/ssl /etc/letsencrypt
    /opt/site_manager/config
    /var/spool/cron/crontabs /etc/crontab /etc/cron.d
    /etc/supervisor
    /etc/php /etc/mysql /etc/redis
    /root/.mysql_root_password /www/server/mysql_root.pwd
    /etc/ufw /etc/ssh /root/.ssh /root/.config/rclone
    /etc/hosts /etc/hostname /etc/fstab /etc/timezone
    /etc/sysctl.conf /etc/sysctl.d /etc/security/limits.conf /etc/security/limits.d
    /etc/systemd/system /etc/logrotate.d /etc/fail2ban
    /etc/apt/sources.list /etc/apt/sources.list.d
    /etc/network/interfaces /etc/netplan
    /root/tools
)

# docker 编排：compose 文件 + .env（数据卷不在此，靠各项目自己的备份脚本）
while IFS= read -r f; do PATHS+=("$f"); done < <(
    find /opt /www/wwwroot -maxdepth 3 \( -name 'docker-compose*.y*ml' -o -name 'compose.y*ml' -o -name '.env' -o -name 'mailcow.conf' \) \
        -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null)
[ -d /opt/mailcow-dockerized/data/conf ] && PATHS+=(/opt/mailcow-dockerized/data/conf)

# /usr/local/bin 下的自写脚本（跳过软链与 >2MB 的二进制）
while IFS= read -r f; do PATHS+=("$f"); done < <(find /usr/local/bin -maxdepth 1 -type f -size -2M 2>/dev/null)

EXISTING=()
for p in "${PATHS[@]}"; do [ -e "$p" ] && EXISTING+=("${p#/}"); done

tar -czpf "$OUT" \
    --exclude='*.log' --exclude='*.log.[0-9]*' --exclude='*.gz.[0-9]*' --exclude='__pycache__' \
    -C / "${EXISTING[@]}" \
    -C "$STAGE" _meta 2>>"$LOG_FILE"
rc=$?
# tar rc=1 = 打包中文件变化，内容仍可用
if [ $rc -gt 1 ] || [ ! -s "$OUT" ]; then
    rm -f "$OUT"; log "备份失败: 服务器配置 (tar rc=$rc)"; exit 1
fi
chmod 600 "$OUT"
log "备份成功: 服务器配置 $(basename "$OUT") ($(du -h "$OUT" | cut -f1), ${#EXISTING[@]} 项)"

# ---------- 3. 本地保留 ----------
ls -1t "$DEST"/server_"${HOST}"_*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f

# ---------- 4. FTP 上传 + 远端保留 ----------
if [ "$FTP_ENABLED" = "true" ] && [ -n "$FTP_HOST" ]; then
    url="ftp://${FTP_HOST}:${FTP_PORT}${FTP_PATH}/server"
    if curl -s -T "$OUT" "$url/$(basename "$OUT")" --user "${FTP_USER}:${FTP_PASS}" --ftp-create-dirs; then
        log "FTP上传成功"
        [ "$FTP_DELETE_LOCAL" = "true" ] && rm -f "$OUT"
        old=$(curl -s --list-only "$url/" --user "${FTP_USER}:${FTP_PASS}" | grep "^server_${HOST}_" | sort | head -n -"$KEEP")
        for f in $old; do
            curl -s "ftp://${FTP_HOST}:${FTP_PORT}/" --user "${FTP_USER}:${FTP_PASS}" \
                --quote "DELE ${FTP_PATH}/server/${f}" >/dev/null 2>&1
        done
        [ -n "$old" ] && log "FTP清理: 删除 $(echo "$old" | wc -w) 份，保留 $KEEP 份"
    else
        log "FTP上传失败"; exit 1
    fi
fi
log ""
