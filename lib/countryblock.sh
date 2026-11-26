#!/bin/bash
# Site Manager —— 全站国家访问控制（country-block）
#
# 在 nginx http 级生成 allow/deny（/etc/nginx/conf.d/00-country-block.conf），
# 对现有和以后新建的所有站点生效，不受后台「访问地区控制」影响。
# 数据源：五大 RIR 官方 delegated 文件（lib/country_block.py 负责下载/汇总）。
#
# 用法:
#   site country-block                 # 状态
#   site country-block status
#   site country-block on|off
#   site country-block set <CC>...     # 直接设定拦截国家列表
#   site country-block add <CC>...     # 追加
#   site country-block remove <CC>...  # 移除
#   site country-block allow <IP/CIDR> # 白名单（在 deny 之前放行）
#   site country-block unallow <IP/CIDR>
#   site country-block update          # 重新拉取 RIR 数据并生效
#   site country-block cron on|off     # 每日检查更新（缓存 7 天，/etc/cron.d/site-country-block）

CB_CONF="/opt/site_manager/config/country_block.conf"
CB_TEMPLATE="/opt/site_manager/config/country_block.conf.template"
CB_PY="/opt/site_manager/lib/country_block.py"
CB_STATE="/opt/site_manager/data/country-block"
CB_LOG="/var/log/country-block.log"
CB_CRON="/etc/cron.d/site-country-block"
CB_DEFAULT_OUT="/etc/nginx/conf.d/00-country-block.conf"

cb_ensure_conf() {
    local old_out="$1"
    if [ ! -f "$CB_CONF" ]; then
        mkdir -p "$(dirname "$CB_CONF")"
        if [ -f "$CB_TEMPLATE" ]; then
            cp "$CB_TEMPLATE" "$CB_CONF"
        else
            cat > "$CB_CONF" <<'EOF'
# Site Manager —— 全站国家访问控制配置（由 site country-block 维护）
CB_ENABLED=1
CB_MODE="block"
CB_COUNTRIES="CN"
CB_ALLOW_IPS=""
CB_OUT="/etc/nginx/conf.d/00-country-block.conf"
EOF
        fi
        chmod 644 "$CB_CONF"
    fi
    # shellcheck disable=SC1090
    source "$CB_CONF"
    CB_ENABLED="${CB_ENABLED:-1}"
    CB_MODE="${CB_MODE:-block}"
    CB_COUNTRIES="${CB_COUNTRIES:-CN}"
    CB_ALLOW_IPS="${CB_ALLOW_IPS:-}"
    CB_OUT="${CB_OUT:-$CB_DEFAULT_OUT}"
}

cb_save_conf() {
    cat > "$CB_CONF" <<EOF
# Site Manager —— 全站国家访问控制配置（由 site country-block 维护）
# 生成文件: $CB_OUT
CB_ENABLED=$CB_ENABLED
CB_MODE="$CB_MODE"
CB_COUNTRIES="$CB_COUNTRIES"
CB_ALLOW_IPS="$CB_ALLOW_IPS"
CB_OUT="$CB_OUT"
EOF
    chmod 644 "$CB_CONF"
}

cb_join() { echo "$*" | tr ' ' ','; }

cb_apply() {
    cb_ensure_conf
    if [ "$CB_ENABLED" != "1" ]; then
        python3 "$CB_PY" --off --out "$CB_OUT" --state "$CB_STATE" --log "$CB_LOG"
        return $?
    fi
    python3 "$CB_PY" \
        --out "$CB_OUT" --state "$CB_STATE" \
        --mode "$CB_MODE" \
        --countries "$(cb_join $CB_COUNTRIES)" \
        --allow-ips "$(cb_join $CB_ALLOW_IPS)" \
        --log "$CB_LOG" "$@"
}

cb_status() {
    cb_ensure_conf
    echo ""
    echo -e "${CYAN}======== 全站国家访问控制 ========${NC}"
    echo "  开关:      $([ "$CB_ENABLED" = "1" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已停用${NC}")"
    echo "  模式:      $CB_MODE $([ "$CB_MODE" = "allow" ] && echo '(仅放行列表国家，其余全拦)')"
    echo "  国家:      ${CB_COUNTRIES:-（空）}"
    echo "  白名单 IP: ${CB_ALLOW_IPS:-（无）}"
    echo "  生成文件:  $CB_OUT"
    if [ -f "$CB_OUT" ]; then
        local v4 v6
        v4=$(grep -cE '^(deny|allow) [^:]+;' "$CB_OUT" 2>/dev/null)
        v6=$(grep -cE '^(deny|allow) [^:]*:[^;]+;' "$CB_OUT" 2>/dev/null)
        echo "  条目:      IPv4 $v4 / IPv6 $v6"
        stat -c '  最后更新:  %y' "$CB_OUT" | cut -d. -f1
    else
        echo -e "  条目:      ${YELLOW}文件不存在（未生效）${NC}"
    fi
    if [ -f "$CB_STATE/countries.json" ]; then
        local ts age
        ts=$(stat -c %Y "$CB_STATE/countries.json" 2>/dev/null || echo 0)
        age=$(( ( $(date +%s) - ts ) / 3600 ))
        echo "  CIDR 缓存: ${age} 小时前更新（$CB_STATE/countries.json）"
    fi
    if [ -f "$CB_CRON" ]; then
        echo "  自动更新: 已开启（$CB_CRON）"
    else
        echo "  自动更新: 未开启（site country-block cron on）"
    fi
    echo ""
    echo "  说明: 本规则在 nginx http 级生效，对所有站点（含以后新建）有效，"
    echo "        与后台「访问地区控制」互不影响。"
    echo ""
}

cb_validate_codes() {
    local cc
    for cc in "$@"; do
        if ! [[ "$cc" =~ ^[A-Za-z]{2}$ ]]; then
            echo -e "${RED}无效国家代码: $cc（需 ISO 3166-1 两位，如 CN/US/JP）${NC}"
            return 1
        fi
    done
    return 0
}

cb_validate_ip() {
    python3 - "$1" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_network(sys.argv[1], strict=False)
except ValueError:
    sys.exit(1)
PY
}

cb_set() {
    cb_ensure_conf
    [ $# -eq 0 ] && { echo "用法: site country-block set <CC>..."; return 2; }
    cb_validate_codes "$@" || return 2
    CB_COUNTRIES=$(echo "$@" | tr '[:lower:]' '[:upper:]' | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' ' | sed 's/ $//')
    cb_save_conf
    echo -e "${GREEN}国家列表已设为: $CB_COUNTRIES${NC}"
    cb_apply
}

cb_add() {
    cb_ensure_conf
    [ $# -eq 0 ] && { echo "用法: site country-block add <CC>..."; return 2; }
    cb_validate_codes "$@" || return 2
    CB_COUNTRIES=$(echo "$CB_COUNTRIES $*" | tr '[:lower:]' '[:upper:]' | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' ' | sed 's/ $//')
    cb_save_conf
    echo -e "${GREEN}国家列表: $CB_COUNTRIES${NC}"
    cb_apply
}

cb_remove() {
    cb_ensure_conf
    [ $# -eq 0 ] && { echo "用法: site country-block remove <CC>..."; return 2; }
    local remove_list cc keep=""
    remove_list=$(echo "$@" | tr '[:lower:]' '[:upper:]' | tr ' ' '\n')
    for cc in $CB_COUNTRIES; do
        echo "$remove_list" | grep -qxF "$cc" || keep="$keep $cc"
    done
    CB_COUNTRIES=$(echo "$keep" | sed 's/^ *//')
    cb_save_conf
    echo -e "${GREEN}国家列表: ${CB_COUNTRIES:-（空）}${NC}"
    if [ -z "$CB_COUNTRIES" ]; then
        echo -e "${YELLOW}列表为空，规则已停用（文件会删除）${NC}"
        python3 "$CB_PY" --off --out "$CB_OUT" --state "$CB_STATE" --log "$CB_LOG"
        return $?
    fi
    cb_apply
}

cb_allow_add() {
    cb_ensure_conf
    [ $# -eq 0 ] && { echo "用法: site country-block allow <IP/CIDR>..."; return 2; }
    local ip
    for ip in "$@"; do
        cb_validate_ip "$ip" || { echo -e "${RED}无效 IP/CIDR: $ip${NC}"; return 2; }
    done
    CB_ALLOW_IPS=$(echo "$CB_ALLOW_IPS $*" | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' ' | sed 's/ $//')
    cb_save_conf
    echo -e "${GREEN}白名单: $CB_ALLOW_IPS${NC}"
    cb_apply
}

cb_allow_remove() {
    cb_ensure_conf
    [ $# -eq 0 ] && { echo "用法: site country-block unallow <IP/CIDR>..."; return 2; }
    local remove_list keep="" ip
    remove_list=$(echo "$@" | tr ' ' '\n')
    for ip in $CB_ALLOW_IPS; do
        echo "$remove_list" | grep -qxF "$ip" || keep="$keep $ip"
    done
    CB_ALLOW_IPS=$(echo "$keep" | sed 's/^ *//')
    cb_save_conf
    echo -e "${GREEN}白名单: ${CB_ALLOW_IPS:-（无）}${NC}"
    cb_apply
}

cb_on() {
    cb_ensure_conf
    CB_ENABLED=1
    cb_save_conf
    echo -e "${GREEN}已启用${NC}"
    cb_apply
}

cb_off() {
    cb_ensure_conf
    CB_ENABLED=0
    cb_save_conf
    echo -e "${YELLOW}已停用，正在移除 nginx 规则${NC}"
    cb_apply
}

cb_update() { cb_apply --refresh; }

cb_cron() {
    cb_ensure_conf
    case "${1:-}" in
        on)
            cat > "$CB_CRON" <<EOF
# Site Manager 全站国家访问控制：每日检查，RIR 缓存超过 7 天才重新下载
17 4 * * * root /usr/local/bin/site country-block apply >/dev/null 2>&1
EOF
            chmod 644 "$CB_CRON"
            cat > /etc/logrotate.d/site-country-block <<'EOF'
/var/log/country-block.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
EOF
            chmod 644 /etc/logrotate.d/site-country-block
            echo -e "${GREEN}已开启每日检查更新（04:17；RIR 数据缓存 7 天）${NC}"
            ;;
        off)
            rm -f "$CB_CRON" /etc/logrotate.d/site-country-block
            echo -e "${YELLOW}已关闭自动更新${NC}"
            ;;
        *)
            echo "用法: site country-block cron on|off"
            ;;
    esac
}

cb_menu() {
    echo "用法:"
    echo "  site country-block                      查看状态"
    echo "  site country-block on|off               启用/停用（停用会删除 nginx 规则）"
    echo "  site country-block set <CC>...          设定拦截国家，如: set CN US JP"
    echo "  site country-block add <CC>...          追加国家"
    echo "  site country-block remove <CC>...       移除国家"
    echo "  site country-block allow <IP/CIDR>...   加白名单（优先于国家拦截）"
    echo "  site country-block unallow <IP/CIDR>... 移除白名单"
    echo "  site country-block update               重新拉取 RIR 数据并生效"
    echo "  site country-block cron on|off          每日检查更新开关（缓存 7 天）"
    echo ""
    echo "说明: 规则写在 nginx http 级（$CB_DEFAULT_OUT），"
    echo "      对现有和以后新建的所有站点生效，与后台「访问地区控制」无关。"
}

country_block() {
    local sub="${1:-status}"
    shift 2>/dev/null || true
    case "$sub" in
        status|"") cb_status;;
        on) cb_on;;
        off) cb_off;;
        set) cb_set "$@";;
        add) cb_add "$@";;
        remove|rm) cb_remove "$@";;
        allow) cb_allow_add "$@";;
        unallow) cb_allow_remove "$@";;
        update) cb_update;;
        apply) cb_apply "$@";;
        cron) cb_cron "$@";;
        help|-h|--help) cb_menu;;
        *) echo -e "${RED}未知子命令: $sub${NC}"; echo ""; cb_menu; return 1;;
    esac
}
