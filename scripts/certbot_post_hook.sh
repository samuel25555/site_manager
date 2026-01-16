#!/bin/bash
# Certbot Post-Hook: Reload Nginx after certificate renewal
# Place/Symlink this to /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh

if command -v systemctl >/dev/null 2>&1; then
    systemctl reload nginx
    echo "Nginx reloaded via systemctl"
elif command -v service >/dev/null 2>&1; then
    service nginx reload
    echo "Nginx reloaded via service"
else
    /usr/sbin/nginx -s reload
    echo "Nginx reloaded via direct command"
fi
