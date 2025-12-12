#!/bin/bash
source /opt/site_manager/software/install/lib.sh
check_root

ACTION="$1"
VERSION="${2:-5.7}"

install_mysql() {
    log_step "安装 MySQL/MariaDB..."
    
    if check_installed "/usr/bin/mysql"; then
        log_warn "MySQL/MariaDB 已安装: $(mysql --version | head -1)"
        read -p "重新安装? (y/n): " c; [ "$c" != "y" ] && return
    fi

    # 生成随机 root 密码
    local root_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)

    echo "选择数据库类型:"
    echo " 1) MariaDB (推荐，完全兼容MySQL)"
    echo " 2) MySQL 官方版"
    read -p "选择 [1]: " db_type
    db_type="${db_type:-1}"

    case "$PM" in
        apt)
            if [ "$db_type" = "2" ]; then
                # MySQL 官方版
                log_step "安装 MySQL $VERSION..."
                wget -q https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb -O /tmp/mysql-apt.deb
                DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt.deb 2>/dev/null
                apt-get update
                debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password $root_pass"
                debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password $root_pass"
                apt-get install -y mysql-server || install_failed "MySQL"
                rm -f /tmp/mysql-apt.deb
            else
                # MariaDB (默认)
                log_step "安装 MariaDB..."
                apt-get update
                debconf-set-selections <<< "mariadb-server mysql-server/root_password password $root_pass"
                debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password $root_pass"
                apt-get install -y mariadb-server mariadb-client || install_failed "MariaDB"
            fi
            ;;
        yum|dnf)
            if [ "$db_type" = "2" ]; then
                $PM_INSTALL mysql-community-server mysql-community-client || install_failed "MySQL"
            else
                $PM_INSTALL mariadb-server mariadb || install_failed "MariaDB"
            fi
            ;;
    esac

    # 启动服务
    service_enable mysql 2>/dev/null || service_enable mariadb 2>/dev/null
    service_start mysql 2>/dev/null || service_start mariadb 2>/dev/null

    # 设置 root 密码
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_pass';" 2>/dev/null || \
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$root_pass');" 2>/dev/null

    firewall_allow 3306

    # 保存密码
    echo "$root_pass" > /root/.mysql_root_password
    chmod 600 /root/.mysql_root_password

    install_success "MySQL/MariaDB" "$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    echo -e " Root 密码: ${YELLOW}$root_pass${NC}"
    echo " 密码已保存到 /root/.mysql_root_password"
}

uninstall_mysql() {
    log_step "卸载 MySQL/MariaDB..."
    echo -e "${YELLOW}警告: 将删除所有数据库!${NC}"
    read -p "确定卸载? (输入 YES): " c; [ "$c" != "YES" ] && return
    
    systemctl stop mysql 2>/dev/null || systemctl stop mariadb 2>/dev/null
    
    case "$PM" in
        apt)
            apt-get remove --purge -y mysql-server mysql-client mysql-common mariadb-server mariadb-client 2>/dev/null
            apt-get autoremove -y
            ;;
        yum|dnf)
            $PM remove -y mysql-community-server mariadb-server 2>/dev/null
            ;;
    esac
    
    rm -rf /var/lib/mysql
    log_info "MySQL/MariaDB 已卸载"
}

case "$ACTION" in
    install) install_mysql;;
    uninstall) uninstall_mysql;;
    update) apt-get update && apt-get upgrade -y mariadb-server mysql-server 2>/dev/null; systemctl restart mysql 2>/dev/null || systemctl restart mariadb;;
    *) echo "用法: $0 install|uninstall|update [version]";;
esac
