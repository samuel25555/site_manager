#!/bin/bash
# 启用 HTTPS 防窜站功能
# 防止删除站点后访问到其他站点

ROOT_DIR="${ROOT_DIR:-/opt/site_manager}"
NGINX_CONF_DIR="${NGINX_CONF_DIR:-/www/vhost/nginx}"
SSL_DIR="${SSL_DIR:-/www/ssl}"

echo "启用 HTTPS 防窜站功能..."

# 查找一个可用的 SSL 证书
DEFAULT_CERT=""
for cert in "$SSL_DIR"/*/fullchain.pem; do
    if [ -f "$cert" ]; then
        DEFAULT_CERT="$cert"
        break
    fi
done

if [ -z "$DEFAULT_CERT" ]; then
    echo "错误: 未找到可用的 SSL 证书"
    echo "请先为至少一个站点申请证书"
    exit 1
fi

DEFAULT_KEY="${DEFAULT_CERT%/*}/privkey.pem"
DEFAULT_DOMAIN=$(basename "${DEFAULT_CERT%/*}")

echo "使用证书: $DEFAULT_DOMAIN"

# 创建防窜站配置
cat > "$NGINX_CONF_DIR/default" << NGINXCONFIG
# 默认站点 - 防止 HTTPS 窜站
# 自动生成的防窜站配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

server {
    listen 80 default_server;
    listen 443 ssl default_server;
    server_name _;
    
    # SSL 证书 (使用 $DEFAULT_DOMAIN 的证书)
    ssl_certificate $DEFAULT_CERT;
    ssl_certificate_key $DEFAULT_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    # 记录访问日志 (用于监控恶意访问)
    access_log /www/wwwlogs/default_access.log;
    error_log /www/wwwlogs/default_error.log;
    
    # 返回 444 - 直接关闭连接
    # 444 是 nginx 特殊状态码，不返回任何内容给客户端
    return 444;
}
NGINXCONFIG

# 创建符号链接
ln -sf "$NGINX_CONF_DIR/default" /etc/nginx/sites-enabled/default

# 测试并重载 nginx
if nginx -t; then
    systemctl reload nginx
    echo "✅ HTTPS 防窜站功能已启用"
    echo ""
    echo "功能说明:"
    echo "  - 访问不存在的站点时将直接关闭连接"
    echo "  - 防止删除站点后显示其他站点内容"
    echo "  - 日志位置: /www/wwwlogs/default_access.log"
else
    echo "❌ Nginx 配置测试失败"
    exit 1
fi
