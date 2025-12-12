# Site Manager

轻量级 Linux 服务器管理工具，类似宝塔面板，支持 CLI 命令行和 Web 面板两种管理方式。

## 特性

- 🖥️ **CLI 优先** - 命令行管理，高效便捷
- 🌐 **Web 面板** - 可选的图形界面（默认关闭）
- 📦 **软件管理** - 一键安装 Nginx/PHP/MySQL/Redis/Node.js/Docker
- 🔒 **SSL 证书** - Let's Encrypt 免费证书自动申请续期
- 💾 **自动备份** - 支持 FTP 远程备份，自动清理旧备份
- 🛡️ **安全管理** - 防火墙配置

## 系统要求

- Debian 10/11/12 或 Ubuntu 20.04/22.04/24.04
- x86_64 架构
- Root 权限

## 安装

```bash
# 从 GitHub 安装（需要 SSH 密钥）
git clone git@github.com:samuel25555/site_manager.git /opt/site_manager
cd /opt/site_manager && bash install.sh

# 或者从本地服务器
scp -r user@server:/opt/projects/site_manager /opt/
cd /opt/site_manager && bash install.sh
```

## 快速开始

```bash
# 查看帮助
site

# 交互式菜单
site -m

# 查看站点列表
site list

# 查看已安装软件
site soft
```

## 命令参考

### 站点管理

```bash
site list                      # 查看所有站点
site create <域名> <类型>       # 创建站点 (php/static/proxy)
site delete <域名>             # 删除站点
site enable <域名>             # 启用站点
site disable <域名>            # 禁用站点
site info <域名>               # 站点详情
```

### SSL 证书

```bash
site ssl <域名>                # 申请 SSL 证书
site ssl renew                 # 续期所有证书
```

### 软件管理

```bash
site soft                      # 查看已安装软件
site install <软件> [版本]      # 安装软件
site uninstall <软件>          # 卸载软件

# 可用软件
site install nginx [1.24|1.26|1.27]
site install php [7.4|8.0|8.1|8.2|8.3]
site install mysql [5.7|8.0]      # 可选 MySQL 或 MariaDB
site install redis
site install nodejs [18|20|22]
site install docker
```

### 服务管理

```bash
site nginx reload|restart|status
site php restart
site mysql restart|status
site redis restart|status
```

### 备份管理

```bash
# 交互式备份（编号选择）
site -m  # 选择 3) 备份管理

# 命令行备份
site backup <域名>             # 备份站点
site restore <域名> <文件>      # 恢复站点
site db backup [数据库]         # 备份数据库
site db restore <库> <文件>     # 恢复数据库
```

### 定时备份脚本

```bash
# 备份数据库（保留10份）
/opt/site_manager/bin/backup_cron.sh db 10

# 备份站点（保留7份）
/opt/site_manager/bin/backup_cron.sh site 7

# 备份指定路径（保留5份）
/opt/site_manager/bin/backup_cron.sh path 5 /path/to/dir

# 备份全部
/opt/site_manager/bin/backup_cron.sh all 10 7
```

### 防火墙

```bash
site firewall status           # 查看状态
site firewall on|off           # 开启/关闭
site firewall allow <端口>      # 放行端口
site firewall deny <端口>       # 封禁端口
```

### Web 面板

```bash
site panel start               # 启动面板
site panel stop                # 停止面板
site panel restart             # 重启面板
```

## 目录结构

```
/opt/site_manager/             # 程序目录
├── bin/
│   ├── site                   # 主命令
│   └── backup_cron.sh         # 定时备份脚本
├── config/
│   ├── site_manager.conf      # 主配置
│   ├── backup.conf            # 备份配置（FTP等）
│   └── backup_exclude.conf    # 备份排除规则
├── software/
│   ├── list.json              # 软件列表
│   └── install/               # 安装脚本
├── panel/                     # Web 面板
└── lib/                       # 库文件

/www/                          # 数据目录
├── wwwroot/                   # 站点文件
└── backup/                    # 备份文件
    ├── database/              # 数据库备份
    ├── site/                  # 站点备份
    └── path/                  # 路径备份

/etc/nginx/
├── sites-available/           # Nginx 配置
└── sites-enabled/             # 已启用站点
```

## 配置文件

### 备份配置 `/opt/site_manager/config/backup.conf`

```bash
# 本地备份
BACKUP_DIR=/www/backup
BACKUP_KEEP=7                  # 保留份数

# FTP 远程备份
FTP_ENABLED=true
FTP_HOST=ftp.example.com
FTP_PORT=21
FTP_USER=user
FTP_PASS=password
FTP_PATH=/backup
FTP_DELETE_LOCAL=false         # 上传后删除本地
```

### 备份排除规则 `/opt/site_manager/config/backup_exclude.conf`

```bash
# 排除目录
node_modules
vendor
.git
cache
logs

# 排除文件类型
*.log
*.tmp
*.cache
```

## 定时任务

安装后默认添加以下定时任务：

```bash
# 每小时备份数据库，保留10份
0 * * * * /opt/site_manager/bin/backup_cron.sh db 10

# 每天凌晨3点备份站点，保留7份
0 3 * * * /opt/site_manager/bin/backup_cron.sh site 7
```

查看/编辑定时任务：
```bash
crontab -e
```

## 日志

- 备份日志: `/var/log/site_manager/backup.log`
- 面板日志: `/tmp/panel.log`
- Nginx 日志: `/var/log/nginx/sites/<域名>/`

## 更新

```bash
cd /opt/site_manager && git pull
```

## 卸载

```bash
# 停止服务
site panel stop

# 删除程序
rm -rf /opt/site_manager
rm -f /usr/local/bin/site

# 可选：删除数据
rm -rf /www/backup
```

## License

MIT
