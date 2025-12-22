#!/bin/bash
# 通用计划任务包装脚本
# 用法: cron_wrapper.sh <命令> [日志文件]
#
# 示例:
#   cron_wrapper.sh "/opt/site_manager/bin/backup_cron.sh db"
#   cron_wrapper.sh "php /www/wwwroot/xxx/artisan schedule:run" "/www/wwwlogs/laravel.log"

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

CMD="$1"
LOG="${2:-/www/wwwlogs/site_manager/cron.log}"

[ -z "$CMD" ] && { echo "用法: $0 <命令> [日志文件]"; exit 1; }

# 确保日志目录存在
mkdir -p "$(dirname "$LOG")"

{
    echo "----------------------------------------------------------------------------"
    echo "☆ [$(date '+%Y-%m-%d %H:%M:%S')] 开始执行: $CMD"
    echo "----------------------------------------------------------------------------"

    # 执行命令并记录退出码
    eval $CMD
    exit_code=$?

    echo "----------------------------------------------------------------------------"
    if [ $exit_code -eq 0 ]; then
        echo "★ [$(date '+%Y-%m-%d %H:%M:%S')] 执行成功"
    else
        echo "✗ [$(date '+%Y-%m-%d %H:%M:%S')] 执行失败 (退出码: $exit_code)"
    fi
    echo "----------------------------------------------------------------------------"
    echo ""
} >> "$LOG" 2>&1
