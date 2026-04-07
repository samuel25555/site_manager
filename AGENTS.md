# AGENTS.md

本文件为在此仓库中工作的 AI 编程助手提供指导。

## 项目概述

Site Manager 是一个轻量级 Linux 服务器管理工具，采用 CLI 优先设计，可选 Web 面板。支持 Debian 10/11/12 和 Ubuntu 20.04/22.04/24.04。

**核心原则**：所有功能都在 CLI 层（Bash）实现。Web 层只是调用 `site` 命令的包装器。

## 构建命令

### Web 面板（Go + Vue）
```bash
# 完整构建（前端 + 后端）
cd panel && bash build.sh

# 仅前端（开发模式）
cd panel/web && npm run dev

# 仅前端（生产构建）
cd panel/web && npm run build

# 仅后端（需要 CGO 支持 SQLite）
cd panel && CGO_ENABLED=1 go build -o site_manager_panel .

# 运行面板
./panel/site_manager_panel --port=8888
```

### CLI（Bash）
无需构建 - 脚本为解释执行。修改 `lib/*.sh` 后立即生效。

## 测试命令

### Go 测试
```bash
cd panel

# 运行所有测试
go test ./...

# 运行特定包的测试
go test -v ./internal/auth

# 运行特定测试函数（最常用）
go test -v -run TestFunctionName ./internal/auth

# 运行并查看覆盖率
go test -cover ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

### CLI 测试（需要 root）
```bash
site list                    # 测试站点列表
site soft                    # 测试软件状态
site create test.com php     # 测试站点创建
site ssl test.com --dns      # 测试 SSL 申请
```

## 代码风格指南

### Go（后端）
- **导入**：标准库在前，第三方库其次，内部包最后。组间用空行分隔
- **格式化**：使用 `gofmt` 或 `goimports`，导入排序: 标准库 > 第三方 > 内部
- **错误处理**：显式检查错误，使用 `if err != nil` 模式，将错误向上传递
- **命名**：
  - 导出标识符使用 PascalCase
  - 未导出标识符使用 camelCase
  - 缩写使用全大写（HTTP、URL、DB）
- **API 处理器**：遵循 `panel/internal/*/handler.go` 中的模式：
  1. 从 Fiber 上下文解析请求
  2. 通过 `exec.Command("site", ...)` 调用 CLI
  3. 解析 stdout/stderr
  4. 返回 JSON 响应

### TypeScript/Vue（前端）
- **格式化**：项目使用默认 Vue/Vite 配置。遵循现有模式
- **组件**：使用 Vue 3 Composition API 和 `<script setup>`
- **导入**：使用 `@/` 别名指向 src 目录
- **类型**：为 API 响应定义接口，避免使用 `any`

### Bash（CLI）
- **缩进**：4 个空格
- **函数**：使用 `snake_case`
- **变量**：常量使用 `UPPER_CASE`，局部变量使用 `lower_case`
- **错误处理**：适当使用 `set -e`，检查命令退出码
- **引号**：始终引用变量：`"$variable"`

## 架构

### 双层架构
- **CLI 层**（`bin/site` + `lib/*.sh`）：Bash 实现的核心功能
- **Web 层**（`panel/`）：调用 CLI 命令的 Go API

### 关键入口点
- CLI：`bin/site` → 加载 `lib/*.sh` 模块
- Web：`panel/main.go` → Fiber 框架，处理器在 `panel/internal/*/handler.go`

### 重要规则
1. Web 层绝不直接操作文件、数据库或服务
2. 所有业务逻辑都在 Bash 脚本中（单一数据源）
3. 添加功能时：先实现 CLI，再添加 API 包装器

## 文件修改效果

| 文件类型 | 效果 |
|---------|------|
| `lib/*.sh` | 立即生效（每次 CLI 运行时加载） |
| `panel/*.go` | 需要重新构建和重启 |
| `config/*.conf` | 需要重启服务 |
| `software/list.json` | 立即生效（每次使用时读取） |

## Nginx 配置规则

### SSL/HTTPS 设置
**重要**：配置 SSL 时，80 和 443 必须写在同一个 server 块中：

```nginx
server {
    listen 80;
    listen 443 ssl http2;
    server_name example.com;
    root /www/wwwroot/example.com;
    
    ssl_certificate /www/ssl/example.com/fullchain.pem;
    ssl_certificate_key /www/ssl/example.com/privkey.pem;
    
    # HTTP 跳转到 HTTPS
    if ($scheme != "https") {
        return 301 https://$host$request_uri;
    }
    
    # ... location 块
}
```

**禁止**：不要分成两个 server 块（一个 80，一个 443）

### 目录命名
- 站点目录名必须与绑定的第一个域名完全一致
- 例如：server_name api.music222.com api.bmw777.local; → 目录名应为 api.music222.com

### SSL 证书规则
**绑定域名到 Cloudflare 账号：**
```bash
# 绑定根域名（不是子域名）
site ssl bind example.com <账号别名>

# 申请泛解析证书（包含 example.com 和 *.example.com）
site ssl "example.com" --dns --wildcard
```

**规则：**
1. 必须绑定根域名（如 music222.com），不是子域名（如 api.music222.com）
2. 申请证书时使用 `--wildcard` 参数申请泛解析证书
3. 泛解析证书自动包含：`example.com` 和 `*.example.com`
4. 所有子域名站点共用同一个泛解析证书

## 常见模式

### 添加新 API 端点
1. 在相应的 `lib/*.sh` 文件中添加 CLI 命令
2. 在 `panel/internal/<module>/handler.go` 中添加处理器
3. 在 `panel/main.go` 中注册路由
4. 处理器通过 `exec.Command()` 调用 CLI，绝不直接修改系统

### 错误响应
```go
return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
    "error": "description",
})
```

### 成功响应
```go
return c.JSON(fiber.Map{
    "message": "success",
    "data": result,
})
```

## 远程服务器操作规则

### 文件备份规范
- **修改文件备份必须使用带时间戳的后缀** - 格式：`文件名.bak.YYYYMMDD_HHMMSS`（如 `file.php.bak.20250206_143052`）
- 禁止直接覆盖远程服务器文件

### 远程文件修改流程
**优先使用本地修改工作流**：
1. 下载远程文件到本地 `/tmp/` 目录
2. 在本地修改文件
3. 本地验证语法/格式（如 `php -l`、`gofmt` 等）
4. 上传回远程服务器
5. 远程再次验证

**修改前必须**：
1. 先备份原文件（带时间戳后缀）
2. 查看原文件内容，理解当前逻辑
3. 只做针对性修改，不要整体替换

**注意事项**：
- 多个服务器的"相同功能"不能假设代码一样，必须分别检查
- 远程操作前先确认：这个修改是否适用于目标服务器？
