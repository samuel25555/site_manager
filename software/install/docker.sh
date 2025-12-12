#!/bin/bash
source /opt/site_manager/software/install/lib.sh
check_root

ACTION="$1"

install_docker() {
    log_step "安装 Docker..."

    case "$PM" in
        apt)
            apt-get update
            apt-get install -y ca-certificates curl gnupg
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || install_failed "Docker"
            ;;
        yum|dnf)
            $PM_INSTALL yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $PM_INSTALL docker-ce docker-ce-cli containerd.io docker-compose-plugin || install_failed "Docker"
            ;;
    esac

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m", "max-file": "3"}
}
DAEMON

    service_enable docker
    service_start docker
    install_success "Docker" "$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
}

uninstall_docker() {
    echo -e "${YELLOW}警告: 将删除所有容器和镜像!${NC}"
    read -p "确定卸载? (输入 YES): " c; [ "$c" != "YES" ] && return
    docker stop $(docker ps -aq) 2>/dev/null
    service_stop docker
    apt-get remove --purge -y docker-ce docker-ce-cli containerd.io 2>/dev/null
    rm -rf /var/lib/docker
    log_info "Docker 已卸载"
}

case "$ACTION" in
    install) install_docker;; uninstall) uninstall_docker;;
    update) apt-get update && apt-get upgrade -y docker-ce; service_restart docker;;
    *) echo "用法: $0 install|uninstall|update";;
esac
