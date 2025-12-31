# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Site Manager 是一个轻量级 Linux 服务器管理工具，采用 CLI 优先设计，同时提供可选的 Web 面板。支持 Debian 10/11/12 和 Ubuntu 20.04/22.04/24.04。

## 常用命令

### 站点管理
```bash
site                          # 显示帮助
site -m                       # 交互式菜单
site list                     # 列出所有站点
site create <域名> <类型>      # 创建站点 (类型: php/static/node/python/docker/proxy)
site delete <域名>            # 删除站点
site info <域名>              # 站点详情
```

### 备份管理
```bash
site backup <域名>            # 备份站点
site backup db [数据库]        # 备份数据库
site backup path <路径>       # 备份指定路径
site backup list              # 查看备份列表
site backup config            # 查看/修改备份配置
site restore <域名> <文件>     # 恢复站点
```

### SSL 证书管理
```bash
site ssl <域名>               # 申请SSL证书 (HTTP验证)
site ssl <域名> --dns         # 申请SSL证书 (DNS验证)
site ssl "d1,d2,d3" --dns     # 多域名证书申请
site ssl list                 # 查看证书列表和状态
site ssl renew                # 续期证书 (>30天自动跳过)

# 多账号管理 (支持多个 Cloudflare 账号)
site ssl account list         # 查看 DNS 账号列表
site ssl account add <别名>   # 添加 DNS 账号
site ssl account remove <别名> # 删除 DNS 账号
site ssl bind <域名> <别名>    # 绑定域名到账号
site ssl unbind <域名>        # 解绑域名
site ssl bindlist             # 查看域名绑定列表
```

### 计划任务管理
```bash
site cron list                # 查看计划任务列表
site cron add <时间> <命令>    # 添加计划任务
site cron remove <编号>       # 删除计划任务
site cron log [日志文件]       # 查看任务日志
site cron run <命令>          # 立即执行任务
```

### 软件管理
```bash
site install <软件> [版本]     # 安装软件 (nginx/php/mysql/redis/nodejs/docker/composer/certbot)
site soft                     # 查看已安装软件
```

### 面板与服务
```bash
site panel <start|stop|restart>   # 面板管理
site nginx <reload|restart>       # Nginx管理
site firewall <操作> [参数]        # 防火墙管理
```

### 定时备份 (推荐使用 site cron 管理)
```bash
site cron add "0 * * * *" "site backup db"           # 每小时备份数据库
site cron add "0 4 * * *" "site backup path /www/wwwroot"  # 每天4点备份站点
site cron add "0 3 * * *" "site ssl renew"           # 每天3点检查SSL续期
```

### 构建 Web 面板
```bash
cd panel && bash build.sh     # 同时构建 Vue 前端 + Go 后端
./site_manager_panel --port=8888   # 运行面板
```

## 架构

### 目录结构
- `bin/` - 可执行文件 (`site` 主命令, `backup_cron.sh` 定时备份)
- `lib/` - Bash 库文件 (13 个模块: site.sh, software.sh, backup.sh, firewall.sh 等)
- `config/` - 配置文件和模板
- `scripts/` - 辅助脚本 (certbot hooks, cron wrapper 等)
- `software/` - 软件安装脚本和清单 (`list.json`)
- `panel/` - Go + Vue Web 面板

### 技术栈
- **CLI**: Bash 脚本 (所有核心功能在 `lib/*.sh`)
- **后端**: Go 1.24 + Fiber v2 + SQLite
- **前端**: Vue 3 + Vite + Tailwind CSS + TypeScript

### 核心模块 (lib/)
| 文件 | 功能 |
|------|------|
| `site.sh` | 站点创建/管理 (PHP/Static/Node/Python/Docker/Proxy) |
| `software.sh` | 软件安装/卸载/状态 |
| `backup.sh` | 备份/恢复 (支持 FTP 远程) |
| `firewall.sh` | UFW 防火墙管理 |
| `ssl.sh` | Let's Encrypt 证书管理 (支持多账号 DNS 验证) |
| `db.sh` | 数据库备份/恢复 |
| `php.sh` | PHP 多版本管理 (7.4-8.3) |
| `panel.sh` | Web 面板管理 |
| `utils.sh` | 通用工具函数 |

### Web 面板 API 结构 (panel/internal/)
- `auth/` - JWT 认证
- `site/` - 站点管理 API
- `system/` - 系统状态 (CPU/内存/磁盘)
- `software/` - 软件管理 API
- `terminal/` - WebSocket 终端
- `firewall/` - 防火墙 API
- `files/` - 文件管理 API
- `models/` - SQLite 数据模型

### 配置文件
- `config/site_manager.conf` - 主配置 (目录路径、默认 PHP 版本)
- `config/backup.conf` - 备份配置 (FTP 设置、保留策略)
- `config/backup_exclude.conf` - 备份排除规则
- `config/dns_accounts.json` - DNS API 账号配置 (Cloudflare 等)
- `config/ssl_domains.json` - 域名与 DNS 账号绑定关系
- `software/list.json` - 可安装软件清单

### 数据目录
```
/www/wwwroot/       # 网站文件
/www/backup/        # 备份 (按类型分: database/, site/, path/)
/www/vhost/         # 配置目录 (nginx/, rewrite/, supervisor/)
```

## 开发注意事项

- 所有 Bash 脚本需要 Root 权限运行
- Web 用户为 `www`，站点文件权限需保持一致
- PHP 支持多版本并存，优先级: 8.3 > 8.2 > 8.1 > 8.0 > 7.4
- 面板默认端口 8888，CLI 优先于 Web 面板使用
- Go 构建需要 CGO_ENABLED=1 (SQLite 依赖)
