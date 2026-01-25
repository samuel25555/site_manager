# 配置文件说明

## 配置文件列表

### 必需配置（已有默认值）
- `site_manager.conf` - 主配置文件（路径、版本等）
- `dns_accounts.json` - DNS API 账号配置（默认为空）
- `ssl_domains.json` - SSL 域名与账号绑定（自动生成）

### 可选配置（需要手动创建）
- `backup.conf` - 备份配置（含 FTP 远程备份）
- `cloudflare_<别名>.ini` - Cloudflare DNS API 凭据

---

## 快速配置指南

### 1. 备份配置（启用 FTP 远程备份）

```bash
# 复制模板
cp backup.conf.template backup.conf

# 编辑配置
vim backup.conf

# 修改以下配置：
# - FTP_ENABLED=true
# - FTP_HOST, FTP_PORT, FTP_USER, FTP_PASS
# - FTP_PATH（建议用服务器标识，如 /SERVER1）
```

### 2. Cloudflare DNS 配置（用于 DNS 验证申请 SSL）

#### 方法 1：使用 dns_accounts.json（推荐用于多账号）

```bash
# 编辑 dns_accounts.json
vim dns_accounts.json

# 添加账号（支持多账号）：
{
  "cloudflare": [
    {
      "alias": "main",
      "email": "your@example.com",
      "api_key": "your_global_api_key"
    },
    {
      "alias": "backup",
      "email": "backup@example.com",
      "api_key": "another_api_key"
    }
  ]
}

# 绑定域名到指定账号
site ssl bind example.com main
site ssl bind another.com backup

# 申请证书
site ssl example.com --dns
```

#### 方法 2：使用 .ini 文件（用于单账号或 Certbot 直接调用）

```bash
# 复制模板
cp cloudflare.ini.template cloudflare_main.ini

# 编辑凭据
vim cloudflare_main.ini

# 设置权限（重要！）
chmod 600 cloudflare_main.ini
```

### 3. DNS 账号管理命令

```bash
# 查看已配置账号
site ssl account list

# 绑定域名到账号
site ssl bind <域名> <账号别名>

# 查看域名绑定
site ssl list
```

---

## 配置文件安全

### 敏感文件（不应提交到 Git）
以下文件包含敏感信息，已添加到 `.gitignore`：
- `backup.conf` - 包含 FTP 密码
- `cloudflare_*.ini` - 包含 API 凭据
- `*_password` - 所有密码文件

### 模板文件（可以提交到 Git）
- `backup.conf.template`
- `cloudflare.ini.template`

---

## 运营服务器配置建议

每个运营服务器应该：

1. **使用独立的 FTP 路径**
   - 例如：SERVER1 → `/SERVER1`, SERVER2 → `/SERVER2`
   - 方便区分不同服务器的备份

2. **使用独立的 Cloudflare 账号（可选）**
   - 或者在同一账号下用不同的 alias 区分
   - 绑定该服务器管理的域名

3. **不要将实际配置文件提交到 Git**
   - 只提交 `.template` 模板文件
   - 服务器上创建实际配置文件

---

## 示例：配置新服务器

```bash
# 1. 克隆仓库
git clone https://github.com/your/site_manager.git
cd site_manager

# 2. 运行安装
bash install.sh

# 3. 配置备份
cp config/backup.conf.template config/backup.conf
vim config/backup.conf
# 设置 FTP_PATH="/YOUR_SERVER_NAME"

# 4. 配置 DNS（如果需要 DNS 验证申请 SSL）
vim config/dns_accounts.json
# 或创建 cloudflare_xxx.ini 文件

# 5. 绑定域名到 DNS 账号
site ssl bind your-domain.com your_account_alias

# 6. 开始使用
site create your-domain.com php80
site ssl your-domain.com --dns
```
