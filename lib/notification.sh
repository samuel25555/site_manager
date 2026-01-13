#!/bin/bash
#===============================================================================
# Site Manager - 通知模块
# 支持: Telegram
#===============================================================================

# 加载配置
load_monitor_config() {
    local conf="/opt/site_manager/config/monitor.conf"
    [ -f "$conf" ] && source "$conf"
}

# 发送 Telegram 消息
notify_telegram() {
    local level="$1"    # CRITICAL / WARNING / RECOVERY / INFO
    local title="$2"
    local message="$3"

    load_monitor_config

    # 检查配置
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "Telegram 未配置" >&2
        return 1
    fi

    # 根据级别选择 emoji
    local emoji=""
    case "$level" in
        CRITICAL) emoji="🔴";;
        WARNING)  emoji="🟡";;
        RECOVERY) emoji="🟢";;
        INFO)     emoji="🔵";;
        *)        emoji="⚪";;
    esac

    # 获取主机信息
    local host_name="${MONITOR_HOST_NAME:-$(hostname)}"
    local host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 构建消息
    local text="<b>${emoji} [${level}] ${host_name}</b>

<b>${title}</b>

${message}

<i>时间: ${timestamp}</i>
<i>主机: ${host_name} (${host_ip})</i>"

    # URL 编码换行符
    text=$(echo "$text" | sed 's/\\n/%0A/g')

    # 发送消息
    local response=$(curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=${text}" 2>&1)

    if echo "$response" | grep -q '"ok":true'; then
        return 0
    else
        echo "Telegram 发送失败: $response" >&2
        return 1
    fi
}

# 发送测试消息
notify_test() {
    notify_telegram "INFO" "测试通知" "Site Manager 监控通知配置成功！"
}

# 告警去重检查
# 返回 0 表示可以发送，1 表示应该跳过
should_send_alert() {
    local alert_key="$1"
    local cooldown="${2:-3600}"  # 默认 1 小时冷却

    local state_file="/tmp/site_monitor_state.json"
    local now=$(date +%s)

    # 初始化状态文件
    if [ ! -f "$state_file" ]; then
        echo '{"last_alert":{}}' > "$state_file"
    fi

    # 读取上次告警时间
    local last_alert=$(grep -o "\"${alert_key}\":[0-9]*" "$state_file" 2>/dev/null | grep -o '[0-9]*')

    if [ -n "$last_alert" ]; then
        local elapsed=$((now - last_alert))
        if [ $elapsed -lt $cooldown ]; then
            return 1  # 冷却中，跳过
        fi
    fi

    # 更新状态
    if grep -q "\"${alert_key}\"" "$state_file" 2>/dev/null; then
        sed -i "s/\"${alert_key}\":[0-9]*/\"${alert_key}\":${now}/" "$state_file"
    else
        sed -i "s/\"last_alert\":{/\"last_alert\":{\"${alert_key}\":${now},/" "$state_file"
        # 清理多余逗号
        sed -i 's/,}/}/' "$state_file"
    fi

    return 0  # 可以发送
}

# 清除告警状态（用于恢复通知）
clear_alert_state() {
    local alert_key="$1"
    local state_file="/tmp/site_monitor_state.json"

    if [ -f "$state_file" ]; then
        sed -i "s/\"${alert_key}\":[0-9]*,*//" "$state_file"
        # 清理多余逗号和空对象
        sed -i 's/,,/,/g; s/{,/{/g; s/,}/}/g' "$state_file"
    fi
}

# 检查是否有活跃告警
has_active_alert() {
    local alert_key="$1"
    local state_file="/tmp/site_monitor_state.json"

    [ -f "$state_file" ] && grep -q "\"${alert_key}\"" "$state_file"
}
