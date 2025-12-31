#!/bin/bash
# SSL 证书管理 - 支持多账号

CONFIG_DIR="${ROOT_DIR:-/opt/site_manager}/config"
SSL_DIR="${SSL_DIR:-/www/ssl}"
DNS_ACCOUNTS_FILE="$CONFIG_DIR/dns_accounts.json"
SSL_DOMAINS_FILE="$CONFIG_DIR/ssl_domains.json"
SSL_LOG="/www/wwwlogs/site_manager/ssl.log"

# 确保配置文件存在
_ssl_init() {
    mkdir -p "$CONFIG_DIR" "$SSL_DIR" "$(dirname "$SSL_LOG")"
    [ ! -f "$DNS_ACCOUNTS_FILE" ] && echo '{"cloudflare":[]}' > "$DNS_ACCOUNTS_FILE"
    [ ! -f "$SSL_DOMAINS_FILE" ] && echo '{}' > "$SSL_DOMAINS_FILE"
}

# 日志
ssl_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$SSL_LOG"
}

# ==================== 账号管理 ====================

# 列出所有账号
ssl_account_list() {
    _ssl_init
    echo -e "${CYAN}======== DNS API 账号列表 ========${NC}"

    local accounts=$(cat "$DNS_ACCOUNTS_FILE")
    local count=$(echo "$accounts" | jq -r '.cloudflare | length')

    if [ "$count" -eq 0 ]; then
        echo "  暂无账号，使用 site ssl account add <别名> 添加"
        return
    fi

    echo ""
    echo -e "${YELLOW}Cloudflare 账号:${NC}"
    echo "$accounts" | jq -r '.cloudflare[] | "  [\(.alias)] \(.email)"'
}

# 添加账号
ssl_account_add() {
    _ssl_init
    local alias="$1"

    if [ -z "$alias" ]; then
        echo "用法: site ssl account add <别名>"
        return 1
    fi

    # 检查别名是否已存在
    local exists=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .alias' "$DNS_ACCOUNTS_FILE")
    if [ -n "$exists" ]; then
        echo -e "${RED}账号别名已存在: $alias${NC}"
        return 1
    fi

    read -p "Cloudflare Email: " email
    read -p "Cloudflare API Key: " api_key

    if [ -z "$email" ] || [ -z "$api_key" ]; then
        echo -e "${RED}Email 和 API Key 不能为空${NC}"
        return 1
    fi

    # 生成唯一ID
    local id=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 16)

    # 添加到配置
    local tmp=$(mktemp)
    jq --arg id "$id" --arg alias "$alias" --arg email "$email" --arg key "$api_key" \
       '.cloudflare += [{"id": $id, "alias": $alias, "email": $email, "api_key": $key}]' \
       "$DNS_ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$DNS_ACCOUNTS_FILE"

    # 创建凭据文件
    local cred_file="$CONFIG_DIR/cloudflare_${alias}.ini"
    cat > "$cred_file" << EOF
dns_cloudflare_email = $email
dns_cloudflare_api_key = $api_key
EOF
    chmod 600 "$cred_file"

    echo -e "${GREEN}账号添加成功: $alias${NC}"
}

# 删除账号
ssl_account_remove() {
    _ssl_init
    local alias="$1"

    if [ -z "$alias" ]; then
        echo "用法: site ssl account remove <别名>"
        return 1
    fi

    # 检查是否存在
    local exists=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .alias' "$DNS_ACCOUNTS_FILE")
    if [ -z "$exists" ]; then
        echo -e "${RED}账号不存在: $alias${NC}"
        return 1
    fi

    # 删除配置
    local tmp=$(mktemp)
    jq --arg a "$alias" '.cloudflare = [.cloudflare[] | select(.alias != $a)]' \
       "$DNS_ACCOUNTS_FILE" > "$tmp" && mv "$tmp" "$DNS_ACCOUNTS_FILE"

    # 删除凭据文件
    rm -f "$CONFIG_DIR/cloudflare_${alias}.ini"

    echo -e "${GREEN}账号已删除: $alias${NC}"
}

# ==================== 域名绑定 ====================

# 提取根域名
_extract_root_domain() {
    local domain="$1"
    # 移除通配符
    domain="${domain#\*.}"
    # 简单提取：取最后两段
    echo "$domain" | awk -F. '{if(NF>=2) print $(NF-1)"."$NF; else print $0}'
}

# 绑定域名到账号
ssl_bind() {
    _ssl_init
    local domain="$1"
    local alias="$2"

    if [ -z "$domain" ] || [ -z "$alias" ]; then
        echo "用法: site ssl bind <根域名> <账号别名>"
        return 1
    fi

    # 检查账号是否存在
    local exists=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .alias' "$DNS_ACCOUNTS_FILE")
    if [ -z "$exists" ]; then
        echo -e "${RED}账号不存在: $alias${NC}"
        echo "使用 site ssl account list 查看可用账号"
        return 1
    fi

    # 获取账号ID
    local account_id=$(jq -r --arg a "$alias" '.cloudflare[] | select(.alias == $a) | .id' "$DNS_ACCOUNTS_FILE")

    # 更新绑定
    local tmp=$(mktemp)
    jq --arg d "$domain" --arg id "$account_id" --arg alias "$alias" \
       '. + {($d): {"account_id": $id, "alias": $alias}}' \
       "$SSL_DOMAINS_FILE" > "$tmp" && mv "$tmp" "$SSL_DOMAINS_FILE"

    echo -e "${GREEN}已绑定: $domain -> $alias${NC}"
}

# 解绑域名
ssl_unbind() {
    _ssl_init
    local domain="$1"

    if [ -z "$domain" ]; then
        echo "用法: site ssl unbind <根域名>"
        return 1
    fi

    local tmp=$(mktemp)
    jq --arg d "$domain" 'del(.[$d])' "$SSL_DOMAINS_FILE" > "$tmp" && mv "$tmp" "$SSL_DOMAINS_FILE"

    echo -e "${GREEN}已解绑: $domain${NC}"
}

# 列出绑定关系
ssl_bindlist() {
    _ssl_init
    echo -e "${CYAN}======== 域名绑定列表 ========${NC}"

    local bindings=$(cat "$SSL_DOMAINS_FILE")
    local count=$(echo "$bindings" | jq 'keys | length')

    if [ "$count" -eq 0 ]; then
        echo "  暂无绑定，使用 site ssl bind <域名> <账号别名> 添加"
        return
    fi

    echo ""
    echo "$bindings" | jq -r 'to_entries[] | "  \(.key) -> \(.value.alias)"'
}

# 获取域名对应的凭据文件
_get_credentials_for_domain() {
    local domain="$1"
    local root_domain=$(_extract_root_domain "$domain")

    # 查找绑定
    local alias=$(jq -r --arg d "$root_domain" '.[$d].alias // empty' "$SSL_DOMAINS_FILE")

    if [ -n "$alias" ]; then
        local cred_file="$CONFIG_DIR/cloudflare_${alias}.ini"
        if [ -f "$cred_file" ]; then
            echo "$cred_file"
            return 0
        fi
    fi

    # 回退到默认配置
    local default_cred="$CONFIG_DIR/cloudflare.ini"
    if [ -f "$default_cred" ]; then
        echo "$default_cred"
        return 0
    fi

    return 1
}

# ==================== 证书申请 ====================

# 安装 certbot
ssl_install() {
    check_root

    if command_exists certbot; then
        log_info "certbot 已安装"
        return 0
    fi

    log_info "安装 certbot..."
    apt-get update -qq
    apt-get install -y -qq certbot python3-certbot-nginx python3-certbot-dns-cloudflare jq > /dev/null 2>&1

    if command_exists certbot; then
        log_success "certbot 安装成功"
    else
        log_error "certbot 安装失败"
        return 1
    fi
}

# 配置默认 Cloudflare DNS API（兼容旧版）
ssl_dns_config() {
    check_root

    local email="$1"
    local api_key="$2"

    if [ -z "$email" ] || [ -z "$api_key" ]; then
        echo "配置默认 Cloudflare DNS API"
        read -p "Email: " email
        read -p "API Key: " api_key
    fi

    if [ -z "$email" ] || [ -z "$api_key" ]; then
        log_error "Email 和 API Key 不能为空"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/cloudflare.ini" << EOF
dns_cloudflare_email = $email
dns_cloudflare_api_key = $api_key
EOF
    chmod 600 "$CONFIG_DIR/cloudflare.ini"

    log_success "默认 Cloudflare DNS 配置已保存"
}

# 申请 SSL 证书（支持多域名）
ssl_request() {
    local domains_input="$1"
    shift

    check_root
    _ssl_init

    if [ -z "$domains_input" ]; then
        log_error "用法: site ssl <域名> [--dns] [--wildcard]"
        log_info "多域名: site ssl \"a.com,b.com\" --dns"
        return 1
    fi

    # 检查 certbot
    if ! command_exists certbot; then
        log_warn "certbot 未安装，正在安装..."
        ssl_install || return 1
    fi

    local use_dns=false
    local wildcard=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dns) use_dns=true ;;
            --wildcard) wildcard=true; use_dns=true ;;
        esac
        shift
    done

    # 解析域名列表
    IFS=',' read -ra domains <<< "$domains_input"
    local primary_domain="${domains[0]}"

    log_info "申请 SSL 证书: ${domains[*]}"
    ssl_log "申请证书: ${domains[*]}"

    mkdir -p "$SSL_DIR/$primary_domain"

    if [ "$use_dns" = "true" ]; then
        # DNS 验证
        local domain_args=""
        local cred_file=""
        local all_same_account=true
        local first_cred=""

        for domain in "${domains[@]}"; do
            domain=$(echo "$domain" | xargs)  # trim
            [ -z "$domain" ] && continue

            local cred=$(_get_credentials_for_domain "$domain")
            if [ -z "$cred" ]; then
                log_error "域名 $domain 未绑定 DNS 账号，且无默认配置"
                log_info "请先运行: site ssl bind $(_extract_root_domain "$domain") <账号别名>"
                return 1
            fi

            # 检查是否所有域名使用同一账号
            if [ -z "$first_cred" ]; then
                first_cred="$cred"
            elif [ "$cred" != "$first_cred" ]; then
                all_same_account=false
            fi

            domain_args="$domain_args -d $domain"
            [ "$wildcard" = "true" ] && domain_args="$domain_args -d *.$domain"
        done

        if [ "$all_same_account" = "false" ]; then
            # 多账号情况：使用 manual 模式 + 自定义 hook，合并到一张证书
            log_warn "检测到多个 DNS 账号，使用自定义 Hook 合并申请"
            ssl_log "多账号模式: 使用 manual hook 申请"

            local auth_hook="/opt/site_manager/scripts/certbot_cf_auth.sh"
            local cleanup_hook="/opt/site_manager/scripts/certbot_cf_cleanup.sh"

            # 清理之前的临时文件
            rm -f /tmp/certbot_cf_cleanup /tmp/certbot_cf_records_*

            # 获取第一个账号的邮箱用于注册
            local first_alias=$(jq -r --arg d "$(_extract_root_domain "${domains[0]}")" '.[$d].alias // empty' "$SSL_DOMAINS_FILE")
            local reg_email=$(jq -r --arg a "$first_alias" '.cloudflare[] | select(.alias == $a) | .email' "$DNS_ACCOUNTS_FILE" 2>/dev/null)
            [ -z "$reg_email" ] && reg_email="admin@${domains[0]}"

            certbot certonly \
                --manual \
                --preferred-challenges dns \
                --manual-auth-hook "$auth_hook" \
                --manual-cleanup-hook "$cleanup_hook" \
                $domain_args \
                --non-interactive --agree-tos --email "$reg_email" \
                --cert-name "$primary_domain"
        else
            # 单账号：一次申请所有域名
            local cf_email=$(grep "dns_cloudflare_email" "$first_cred" | cut -d'=' -f2 | tr -d ' ')

            ssl_log "使用单账号申请所有域名"
            certbot certonly \
                --dns-cloudflare \
                --dns-cloudflare-credentials "$first_cred" \
                --dns-cloudflare-propagation-seconds 30 \
                $domain_args \
                --non-interactive --agree-tos --email "$cf_email" \
                --cert-name "$primary_domain"
        fi
    else
        # HTTP 验证
        if ! site_exists "$primary_domain"; then
            log_error "站点 $primary_domain 不存在，HTTP 验证需要先创建站点"
            log_info "或使用 --dns 参数进行 DNS 验证"
            return 1
        fi

        local domain_args=""
        for domain in "${domains[@]}"; do
            domain=$(echo "$domain" | xargs)
            [ -n "$domain" ] && domain_args="$domain_args -d $domain"
        done

        certbot --nginx $domain_args --non-interactive --agree-tos --email "${ADMIN_EMAIL:-admin@$primary_domain}"
    fi

    if [ $? -eq 0 ]; then
        # 复制证书
        if [ -d "/etc/letsencrypt/live/$primary_domain" ]; then
            cp "/etc/letsencrypt/live/$primary_domain/fullchain.pem" "$SSL_DIR/$primary_domain/"
            cp "/etc/letsencrypt/live/$primary_domain/privkey.pem" "$SSL_DIR/$primary_domain/"
            chmod 644 "$SSL_DIR/$primary_domain/fullchain.pem"
            chmod 600 "$SSL_DIR/$primary_domain/privkey.pem"
        fi

        log_success "SSL 证书申请成功"
        ssl_log "证书申请成功: ${domains[*]}"
        log_info "证书路径: $SSL_DIR/$primary_domain/"
        nginx_reload 2>/dev/null
    else
        log_error "SSL 证书申请失败"
        ssl_log "证书申请失败: ${domains[*]}"
        return 1
    fi
}

# ==================== 证书续期 ====================

# 获取证书剩余天数
_get_cert_days_left() {
    local cert_path="$1"
    if [ ! -f "$cert_path" ]; then
        echo "-1"
        return
    fi

    local expiry=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
    if [ -z "$expiry" ]; then
        echo "-1"
        return
    fi

    local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null)
    local now_ts=$(date +%s)
    local days_left=$(( (expiry_ts - now_ts) / 86400 ))
    echo "$days_left"
}

# 智能续期所有证书
ssl_renew() {
    check_root
    _ssl_init

    ssl_log "----------------------------------------------------------------------------"
    ssl_log "☆ 开始执行: SSL 证书续期检查"
    ssl_log "----------------------------------------------------------------------------"

    local renewed=0
    local skipped=0
    local failed=0

    # 遍历所有证书
    for cert_dir in /etc/letsencrypt/live/*/; do
        [ -d "$cert_dir" ] || continue

        local domain=$(basename "$cert_dir")
        [ "$domain" = "README" ] && continue

        local cert_file="$cert_dir/fullchain.pem"
        local days_left=$(_get_cert_days_left "$cert_file")

        if [ "$days_left" -lt 0 ]; then
            ssl_log "跳过 $domain: 无法读取证书"
            ((skipped++))
            continue
        fi

        if [ "$days_left" -gt 30 ]; then
            ssl_log "跳过 $domain: 剩余 $days_left 天 (>30天)"
            ((skipped++))
            continue
        fi

        ssl_log "续期 $domain: 剩余 $days_left 天"

        # 获取证书域名列表
        local cert_domains=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | \
            grep -A1 "Subject Alternative Name" | tail -1 | \
            sed 's/DNS://g' | tr ',' '\n' | xargs)

        # 检查是否有通配符
        local has_wildcard=false
        echo "$cert_domains" | grep -q '\*\.' && has_wildcard=true

        if [ "$has_wildcard" = "true" ]; then
            # DNS 验证续期
            local root_domain=$(_extract_root_domain "$domain")
            local cred=$(_get_credentials_for_domain "$domain")

            if [ -z "$cred" ]; then
                ssl_log "失败 $domain: 未找到 DNS 凭据"
                ((failed++))
                continue
            fi

            if certbot renew --cert-name "$domain" \
                --dns-cloudflare \
                --dns-cloudflare-credentials "$cred" \
                --dns-cloudflare-propagation-seconds 30 \
                --non-interactive 2>&1 | tee -a "$SSL_LOG"; then
                ssl_log "成功续期: $domain"
                ((renewed++))
            else
                ssl_log "续期失败: $domain"
                ((failed++))
            fi
        else
            # HTTP 验证续期
            if certbot renew --cert-name "$domain" --non-interactive 2>&1 | tee -a "$SSL_LOG"; then
                ssl_log "成功续期: $domain"
                ((renewed++))
            else
                ssl_log "续期失败: $domain"
                ((failed++))
            fi
        fi

        # 更新本地证书副本
        if [ -d "$SSL_DIR/$domain" ] && [ -f "$cert_dir/fullchain.pem" ]; then
            cp "$cert_dir/fullchain.pem" "$SSL_DIR/$domain/"
            cp "$cert_dir/privkey.pem" "$SSL_DIR/$domain/"
        fi
    done

    ssl_log "----------------------------------------------------------------------------"
    ssl_log "★ 续期完成: 成功 $renewed, 跳过 $skipped, 失败 $failed"
    ssl_log "----------------------------------------------------------------------------"
    ssl_log ""

    [ "$renewed" -gt 0 ] && nginx_reload 2>/dev/null

    log_success "续期检查完成: 成功 $renewed, 跳过 $skipped, 失败 $failed"
}

# 列出所有证书状态
ssl_list() {
    _ssl_init
    echo -e "${CYAN}======== SSL 证书列表 ========${NC}"
    echo ""

    printf "%-30s %-12s %-20s\n" "域名" "剩余天数" "状态"
    printf "%-30s %-12s %-20s\n" "------------------------------" "------------" "--------------------"

    for cert_dir in /etc/letsencrypt/live/*/; do
        [ -d "$cert_dir" ] || continue

        local domain=$(basename "$cert_dir")
        [ "$domain" = "README" ] && continue

        local cert_file="$cert_dir/fullchain.pem"
        local days_left=$(_get_cert_days_left "$cert_file")

        local status=""
        local color=""
        if [ "$days_left" -lt 0 ]; then
            status="无法读取"
            color="$RED"
        elif [ "$days_left" -le 7 ]; then
            status="即将过期!"
            color="$RED"
        elif [ "$days_left" -le 30 ]; then
            status="需要续期"
            color="$YELLOW"
        else
            status="正常"
            color="$GREEN"
        fi

        printf "%-30s ${color}%-12s${NC} %-20s\n" "$domain" "$days_left 天" "$status"
    done
}
