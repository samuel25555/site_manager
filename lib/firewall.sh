#!/bin/bash
#===============================================================================
# Site Manager - 防火墙管理模块
# 使用 ufw 管理防火墙规则
#===============================================================================

#---------------------------------------
# 检查并安装 ufw
#---------------------------------------
ensure_ufw_installed() {
    if ! command -v ufw &>/dev/null; then
        log_info "安装 ufw 防火墙..."
        apt-get update -qq
        apt-get install -y ufw > /dev/null 2>&1
        log_success "ufw 安装完成"
    fi
}

#---------------------------------------
# 防火墙状态
#---------------------------------------
firewall_status() {
    ensure_ufw_installed

    local status=$(ufw status 2>/dev/null | head -1)

    echo ""
    echo "防火墙状态"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$status" == *"inactive"* ]]; then
        echo -e "状态: ${RED}已关闭${NC}"
    else
        echo -e "状态: ${GREEN}已开启${NC}"
        echo ""
        echo "规则列表:"
        echo "─────────────────────────────────────────────────────────────"
        ufw status numbered 2>/dev/null | tail -n +4
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#---------------------------------------
# 开启防火墙
#---------------------------------------
firewall_enable() {
    ensure_ufw_installed

    # 确保 SSH 端口开放
    local ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    ssh_port="${ssh_port:-22}"

    log_info "开启防火墙..."

    # 设置默认策略
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1

    # 确保 SSH 开放
    ufw allow "$ssh_port/tcp" comment 'SSH' > /dev/null 2>&1

    # 开放常用端口
    ufw allow 80/tcp comment 'HTTP' > /dev/null 2>&1
    ufw allow 443/tcp comment 'HTTPS' > /dev/null 2>&1

    # 启用防火墙
    echo "y" | ufw enable > /dev/null 2>&1

    log_success "防火墙已开启"
    log_info "已自动开放端口: SSH($ssh_port), HTTP(80), HTTPS(443)"

    firewall_status
}

#---------------------------------------
# 关闭防火墙
#---------------------------------------
firewall_disable() {
    ensure_ufw_installed

    log_warn "正在关闭防火墙..."
    ufw disable > /dev/null 2>&1
    log_success "防火墙已关闭"
}

#---------------------------------------
# 开放端口
#---------------------------------------
firewall_allow() {
    ensure_ufw_installed

    local port="$1"
    local protocol="${2:-tcp}"
    local comment="$3"

    if [[ -z "$port" ]]; then
        log_error "请指定端口号"
        echo "用法: site firewall allow <端口> [协议] [备注]"
        echo "例如: site firewall allow 8080"
        echo "      site firewall allow 3306 tcp MySQL"
        echo "      site firewall allow 53 udp DNS"
        return 1
    fi

    # 验证端口
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "无效的端口号: $port (有效范围: 1-65535)"
        return 1
    fi

    # 验证协议
    if [[ ! "$protocol" =~ ^(tcp|udp|both)$ ]]; then
        log_error "无效的协议: $protocol (支持: tcp, udp, both)"
        return 1
    fi

    log_info "开放端口 $port/$protocol..."

    if [[ "$protocol" == "both" ]]; then
        if [[ -n "$comment" ]]; then
            ufw allow "$port" comment "$comment" > /dev/null 2>&1
        else
            ufw allow "$port" > /dev/null 2>&1
        fi
    else
        if [[ -n "$comment" ]]; then
            ufw allow "$port/$protocol" comment "$comment" > /dev/null 2>&1
        else
            ufw allow "$port/$protocol" > /dev/null 2>&1
        fi
    fi

    log_success "端口 $port/$protocol 已开放"
}

#---------------------------------------
# 关闭端口
#---------------------------------------
firewall_deny() {
    ensure_ufw_installed

    local port="$1"
    local protocol="${2:-tcp}"

    if [[ -z "$port" ]]; then
        log_error "请指定端口号"
        echo "用法: site firewall deny <端口> [协议]"
        return 1
    fi

    # 验证端口
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "无效的端口号: $port"
        return 1
    fi

    log_info "关闭端口 $port/$protocol..."

    if [[ "$protocol" == "both" ]]; then
        ufw delete allow "$port" > /dev/null 2>&1
    else
        ufw delete allow "$port/$protocol" > /dev/null 2>&1
    fi

    log_success "端口 $port/$protocol 规则已删除"
}

#---------------------------------------
# 删除规则 (按编号)
#---------------------------------------
firewall_delete() {
    ensure_ufw_installed

    local rule_num="$1"

    if [[ -z "$rule_num" ]]; then
        log_error "请指定规则编号"
        echo "用法: site firewall delete <编号>"
        echo ""
        echo "使用 'site firewall status' 查看规则编号"
        return 1
    fi

    if ! [[ "$rule_num" =~ ^[0-9]+$ ]]; then
        log_error "无效的规则编号: $rule_num"
        return 1
    fi

    echo "y" | ufw delete "$rule_num" > /dev/null 2>&1
    log_success "规则 #$rule_num 已删除"
}

#---------------------------------------
# 允许 IP 访问
#---------------------------------------
firewall_allow_ip() {
    ensure_ufw_installed

    local ip="$1"
    local port="$2"

    if [[ -z "$ip" ]]; then
        log_error "请指定 IP 地址"
        echo "用法: site firewall allow-ip <IP> [端口]"
        echo "例如: site firewall allow-ip 192.168.1.100"
        echo "      site firewall allow-ip 192.168.1.0/24 3306"
        return 1
    fi

    log_info "允许 IP $ip 访问..."

    if [[ -n "$port" ]]; then
        ufw allow from "$ip" to any port "$port" > /dev/null 2>&1
        log_success "已允许 $ip 访问端口 $port"
    else
        ufw allow from "$ip" > /dev/null 2>&1
        log_success "已允许 $ip 访问所有端口"
    fi
}

#---------------------------------------
# 禁止 IP 访问
#---------------------------------------
firewall_deny_ip() {
    ensure_ufw_installed

    local ip="$1"

    if [[ -z "$ip" ]]; then
        log_error "请指定 IP 地址"
        echo "用法: site firewall deny-ip <IP>"
        return 1
    fi

    log_info "禁止 IP $ip 访问..."
    ufw deny from "$ip" > /dev/null 2>&1
    log_success "已禁止 $ip 访问"
}

#---------------------------------------
# 重置防火墙
#---------------------------------------
firewall_reset() {
    ensure_ufw_installed

    log_warn "这将删除所有防火墙规则！"
    read -p "确认重置? (y/n) [n]: " confirm

    if [[ "$confirm" != "y" ]]; then
        log_info "取消重置"
        return
    fi

    ufw --force reset > /dev/null 2>&1
    log_success "防火墙已重置"
}

#---------------------------------------
# 常用端口快捷操作
#---------------------------------------
firewall_preset() {
    local preset="$1"
    local action="${2:-allow}"

    case "$preset" in
        web)
            firewall_allow 80 tcp "HTTP"
            firewall_allow 443 tcp "HTTPS"
            ;;
        ssh)
            local ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            firewall_allow "${ssh_port:-22}" tcp "SSH"
            ;;
        mysql)
            firewall_allow 3306 tcp "MySQL"
            ;;
        redis)
            firewall_allow 6379 tcp "Redis"
            ;;
        ftp)
            firewall_allow 21 tcp "FTP"
            firewall_allow 20 tcp "FTP-Data"
            ;;
        mail)
            firewall_allow 25 tcp "SMTP"
            firewall_allow 465 tcp "SMTPS"
            firewall_allow 587 tcp "Submission"
            firewall_allow 110 tcp "POP3"
            firewall_allow 995 tcp "POP3S"
            firewall_allow 143 tcp "IMAP"
            firewall_allow 993 tcp "IMAPS"
            ;;
        *)
            echo "可用的预设:"
            echo "  web   - 开放 80, 443 (HTTP/HTTPS)"
            echo "  ssh   - 开放 SSH 端口"
            echo "  mysql - 开放 3306 (MySQL)"
            echo "  redis - 开放 6379 (Redis)"
            echo "  ftp   - 开放 20, 21 (FTP)"
            echo "  mail  - 开放邮件相关端口"
            echo ""
            echo "用法: site firewall preset <预设名>"
            ;;
    esac
}

#---------------------------------------
# 列出规则
#---------------------------------------
firewall_list() {
    ensure_ufw_installed

    echo ""
    echo "防火墙规则列表"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ufw status verbose 2>/dev/null
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#---------------------------------------
# 主入口
#---------------------------------------
firewall_main() {
    local action="$1"
    shift

    case "$action" in
        status|"")
            firewall_status
            ;;
        on|enable)
            firewall_enable
            ;;
        off|disable)
            firewall_disable
            ;;
        allow)
            firewall_allow "$@"
            ;;
        deny)
            firewall_deny "$@"
            ;;
        delete|remove)
            firewall_delete "$@"
            ;;
        allow-ip)
            firewall_allow_ip "$@"
            ;;
        deny-ip|block)
            firewall_deny_ip "$@"
            ;;
        reset)
            firewall_reset
            ;;
        preset)
            firewall_preset "$@"
            ;;
        list)
            firewall_list
            ;;
        *)
            echo "防火墙管理命令:"
            echo ""
            echo "  site firewall status        - 查看防火墙状态"
            echo "  site firewall on            - 开启防火墙"
            echo "  site firewall off           - 关闭防火墙"
            echo ""
            echo "  site firewall allow <端口> [协议] [备注]"
            echo "                              - 开放端口 (协议: tcp/udp/both)"
            echo "  site firewall deny <端口>   - 关闭端口"
            echo "  site firewall delete <编号> - 删除规则"
            echo ""
            echo "  site firewall allow-ip <IP> [端口]"
            echo "                              - 允许 IP 访问"
            echo "  site firewall deny-ip <IP>  - 禁止 IP 访问"
            echo ""
            echo "  site firewall preset <名称> - 快捷开放端口组"
            echo "                              (web/ssh/mysql/redis/ftp/mail)"
            echo ""
            echo "  site firewall reset         - 重置所有规则"
            echo "  site firewall list          - 列出所有规则"
            ;;
    esac
}
