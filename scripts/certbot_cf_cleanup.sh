#!/bin/bash
# Certbot Cloudflare DNS 验证 Hook - 清理 TXT 记录

CONFIG_DIR="/opt/site_manager/config"
SSL_DOMAINS_FILE="$CONFIG_DIR/ssl_domains.json"
DNS_ACCOUNTS_FILE="$CONFIG_DIR/dns_accounts.json"
LOG_FILE="/www/wwwlogs/site_manager/ssl.log"
CLEANUP_FILE="/tmp/certbot_cf_cleanup"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CLEANUP] $1" >> "$LOG_FILE"
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

    local alias=$(jq -r --arg d "$root_domain" '.[$d].alias // empty' "$SSL_DOMAINS_FILE" 2>/dev/null)

    if [ -n "$alias" ]; then
        CF_EMAIL=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .email' "$DNS_ACCOUNTS_FILE" 2>/dev/null)
        CF_KEY=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .api_key' "$DNS_ACCOUNTS_FILE" 2>/dev/null)
    else
        local default_cred="$CONFIG_DIR/cloudflare.ini"
        if [ -f "$default_cred" ]; then
            CF_EMAIL=$(grep "dns_cloudflare_email" "$default_cred" | cut -d'=' -f2 | tr -d ' ')
            CF_KEY=$(grep "dns_cloudflare_api_key" "$default_cred" | cut -d'=' -f2 | tr -d ' ')
        fi
    fi
}

# 删除 TXT 记录
delete_txt_record() {
    local zone_id="$1"
    local record_id="$2"

    local response=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_KEY" \
        -H "Content-Type: application/json")

    local success=$(echo "$response" | jq -r '.success')

    if [ "$success" = "true" ]; then
        log "删除 TXT 记录成功: $record_id"
    else
        log "删除 TXT 记录失败: $response"
    fi
}

# 主逻辑
main() {
    log "清理域名验证记录: $CERTBOT_DOMAIN"

    # 获取凭据
    get_credentials "$CERTBOT_DOMAIN"

    # 从清理文件读取记录并删除
    if [ -f "$CLEANUP_FILE" ]; then
        while IFS=':' read -r zone_id record_id; do
            [ -n "$zone_id" ] && [ -n "$record_id" ] && delete_txt_record "$zone_id" "$record_id"
        done < "$CLEANUP_FILE"
    fi
}

main

# 如果是最后一个域名，清理临时文件
if [ "$CERTBOT_REMAINING_CHALLENGES" = "0" ]; then
    rm -f "$CLEANUP_FILE" /tmp/certbot_cf_records_*
    log "清理完成，已删除临时文件"
fi
