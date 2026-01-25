# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Site Manager 是一个轻量级 Linux 服务器管理工具，采用 CLI 优先设计，同时提供可选的 Web 面板。支持 Debian 10/11/12 和 Ubuntu 20.04/22.04/24.04。

**核心设计原则**: 所有功能的唯一实现源在 CLI 层 (Bash)，Web 层只是调用 `site` 命令的封装。

## 开发命令

### 构建 Web 面板

```bash
cd panel && bash build.sh              # 完整构建 (前端 + 后端)
cd panel/web && npm run dev            # 前端开发模式
cd panel && CGO_ENABLED=1 go build -o site_manager_panel .  # 仅构建后端
./panel/site_manager_panel --port=8888 # 运行面板
```

**重要**: Go 构建必须设置 `CGO_ENABLED=1`，因为 SQLite 依赖 cgo。

### 测试

```bash
cd panel && go test ./...              # 运行所有 Go 测试
cd panel && go test -v ./internal/auth # 测试单个包
cd panel && go test -run TestLogin     # 运行特定测试
```

### CLI 测试 (需要 Root 权限)

```bash
site list                              # 测试站点列表
site soft                              # 测试软件状态
site create test.com php               # 测试创建站点
site ssl test.com --dns                # 测试 SSL 申请
```

## 架构

### 双层架构

- **CLI 层** (`bin/site` + `lib/*.sh`): 所有核心功能的 Bash 实现，直接操作系统
- **Web 层** (`panel/`): Go API 服务，通过调用 CLI 命令实现功能

Web 面板不直接操作系统，而是调用 `site` 命令，保持单一实现源 (Single Source of Truth)。

### 关键入口点

- **CLI 主入口**: `bin/site` - 解析参数并加载对应的 lib 模块
  - 加载顺序: colors.sh → utils.sh → site_manager.conf → 功能模块
  - 所有 lib 模块通过 `source` 引入，支持热修改（无需重新构建）

- **Web 面板入口**: `panel/main.go`
  - 初始化 Fiber 框架，注册路由和中间件
  - 加载 JWT secret 和 SQLite 数据库 (`data/panel.db`)
  - 所有 API handler 在 `panel/internal/*/handler.go`

### 核心模块 (lib/)

| 文件          | 功能                                        | 关键函数                                 |
| ------------- | ------------------------------------------- | ---------------------------------------- |
| `site.sh`     | 站点创建/管理                               | create_site, delete_site, list_sites     |
| `ssl.sh`      | Let's Encrypt 证书管理，支持多账号 DNS 验证 | ssl*request, ssl_renew, ssl_account*\*   |
| `backup.sh`   | 备份/恢复，支持 FTP 远程                    | backup_site, backup_database, ftp_upload |
| `software.sh` | 软件安装/卸载/状态检测                      | install_software, software_status        |
| `db.sh`       | MySQL/MariaDB 数据库管理                    | create_db, delete_db, list_dbs           |
| `php.sh`      | PHP 多版本管理 (7.4-8.3)                    | install_php, switch_php_version          |
| `monitor.sh`  | 站点健康检查和告警                          | check_site_health, send_alert            |
| `utils.sh`    | 通用工具函数                                | validate_domain, ensure_www_user         |
| `colors.sh`   | 颜色输出定义                                | RED, GREEN, YELLOW, CYAN                 |

### Web 面板 API 模式

所有 handler 都在 `panel/internal/<模块>/handler.go`，遵循统一模式：

1. **解析请求**: 从 Fiber Context 中提取参数 (JSON/Query/Params)
2. **调用 CLI**: 使用 `exec.Command("site", ...)` 执行命令
3. **解析输出**: 解析 CLI 的 stdout/stderr
4. **返回 JSON**: 使用 Fiber 的 `c.JSON()` 返回标准格式

**重要原则**:

- Web 层不直接操作文件系统、数据库或系统服务
- 所有业务逻辑在 Bash 脚本中实现（单一真相源）
- 添加新功能时，先实现 CLI 命令，再封装 API

### 配置文件

| 文件                       | 用途                               | 格式 |
| -------------------------- | ---------------------------------- | ---- |
| `config/site_manager.conf` | 主配置 (目录路径、PHP 版本、MySQL) | Bash |
| `config/dns_accounts.json` | DNS API 账号 (Cloudflare Token)    | JSON |
| `config/ssl_domains.json`  | 域名与 DNS 账号绑定关系            | JSON |
| `config/backup.conf`       | 备份配置 (FTP、保留策略)           | Bash |
| `software/list.json`       | 可安装软件清单、版本、检测路径     | JSON |
| `panel/config/config.json` | Web 面板配置 (端口、JWT Secret)    | JSON |

### 数据目录 (生产环境)

```
/www/wwwroot/              # 网站文件 (各域名子目录)
/www/backup/               # 备份文件
  ├── database/            # 数据库备份 (.sql.gz)
  ├── site/                # 站点备份 (.tar.gz)
  └── path/                # 路径备份 (.tar.gz)
/www/vhost/nginx/          # Nginx 站点配置 (旧版兼容)
/etc/nginx/sites-available/  # Nginx 站点配置 (新版标准)
/etc/nginx/sites-enabled/    # 已启用站点符号链接
/www/wwwlogs/              # 日志文件
  ├── <域名>/              # 各站点日志
  └── site_manager/        # 管理工具日志
```

## CLI 命令速查

### 站点管理

```bash
site list                              # 列出所有站点
site create <域名> <类型>              # 创建站点 (php/static/node/python/docker/proxy)
site create <域名> <类型> --root <路径>  # 创建站点并指定自定义根目录
site delete <域名>                     # 删除站点
site enable <域名>                     # 启用站点
site disable <域名>                    # 禁用站点
site info <域名>                       # 查看站点详情
```

### SSL 证书

```bash
site ssl <域名>                        # HTTP 验证方式申请 SSL
site ssl <域名> --dns                  # DNS 验证方式申请 SSL (推荐)
site ssl "d1,d2,d3" --dns              # 多域名证书
site ssl renew                         # 续期即将过期的证书 (>30天自动跳过)
site ssl list                          # 查看证书列表
site ssl account add <别名>            # 添加 Cloudflare DNS 账号
site ssl account list                  # 查看 DNS 账号列表
site ssl bind <域名> <别名>            # 绑定域名到特定账号
```

### 软件管理

```bash
site soft                              # 查看已安装软件状态
site install <软件> [版本]             # 安装软件 (nginx/php/mysql/redis/nodejs/docker/composer/certbot/supervisor/uv)
site uninstall <软件>                  # 卸载软件
site nginx reload|restart|status       # Nginx 服务控制
site php restart                       # 重启所有 PHP-FPM
site mysql restart|status              # MySQL 服务控制
```

### 备份管理

```bash
site backup <域名>                     # 备份指定站点
site backup db [数据库]                # 备份数据库
site backup path <路径>                # 备份指定路径
site restore <域名> <文件>             # 恢复站点
site db restore <库> <文件>            # 恢复数据库
```

### 计划任务

```bash
site cron list                         # 查看任务列表
site cron add "<时间>" "<命令>"        # 添加任务
site cron remove <编号>                # 删除任务
site cron log                          # 查看任务日志
```

## 开发注意事项

### 权限与环境

- **Root 权限**: 所有 Bash 脚本必须以 root 运行 (操作系统配置、服务管理)
- **Web 用户**: 新建的文件/目录需设置 `www:www` 权限
- **用户创建**: 脚本通过 `ensure_www_user()` 自动创建 www 用户/组

### 构建要求

- **CGO 必须启用**: `CGO_ENABLED=1` (SQLite 依赖)
- **Node.js 路径**: 构建脚本硬编码了 NVM 路径，修改时注意
- **Go 版本**: 使用 `/usr/local/go/bin/go` 路径

### 代码修改生效规则

- **修改 lib/\*.sh**: 立即生效，无需重启 (CLI 每次执行时 source)
- **修改 panel/ 代码**: 需重新构建并重启面板
- **修改 software/list.json**: 立即生效 (CLI 每次读取)
- **修改 config/\*.conf**: 需重启相关服务

### 配置文件兼容性

- Nginx 配置支持两种路径: `/www/vhost/nginx` (旧版) 和 `/etc/nginx/sites-available` (新版)
- MySQL 密码文件支持三种来源: 环境变量、`/root/.mysql_root_password`、宝塔面板路径
- 所有路径在 `config/site_manager.conf` 中可配置

### 软件安装机制

- 软件定义在 `software/list.json`，安装脚本在 `software/install/<name>.sh`
- `checks` 字段用于检测软件是否已安装 (文件路径)
- `service` 字段用于服务控制 (systemd 服务名，支持 `{VERSION}` 占位符)

### Certbot Hook 机制

- DNS 验证通过 Certbot Auth Hook (`scripts/certbot_cf_auth.sh`) 实现
- 域名 → DNS 账号映射存储在 `config/ssl_domains.json`
- Post-Deploy Hook 自动重载 Nginx 配置 (写入 `/etc/letsencrypt/renewal-hooks/post-deploy/reload_nginx.sh`)

### Nginx 配置管理

- 修改配置前使用 `nginx_safe_reload()` 测试配置有效性
- 测试失败会自动回滚配置文件
- 重载使用 `nginx -s reload` 而非 `systemctl reload`

### 数据库操作

- 使用 `mysql_exec()` 和 `mysqldump_exec()` 函数，自动处理凭据
- 备份使用 `--single-transaction --quick` 参数 (InnoDB 一致性备份)
- 空备份文件会自动删除
