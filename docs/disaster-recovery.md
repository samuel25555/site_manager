# 灾备：服务器挂了怎么用备份恢复

## 备份全景（都汇总到 dev `/data/backup/data_other_backup/<机器>/`，每天 03:30 rsync 镜像到 mru `/data/mirror/dev/`）

| 内容 | 来源 | 位置 | 频率 / 保留 |
|---|---|---|---|
| 数据库 | `site backup db` | `<机器>/database/mysql/<库>/` | 每小时 / 51 份 |
| 代码 wwwroot | `site backup path /www/wwwroot` | `<机器>/path/wwwroot/` | 每天 04:00 / 5 份 |
| 后台站点 | `site backup site <域名>` | `<机器>/site/<域名>/` | 每天 / 5 份 |
| **服务器配置** | `site backup server` | `<机器>/server/` | 每天 04:45 / 5 份 |
| **Cloudflare 配置** | dev `cf_backup.py backup` | `DEV1/cloudflare/` | 每天 02:50 / 5 份 |
| dev 管理中枢 | dev `dev_infra_backup.sh` | `DEV1/infra/` | 每天 02:40 / 14 份 |

`<机器>` 是各机 backup.conf 的 FTP_PATH（mru 仍叫 `consenys`）。

**服务器配置包**含：nginx(`/etc/nginx` `/www/vhost`)、证书(`/www/ssl` `/etc/letsencrypt`)、site_manager 配置(DNS/FTP 凭据)、
crontab、supervisor、PHP/MySQL/Redis 配置、MySQL root 密码、UFW/SSH/systemd/sysctl/limits、docker compose + .env、
`/usr/local/bin` 小脚本、`/root/tools`；`_meta/` 下是 MySQL 账号授权 SQL、包清单、PHP 扩展、监听端口、防火墙规则、docker 现状、`site list`。

## 整机重建

1. 新机装 Debian → `install.sh` 装 site_manager；按 `_meta/packages_manual.txt`、`_meta/php*_modules.txt` 补软件
2. 从 dev 取三样最新包：`server/`、`path/wwwroot/`、`database/mysql/<库>/`
3. 配置先解到临时目录再挑着拷（网卡、fstab、SSH 端口要和新机核对，不要整包覆盖 /etc）：
   ```bash
   mkdir /root/restore && tar -xzpf server_*.tar.gz -C /root/restore
   cd /root/restore
   cp -a etc/nginx/. /etc/nginx/; cp -a www/vhost www/ssl /www/; cp -a etc/letsencrypt /etc/
   cp -a opt/site_manager/config/. /opt/site_manager/config/
   cp -a etc/supervisor/. /etc/supervisor/; cp root/.mysql_root_password /root/
   crontab var/spool/cron/crontabs/root
   ```
   `/etc/nginx/sites-available` 必须是 → `/www/vhost/nginx` 的软链（见 CLAUDE.md）。
4. 代码：`tar -xzpf path_wwwroot_*.tar.gz -C /www`；数据库：`site db restore <库> <包>`
5. MySQL 应用账号：`mysql -uroot -p < /root/restore/_meta/mysql_grants.sql`（每库备份不含 mysql 系统库，漏这步应用连不上库）
6. `nginx -t && systemctl reload nginx`；`supervisorctl reread && supervisorctl update`；按 `_meta/ufw_status.txt` 放行端口
7. DNS 切到新 IP：`/domain` 技能 `dns set-ip <旧IP> <新IP>`

## Cloudflare 恢复（在 dev 上）

```bash
cd /opt/projects/other/cloudflare_dns
.venv/bin/python cf_backup.py restore /data/backup/data_other_backup/DEV1/cloudflare/cf_config_<时间>.tar.gz <域名>            # 预览
.venv/bin/python cf_backup.py restore <快照> <域名> --to <另一个账号短名> --yes   # 账号被封：换账号重建 zone，打印新 NS
.venv/bin/python cf_backup.py restore <快照> <域名> --only rules --yes          # 只恢复规则
```
DNS 只补缺不删多余；规则按 phase 整组覆盖；设置只同步 SSL/HTTPS/缓存等常用项。换账号后要去 NameSilo 改 NS。

## 不在上述备份里的（各自有脚本或尚无）

- mru：JumpServer(`jumpserver_backup.sh`)、tg-monitor(`tgmonitor_backup.sh`)、kefu(`kefu_backup.sh`) 各有备份；**mailcow 邮件数据无备份**
- imdb2：tiktok_fans_check postgres 有 `backup_db.sh`；**imdb 的 tiktok_data_clear(Mongo) 无备份**
- 打包时排除了 `.git`、日志、node_modules、压缩包（见 `config/backup_exclude.conf`）
