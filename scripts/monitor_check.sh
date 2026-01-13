#!/bin/bash
#===============================================================================
# Site Manager - 监控定时任务入口
# 用于 cron 调用执行监控检查
#===============================================================================

# 加载配置
MONITOR_CONF="/opt/site_manager/config/monitor.conf"
[ -f "$MONITOR_CONF" ] && source "$MONITOR_CONF"

# 检查是否启用
if [ "$MONITOR_ENABLED" != "true" ]; then
    exit 0
fi

# 加载监控模块
source /opt/site_manager/lib/monitor.sh

# 执行所有检查
run_all_checks

exit $?
