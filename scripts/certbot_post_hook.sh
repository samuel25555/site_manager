#!/bin/bash
# Certbot Post-Hook: sync renewed certs from letsencrypt/live to /www/ssl, then reload Nginx.
# Place/Symlink this to /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
#
# Why: site_manager nginx vhosts reference /www/ssl/<domain>/, but the system certbot
# timer (`certbot renew`) only updates /etc/letsencrypt/live/. Without this sync, nginx
# keeps serving the stale (eventually expired) /www/ssl copy after every auto-renewal.
# This hook copies any newer live cert into /www/ssl and reloads only when something changed.

SSL_DIR="/www/ssl"
changed=0

if [ -d "$SSL_DIR" ]; then
    for dir in "$SSL_DIR"/*/; do
        [ -d "$dir" ] || continue
        domain=$(basename "$dir")
        live="/etc/letsencrypt/live/$domain"
        [ -f "$live/fullchain.pem" ] || continue
        # 仅当 live 副本比 /www/ssl 现有副本新时才同步
        if [ "$live/fullchain.pem" -nt "$SSL_DIR/$domain/fullchain.pem" ]; then
            cp -L "$live/fullchain.pem" "$SSL_DIR/$domain/fullchain.pem"
            cp -L "$live/privkey.pem"  "$SSL_DIR/$domain/privkey.pem"
            chmod 644 "$SSL_DIR/$domain/fullchain.pem"
            chmod 600 "$SSL_DIR/$domain/privkey.pem"
            echo "Synced cert: $domain"
            changed=1
        fi
    done
fi

# 仅在证书有更新时才 reload，避免每 12h 无谓重载
if [ "$changed" = "1" ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reload nginx && echo "Nginx reloaded via systemctl"
    elif command -v service >/dev/null 2>&1; then
        service nginx reload && echo "Nginx reloaded via service"
    else
        /usr/sbin/nginx -s reload && echo "Nginx reloaded via direct command"
    fi
fi
