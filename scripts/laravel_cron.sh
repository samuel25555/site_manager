#!/bin/bash
# Laravel 计划任务包装脚本
# 用法: laravel_cron.sh <命令> <日志文件>

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

CMD=$1
LOG=$2
SITE="/www/wwwroot/admin.ufa611.com"

echo "----------------------------------------------------------------------------"
startDate=$(date +"%Y-%m-%d %H:%M:%S")
echo "☆[$startDate] 开始执行 $CMD"
echo "----------------------------------------------------------------------------"

# 执行命令
php8.0 $SITE/artisan $CMD

# 完成
echo "----------------------------------------------------------------------------"
endDate=$(date +"%Y-%m-%d %H:%M:%S")
echo "★[$endDate] Successful"
echo "----------------------------------------------------------------------------"
