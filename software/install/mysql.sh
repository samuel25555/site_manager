#!/bin/bash
source /opt/site_manager/software/install/lib.sh
check_root

ACTION="$1"
VERSION="${2:-8.0}"

install_mysql() {
    log_step "安装 MySQL $VERSION..."
    
    local root_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)

    case "$PM" in
        apt)
            debconf-set-selections <<< "mysql-server mysql-server/root_password password $root_pass"
            debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $root_pass"
            apt-get update && apt-get install -y mysql-server mysql-client || install_failed "MySQL"
            ;;
        yum|dnf)
            $PM_INSTALL mysql-community-server mysql-community-client || install_failed "MySQL"
            ;;
    esac

    service_enable mysql
    service_start mysql
    firewall_allow 3306

    echo "$root_pass" > /root/.mysql_root_password
    chmod 600 /root/.mysql_root_password

    install_success "MySQL" "$(get_installed_version mysql)"
    echo -e " Root 密码: ${YELLOW}$root_pass${NC}"
    echo " 密码已保存到 /root/.mysql_root_password"
}

uninstall_mysql() {
    log_step "卸载 MySQL..."
    echo -e "${YELLOW}警告: 将删除所有数据库!${NC}"
    read -p "确定卸载? (输入 YES): " c; [ "$c" != "YES" ] && return
    service_stop mysql
    apt-get remove --purge -y mysql-server mysql-client mysql-common 2>/dev/null
    rm -rf /var/lib/mysql
    log_info "MySQL 已卸载"
}

case "$ACTION" in
    install) install_mysql;; uninstall) uninstall_mysql;;
    update) apt-get update && apt-get upgrade -y mysql-server; service_restart mysql;;
    *) echo "用法: $0 install|uninstall|update [version]";;
esac
