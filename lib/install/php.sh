#!/bin/bash
# PHP 多版本管理脚本
# 用法: php.sh install [版本]
#       php.sh uninstall [版本]
#       php.sh list

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 支持的 PHP 版本
SUPPORTED_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")

# 常用扩展
PHP_EXTENSIONS="cli fpm common mysql curl gd mbstring xml zip bcmath intl opcache redis igbinary readline"

list_php() {
    echo ""
    echo -e "${GREEN}已安装的 PHP 版本:${NC}"
    for v in "${SUPPORTED_VERSIONS[@]}"; do
        if dpkg -l | grep -q "php${v}-cli"; then
            local status=$(systemctl is-active php${v}-fpm 2>/dev/null || echo "inactive")
            if [ "$status" = "active" ]; then
                echo -e "  PHP $v - ${GREEN}运行中${NC}"
            else
                echo -e "  PHP $v - ${YELLOW}已停止${NC}"
            fi
        fi
    done
    echo ""
    echo "可安装版本: ${SUPPORTED_VERSIONS[*]}"
}

install_php() {
    local version="$1"

    if [ -z "$version" ]; then
        echo "用法: site install php <版本>"
        echo "可用版本: ${SUPPORTED_VERSIONS[*]}"
        return 1
    fi

    # 验证版本
    local valid=0
    for v in "${SUPPORTED_VERSIONS[@]}"; do
        [ "$v" = "$version" ] && valid=1 && break
    done

    if [ $valid -eq 0 ]; then
        echo -e "${RED}不支持的版本: $version${NC}"
        echo "可用版本: ${SUPPORTED_VERSIONS[*]}"
        return 1
    fi

    # 检查是否已安装
    if dpkg -l | grep -q "php${version}-cli"; then
        echo -e "${YELLOW}PHP $version 已安装${NC}"
        return 0
    fi

    echo "正在安装 PHP $version..."

    # 添加 sury 源 (如果没有)
    if [ ! -f /etc/apt/sources.list.d/php.list ]; then
        echo "添加 PHP 软件源..."
        apt-get update -qq
        apt-get install -y -qq apt-transport-https lsb-release ca-certificates curl
        curl -sSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/php-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/php-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        apt-get update -qq
    fi

    # 安装 PHP 和扩展
    local packages=""
    for ext in $PHP_EXTENSIONS; do
        packages="$packages php${version}-${ext}"
    done

    if apt-get install -y $packages; then
        systemctl enable php${version}-fpm
        systemctl start php${version}-fpm
        echo -e "${GREEN}PHP $version 安装成功${NC}"
    else
        echo -e "${RED}PHP $version 安装失败${NC}"
        return 1
    fi
}

uninstall_php() {
    local version="$1"

    if [ -z "$version" ]; then
        echo "用法: site uninstall php <版本>"
        list_php
        return 1
    fi

    # 检查是否安装
    if ! dpkg -l | grep -q "php${version}-cli"; then
        echo -e "${YELLOW}PHP $version 未安装${NC}"
        return 0
    fi

    # 确认
    read -p "确认卸载 PHP $version? (y/n): " confirm
    [ "$confirm" != "y" ] && echo "已取消" && return 0

    echo "正在卸载 PHP $version..."

    # 停止服务
    systemctl stop php${version}-fpm 2>/dev/null
    systemctl disable php${version}-fpm 2>/dev/null

    # 卸载所有相关包
    if apt-get purge -y php${version}-*; then
        apt-get autoremove -y
        echo -e "${GREEN}PHP $version 已卸载${NC}"
    else
        echo -e "${RED}卸载失败${NC}"
        return 1
    fi
}

case "$1" in
    install) install_php "$2";;
    uninstall) uninstall_php "$2";;
    list) list_php;;
    *)
        echo "用法: $0 {install|uninstall|list} [版本]"
        list_php
        ;;
esac
