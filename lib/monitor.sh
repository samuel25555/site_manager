#!/bin/bash
#===============================================================================
# Site Manager - 监控模块
# 检查项: 网站/SSL/磁盘/服务/Supervisor/备份
#===============================================================================

# 加载依赖
source /opt/site_manager/lib/notification.sh 2>/dev/null

# 加载配置
MONITOR_CONF="/opt/site_manager/config/monitor.conf"
[ -f "$MONITOR_CONF" ] && source "$MONITOR_CONF"

# 默认值
DISK_WARN_PERCENT="${DISK_WARN_PERCENT:-80}"
DISK_CRIT_PERCENT="${DISK_CRIT_PERCENT:-90}"
SSL_WARN_DAYS="${SSL_WARN_DAYS:-14}"
SSL_CRIT_DAYS="${SSL_CRIT_DAYS:-7}"
BACKUP_MAX_AGE="${BACKUP_MAX_AGE:-24}"  # 小时

# 日志文件
MONITOR_LOG="/www/wwwlogs/site_manager/monitor.log"
mkdir -p "$(dirname "$MONITOR_LOG")" 2>/dev/null

# 写日志
monitor_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$MONITOR_LOG"
}

#---------------------------------------
# 检查网站可访问性
#---------------------------------------
check_websites() {
    [ "$CHECK_WEBSITES" != "true" ] && return 0

    local nginx_conf_dir="/www/vhost/nginx"
    local issues=0

    [ ! -d "$nginx_conf_dir" ] && return 0

    for conf in "$nginx_conf_dir"/*; do
        [ ! -f "$conf" ] && continue

        local domain=$(basename "$conf")
        [[ "$domain" == *.conf ]] && domain="${domain%.conf}"

        # 检查是否启用 SSL
        local url="http://${domain}"
        if grep -q "listen.*443" "$conf" 2>/dev/null; then
            url="https://${domain}"
        fi

        # 发送请求
        local status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 -m 15 "$url" 2>/dev/null)

        if [ "$status" != "200" ] && [ "$status" != "301" ] && [ "$status" != "302" ]; then
            local alert_key="website_${domain}"
            if should_send_alert "$alert_key" 3600; then
                notify_telegram "CRITICAL" "网站不可访问" "域名: ${domain}
HTTP 状态码: ${status}
URL: ${url}

建议: 检查 Nginx 和 PHP-FPM 状态"
                monitor_log "CRITICAL: 网站 $domain 不可访问 (HTTP $status)"
                issues=$((issues + 1))
            fi
        else
            # 恢复检查
            if has_active_alert "website_${domain}"; then
                clear_alert_state "website_${domain}"
                notify_telegram "RECOVERY" "网站已恢复" "域名: ${domain}
状态: 正常 (HTTP ${status})"
                monitor_log "RECOVERY: 网站 $domain 已恢复"
            fi
        fi
    done

    return $issues
}

#---------------------------------------
# 检查 SSL 证书
#---------------------------------------
check_ssl() {
    [ "$CHECK_SSL" != "true" ] && return 0

    local ssl_dir="/www/ssl"
    local issues=0

    [ ! -d "$ssl_dir" ] && return 0

    for cert_dir in "$ssl_dir"/*/; do
        [ ! -d "$cert_dir" ] && continue

        local cert_file="${cert_dir}fullchain.pem"
        [ ! -f "$cert_file" ] && continue

        local domain=$(basename "$cert_dir")
        local end_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local end_epoch=$(date -d "$end_date" +%s 2>/dev/null)
        local now_epoch=$(date +%s)
        local days_left=$(( (end_epoch - now_epoch) / 86400 ))

        local alert_key="ssl_${domain}"

        if [ "$days_left" -lt "$SSL_CRIT_DAYS" ]; then
            if should_send_alert "$alert_key" 3600; then
                notify_telegram "CRITICAL" "SSL 证书即将过期" "域名: ${domain}
剩余天数: ${days_left} 天
过期时间: ${end_date}

建议: site ssl renew 或 site ssl ${domain} --dns"
                monitor_log "CRITICAL: SSL 证书 $domain 将在 $days_left 天后过期"
                issues=$((issues + 1))
            fi
        elif [ "$days_left" -lt "$SSL_WARN_DAYS" ]; then
            if should_send_alert "$alert_key" 86400; then  # 24 小时冷却
                notify_telegram "WARNING" "SSL 证书过期提醒" "域名: ${domain}
剩余天数: ${days_left} 天
过期时间: ${end_date}

建议: 尽快续期证书"
                monitor_log "WARNING: SSL 证书 $domain 将在 $days_left 天后过期"
            fi
        fi
    done

    return $issues
}

#---------------------------------------
# 检查磁盘空间
#---------------------------------------
check_disk() {
    [ "$CHECK_DISK" != "true" ] && return 0

    local issues=0
    local usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    local available=$(df -h / | tail -1 | awk '{print $4}')

    local alert_key="disk_root"

    if [ "$usage" -ge "$DISK_CRIT_PERCENT" ]; then
        if should_send_alert "$alert_key" 1800; then  # 30 分钟冷却
            notify_telegram "CRITICAL" "磁盘空间严重不足" "使用率: ${usage}%
剩余空间: ${available}
阈值: ${DISK_CRIT_PERCENT}%

建议: 立即清理日志或扩容磁盘"
            monitor_log "CRITICAL: 磁盘使用率 ${usage}%"
            issues=$((issues + 1))
        fi
    elif [ "$usage" -ge "$DISK_WARN_PERCENT" ]; then
        if should_send_alert "$alert_key" 3600; then
            notify_telegram "WARNING" "磁盘空间告警" "使用率: ${usage}%
剩余空间: ${available}
阈值: ${DISK_WARN_PERCENT}%

建议: 清理不必要的文件"
            monitor_log "WARNING: 磁盘使用率 ${usage}%"
        fi
    else
        if has_active_alert "$alert_key"; then
            clear_alert_state "$alert_key"
            notify_telegram "RECOVERY" "磁盘空间恢复" "使用率: ${usage}%
剩余空间: ${available}"
            monitor_log "RECOVERY: 磁盘使用率恢复正常 ${usage}%"
        fi
    fi

    return $issues
}

#---------------------------------------
# 检查服务状态
#---------------------------------------
check_services() {
    [ "$CHECK_SERVICES" != "true" ] && return 0

    local issues=0
    local services=("nginx" "mysql" "mariadb" "redis-server")

    for service in "${services[@]}"; do
        # 跳过未安装的服务
        if ! systemctl list-unit-files 2>/dev/null | grep -q "^${service}"; then
            continue
        fi

        local alert_key="service_${service}"

        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            if should_send_alert "$alert_key" 300; then  # 5 分钟冷却
                notify_telegram "CRITICAL" "服务异常" "服务: ${service}
状态: 未运行

建议: systemctl start ${service}"
                monitor_log "CRITICAL: 服务 $service 未运行"
                issues=$((issues + 1))
            fi
        else
            if has_active_alert "$alert_key"; then
                clear_alert_state "$alert_key"
                notify_telegram "RECOVERY" "服务已恢复" "服务: ${service}
状态: 运行中"
                monitor_log "RECOVERY: 服务 $service 已恢复"
            fi
        fi
    done

    # PHP-FPM 检查
    for version in 7.4 8.0 8.1 8.2 8.3; do
        local service="php${version}-fpm"
        if systemctl list-unit-files 2>/dev/null | grep -q "^${service}"; then
            local alert_key="service_php${version}"
            if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                if should_send_alert "$alert_key" 300; then
                    notify_telegram "CRITICAL" "PHP-FPM 异常" "服务: PHP ${version} FPM
状态: 未运行

建议: systemctl start ${service}"
                    monitor_log "CRITICAL: PHP ${version} FPM 未运行"
                    issues=$((issues + 1))
                fi
            else
                if has_active_alert "$alert_key"; then
                    clear_alert_state "$alert_key"
                    notify_telegram "RECOVERY" "PHP-FPM 已恢复" "服务: PHP ${version} FPM
状态: 运行中"
                    monitor_log "RECOVERY: PHP ${version} FPM 已恢复"
                fi
            fi
        fi
    done

    return $issues
}

#---------------------------------------
# 检查 Supervisor 进程
#---------------------------------------
check_supervisor() {
    [ "$CHECK_SUPERVISOR" != "true" ] && return 0

    command -v supervisorctl &>/dev/null || return 0

    local issues=0
    local status_output=$(supervisorctl status 2>/dev/null)

    [ -z "$status_output" ] && return 0

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        local process=$(echo "$line" | awk '{print $1}')
        local state=$(echo "$line" | awk '{print $2}')

        [ -z "$process" ] && continue

        local alert_key="supervisor_${process}"

        if [ "$state" != "RUNNING" ]; then
            if should_send_alert "$alert_key" 600; then  # 10 分钟冷却
                notify_telegram "WARNING" "Supervisor 进程异常" "进程: ${process}
状态: ${state}

建议: supervisorctl restart ${process}"
                monitor_log "WARNING: Supervisor 进程 $process 状态 $state"
                issues=$((issues + 1))
            fi
        else
            if has_active_alert "$alert_key"; then
                clear_alert_state "$alert_key"
                notify_telegram "RECOVERY" "Supervisor 进程恢复" "进程: ${process}
状态: RUNNING"
                monitor_log "RECOVERY: Supervisor 进程 $process 已恢复"
            fi
        fi
    done <<< "$status_output"

    return $issues
}

#---------------------------------------
# 检查备份状态
#---------------------------------------
check_backup() {
    [ "$CHECK_BACKUP" != "true" ] && return 0

    local backup_dir="/www/backup"
    local issues=0
    local max_age_seconds=$((BACKUP_MAX_AGE * 3600))
    local now=$(date +%s)

    # 检查数据库备份
    local db_backup_dir="${backup_dir}/database"
    if [ -d "$db_backup_dir" ]; then
        local latest_db=$(find "$db_backup_dir" -name "*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1)
        if [ -n "$latest_db" ]; then
            local file_time=$(echo "$latest_db" | cut -d' ' -f1 | cut -d'.' -f1)
            local age=$((now - file_time))

            local alert_key="backup_database"
            if [ $age -gt $max_age_seconds ]; then
                local hours_ago=$((age / 3600))
                if should_send_alert "$alert_key" 7200; then  # 2 小时冷却
                    notify_telegram "WARNING" "数据库备份过期" "最近备份: ${hours_ago} 小时前
阈值: ${BACKUP_MAX_AGE} 小时

建议: 检查备份任务 site cron list"
                    monitor_log "WARNING: 数据库备份已超过 ${hours_ago} 小时"
                    issues=$((issues + 1))
                fi
            fi
        fi
    fi

    return $issues
}

#---------------------------------------
# 执行所有检查
#---------------------------------------
run_all_checks() {
    local total_issues=0

    monitor_log "开始执行监控检查"

    check_websites
    total_issues=$((total_issues + $?))

    check_ssl
    total_issues=$((total_issues + $?))

    check_disk
    total_issues=$((total_issues + $?))

    check_services
    total_issues=$((total_issues + $?))

    check_supervisor
    total_issues=$((total_issues + $?))

    check_backup
    total_issues=$((total_issues + $?))

    if [ $total_issues -eq 0 ]; then
        monitor_log "检查完成，无异常"
    else
        monitor_log "检查完成，发现 $total_issues 个问题"
    fi

    return $total_issues
}

#---------------------------------------
# 显示监控状态
#---------------------------------------
show_monitor_status() {
    echo ""
    echo -e "\033[0;36m======== 监控状态 ========\033[0m"
    echo ""

    # 配置状态
    echo -n "监控状态: "
    if [ "$MONITOR_ENABLED" = "true" ]; then
        echo -e "\033[0;32m已启用\033[0m"
    else
        echo -e "\033[0;31m未启用\033[0m"
    fi

    echo -n "检查间隔: "
    echo "${MONITOR_INTERVAL:-5} 分钟"

    echo ""
    echo "Telegram 配置:"
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        echo -e "  状态: \033[0;32m已配置\033[0m"
        echo "  Chat ID: ${TG_CHAT_ID}"
    else
        echo -e "  状态: \033[0;31m未配置\033[0m"
    fi

    echo ""
    echo "监控项:"
    echo "  网站检查: ${CHECK_WEBSITES:-true}"
    echo "  SSL 检查: ${CHECK_SSL:-true}"
    echo "  磁盘检查: ${CHECK_DISK:-true}"
    echo "  服务检查: ${CHECK_SERVICES:-true}"
    echo "  Supervisor: ${CHECK_SUPERVISOR:-true}"
    echo "  备份检查: ${CHECK_BACKUP:-true}"

    echo ""
    echo "阈值设置:"
    echo "  磁盘警告: ${DISK_WARN_PERCENT:-80}%"
    echo "  磁盘危险: ${DISK_CRIT_PERCENT:-90}%"
    echo "  SSL 警告: ${SSL_WARN_DAYS:-14} 天"
    echo "  SSL 危险: ${SSL_CRIT_DAYS:-7} 天"

    # 定时任务状态
    echo ""
    echo -n "定时任务: "
    if crontab -l 2>/dev/null | grep -q "monitor_check.sh"; then
        echo -e "\033[0;32m运行中\033[0m"
    else
        echo -e "\033[0;33m未启动\033[0m"
    fi

    echo ""
}
