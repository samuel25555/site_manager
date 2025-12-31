#!/bin/bash
# Certbot Cloudflare DNS 验证 Hook - 添加 TXT 记录
# 根据域名自动选择对应的 Cloudflare 账号

CONFIG_DIR="/opt/site_manager/config"
SSL_DOMAINS_FILE="$CONFIG_DIR/ssl_domains.json"
DNS_ACCOUNTS_FILE="$CONFIG_DIR/dns_accounts.json"
LOG_FILE="/www/wwwlogs/site_manager/ssl.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTH] $1" >> "$LOG_FILE"
}

# 提取根域名
extract_root_domain() {
    local domain="$1"
    domain="${domain#\*.}"
    echo "$domain" | awk -F. '{if(NF>=2) print $(NF-1)"."$NF; else print $0}'
}

# 获取域名对应的 Cloudflare 凭据
get_credentials() {
    local domain="$1"
    local root_domain=$(extract_root_domain "$domain")

    # 查找绑定的账号别名
    local alias=$(jq -r --arg d "$root_domain" '.[$d].alias // empty' "$SSL_DOMAINS_FILE" 2>/dev/null)

    if [ -n "$alias" ]; then
        # 从账号配置获取凭据
        CF_EMAIL=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .email' "$DNS_ACCOUNTS_FILE" 2>/dev/null)
        CF_KEY=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .api_key' "$DNS_ACCOUNTS_FILE" 2>/dev/null)
        log "域名 $domain (根域名: $root_domain) 使用账号: $alias"
    else
        # 尝试默认配置
        local default_cred="$CONFIG_DIR/cloudflare.ini"
        if [ -f "$default_cred" ]; then
            CF_EMAIL=$(grep "dns_cloudflare_email" "$default_cred" | cut -d'=' -f2 | tr -d ' ')
            CF_KEY=$(grep "dns_cloudflare_api_key" "$default_cred" | cut -d'=' -f2 | tr -d ' ')
            log "域名 $domain 使用默认账号"
        else
            log "错误: 域名 $domain 未绑定账号且无默认配置"
            exit 1
        fi
    fi
}

# 获取 Zone ID
get_zone_id() {
    local root_domain="$1"

    local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$root_domain" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_KEY" \
        -H "Content-Type: application/json")

    local zone_id=$(echo "$response" | jq -r '.result[0].id // empty')

    if [ -z "$zone_id" ] || [ "$zone_id" = "null" ]; then
        log "错误: 无法获取 $root_domain 的 Zone ID"
        log "响应: $response"
        exit 1
    fi

    echo "$zone_id"
}

# 添加 TXT 记录
add_txt_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_value="$3"

    local response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_KEY" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"TXT\",\"name\":\"$record_name\",\"content\":\"$record_value\",\"ttl\":120}")

    local success=$(echo "$response" | jq -r '.success')
    local record_id=$(echo "$response" | jq -r '.result.id // empty')

    if [ "$success" = "true" ] && [ -n "$record_id" ]; then
        log "添加 TXT 记录成功: $record_name = $record_value (ID: $record_id)"
        # 保存记录 ID 供清理时使用
        echo "$record_id" >> "/tmp/certbot_cf_records_$$"
        echo "$zone_id:$record_id" >> "/tmp/certbot_cf_cleanup"
    else
        log "添加 TXT 记录失败: $response"
        exit 1
    fi
}

# 主逻辑
main() {
    log "开始验证域名: $CERTBOT_DOMAIN"
    log "验证内容: $CERTBOT_VALIDATION"

    # 获取凭据
    get_credentials "$CERTBOT_DOMAIN"

    # 提取根域名
    local root_domain=$(extract_root_domain "$CERTBOT_DOMAIN")

    # 获取 Zone ID
    local zone_id=$(get_zone_id "$root_domain")
    log "Zone ID: $zone_id"

    # 构建记录名
    local record_name="_acme-challenge.$CERTBOT_DOMAIN"

    # 添加 TXT 记录
    add_txt_record "$zone_id" "$record_name" "$CERTBOT_VALIDATION"

    # 等待 DNS 传播
    log "等待 DNS 传播 (30秒)..."
    sleep 30
}

main
