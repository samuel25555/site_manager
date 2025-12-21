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
site backup <域名>            # 备份站点
site restore <域名> <文件>     # 恢复站点
site ssl <域名>               # 申请SSL证书
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

### 定时备份
```bash
/opt/site_manager/bin/backup_cron.sh db 10           # 备份数据库,保留10份
/opt/site_manager/bin/backup_cron.sh site 7          # 备份站点,保留7份
/opt/site_manager/bin/backup_cron.sh path 5 /path    # 备份路径,保留5份
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
| `ssl.sh` | Let's Encrypt 证书管理 |
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
- `software/list.json` - 可安装软件清单

### 数据目录
```
/www/wwwroot/       # 网站文件
/www/backup/        # 备份 (按类型分: database/, site/, path/)
/srv/               # 配置目录 (ssl/, runtime/, supervisor/)
```

## 开发注意事项

- 所有 Bash 脚本需要 Root 权限运行
- Web 用户为 `www`，站点文件权限需保持一致
- PHP 支持多版本并存，优先级: 8.3 > 8.2 > 8.1 > 8.0 > 7.4
- 面板默认端口 8888，CLI 优先于 Web 面板使用
- Go 构建需要 CGO_ENABLED=1 (SQLite 依赖)
