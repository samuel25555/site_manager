#!/bin/bash
# 通用计划任务包装脚本
# 用法: cron_wrapper.sh <命令> [日志文件]
#
# 不指定日志文件时自动生成，规则:
#   1. 从命令中提取 /www/wwwroot/{站点}/ 的站点名
#   2. 如果有 artisan 命令，追加命令名
#   3. 日志保存到 /www/wwwlogs/cron/{名称}.log

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

CMD="$1"
LOG="$2"

[ -z "$CMD" ] && { echo "用法: $0 <命令> [日志文件]"; exit 1; }

# 自动生成日志路径
if [ -z "$LOG" ]; then
    CRON_LOG_DIR="/www/wwwlogs/cron"
    mkdir -p "$CRON_LOG_DIR"

    # 尝试从命令中提取站点名 (匹配 /www/wwwroot/xxx/)
    site_name=$(echo "$CMD" | grep -oP '/www/wwwroot/\K[^/]+' | head -1)

    # 尝试提取 artisan 命令名
    artisan_cmd=$(echo "$CMD" | grep -oP 'artisan\s+\K[^\s]+' | head -1 | tr ':' '_')

    if [ -n "$site_name" ]; then
        if [ -n "$artisan_cmd" ]; then
            log_name="${site_name}_${artisan_cmd}"
        else
            log_name="$site_name"
        fi
    elif [ -n "$artisan_cmd" ]; then
        log_name="artisan_${artisan_cmd}"
    else
        # 用命令的 md5 作为日志名
        log_name=$(echo "$CMD" | md5sum | cut -c1-8)
    fi

    LOG="${CRON_LOG_DIR}/${log_name}.log"
fi

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
