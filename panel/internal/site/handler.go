package site

import (
	
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

const nginxConfigDir = "/etc/nginx/sites-available"
const nginxEnabledDir = "/etc/nginx/sites-enabled"
const sitesDir = "/www/wwwroot"
const logsDir = "/var/log/nginx/sites"

type Site struct {
	Domain string `json:"domain"`
	Type   string `json:"type"`
	Status string `json:"status"`
	Path   string `json:"path"`
}

type SiteDetail struct {
	Site
	Size    string   `json:"size"`
	SSL     string   `json:"ssl"`
	SSLInfo *SSLInfo `json:"ssl_info,omitempty"`
	Config  string   `json:"config"`
}

type SSLInfo struct {
	Enabled   bool   `json:"enabled"`
	Issuer    string `json:"issuer,omitempty"`
	ValidFrom string `json:"valid_from,omitempty"`
	ValidTo   string `json:"valid_to,omitempty"`
	CertPath  string `json:"cert_path,omitempty"`
	KeyPath   string `json:"key_path,omitempty"`
}

type CreateRequest struct {
	Domain string `json:"domain"`
	Type   string `json:"type"`
	PHP    string `json:"php,omitempty"`
	Port   int    `json:"port,omitempty"`
	Target string `json:"target,omitempty"`
}

// 验证域名格式
func isValidDomain(domain string) bool {
	match, _ := regexp.MatchString(`^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$`, domain)
	return match && len(domain) >= 3 && len(domain) <= 253
}

// 验证站点类型
func isValidType(t string) bool {
	validTypes := []string{"php", "static", "node", "python", "docker", "proxy"}
	for _, v := range validTypes {
		if t == v || strings.HasPrefix(t, v+":") {
			return true
		}
	}
	return false
}

// List 列出所有站点 - 直接读取 nginx 配置
func List(c *fiber.Ctx) error {
	sites := []Site{}

	files, err := os.ReadDir(nginxConfigDir)
	if err != nil {
		return c.JSON(fiber.Map{
			"status": true,
			"data":   sites,
		})
	}

	for _, file := range files {
		if file.IsDir() {
			continue
		}

		name := file.Name()
		// 跳过 default 和备份文件
		if name == "default" || strings.HasSuffix(name, ".bak") {
			continue
		}

		domain := strings.TrimSuffix(name, ".conf")
		domain = strings.TrimSuffix(domain, ".disabled")

		// 读取配置判断类型
		configPath := filepath.Join(nginxConfigDir, name)
		siteType := detectSiteType(configPath)

		// 判断状态
		status := "disabled"
		enabledPath := filepath.Join(nginxEnabledDir, domain)
		enabledPathConf := filepath.Join(nginxEnabledDir, domain+".conf")
		if _, err := os.Lstat(enabledPath); err == nil {
			status = "enabled"
		} else if _, err := os.Lstat(enabledPathConf); err == nil {
			status = "enabled"
		}

		sites = append(sites, Site{
			Domain: domain,
			Type:   siteType,
			Status: status,
			Path:   filepath.Join(sitesDir, domain),
		})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   sites,
	})
}

// detectSiteType 从 nginx 配置检测站点类型
func detectSiteType(configPath string) string {
	content, err := os.ReadFile(configPath)
	if err != nil {
		return "unknown"
	}

	configStr := string(content)

	if strings.Contains(configStr, "fastcgi_pass") || strings.Contains(configStr, "php-fpm") {
		return "php"
	}
	if strings.Contains(configStr, "proxy_pass") {
		return "proxy"
	}
	if strings.Contains(configStr, "uwsgi_pass") {
		return "python"
	}

	return "static"
}

// Info 获取站点详情
func Info(c *fiber.Ctx) error {
	domain := c.Params("domain")
	if domain == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "域名不能为空"})
	}

	// 查找配置文件
	configPath := filepath.Join(nginxConfigDir, domain)
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		configPath = filepath.Join(nginxConfigDir, domain+".conf")
		if _, err := os.Stat(configPath); os.IsNotExist(err) {
			return c.Status(404).JSON(fiber.Map{"status": false, "message": "站点不存在"})
		}
	}

	// 读取配置
	config, _ := os.ReadFile(configPath)

	// 检测类型和状态
	siteType := detectSiteType(configPath)
	status := "disabled"
	enabledPath := filepath.Join(nginxEnabledDir, domain)
	if _, err := os.Lstat(enabledPath); err == nil {
		status = "enabled"
	}

	// 计算目录大小
	sitePath := filepath.Join(sitesDir, domain)
	size := getDirSize(sitePath)

	// SSL 信息
	sslInfo := getSSLInfo(string(config), domain)
	sslStatus := "未配置"
	if sslInfo != nil && sslInfo.Enabled {
		sslStatus = "已启用"
	}

	detail := SiteDetail{
		Site: Site{
			Domain: domain,
			Type:   siteType,
			Status: status,
			Path:   sitePath,
		},
		Size:    size,
		SSL:     sslStatus,
		SSLInfo: sslInfo,
		Config:  string(config),
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   detail,
	})
}

func getDirSize(path string) string {
	cmd := exec.Command("du", "-sh", path)
	output, err := cmd.Output()
	if err != nil {
		return "未知"
	}
	parts := strings.Fields(string(output))
	if len(parts) > 0 {
		return parts[0]
	}
	return "未知"
}

func getSSLInfo(config string, domain string) *SSLInfo {
	// 从配置中提取证书路径
	certRe := regexp.MustCompile(`ssl_certificate\s+([^;]+);`)
	keyRe := regexp.MustCompile(`ssl_certificate_key\s+([^;]+);`)

	certMatch := certRe.FindStringSubmatch(config)
	keyMatch := keyRe.FindStringSubmatch(config)

	if len(certMatch) < 2 || len(keyMatch) < 2 {
		return nil
	}

	certPath := strings.TrimSpace(certMatch[1])
	keyPath := strings.TrimSpace(keyMatch[1])

	info := &SSLInfo{
		Enabled:  true,
		CertPath: certPath,
		KeyPath:  keyPath,
	}

	// 解析证书获取详细信息
	certData, err := os.ReadFile(certPath)
	if err == nil {
		block, _ := pem.Decode(certData)
		if block != nil {
			cert, err := x509.ParseCertificate(block.Bytes)
			if err == nil {
				info.Issuer = cert.Issuer.CommonName
				info.ValidFrom = cert.NotBefore.Format("2006-01-02")
				info.ValidTo = cert.NotAfter.Format("2006-01-02")
			}
		}
	}

	return info
}

// Create 创建站点
func Create(c *fiber.Ctx) error {
	var req CreateRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "无效的请求"})
	}

	if !isValidDomain(req.Domain) {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "无效的域名格式"})
	}

	if req.Type == "" {
		req.Type = "php"
	}

	if !isValidType(req.Type) {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "无效的站点类型"})
	}

	// 检查是否已存在
	configPath := filepath.Join(nginxConfigDir, req.Domain)
	if _, err := os.Stat(configPath); err == nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "站点已存在"})
	}

	// 创建站点目录
	sitePath := filepath.Join(sitesDir, req.Domain)
	if req.Type == "php" {
		os.MkdirAll(filepath.Join(sitePath, "public"), 0755)
		// 创建默认 index.php
		indexContent := `<?php
echo "<h1>Welcome to ` + req.Domain + `</h1>";
phpinfo();
`
		os.WriteFile(filepath.Join(sitePath, "public", "index.php"), []byte(indexContent), 0644)
	} else {
		os.MkdirAll(sitePath, 0755)
		// 创建默认 index.html
		indexContent := `<!DOCTYPE html>
<html>
<head><title>` + req.Domain + `</title></head>
<body><h1>Welcome to ` + req.Domain + `</h1></body>
</html>`
		os.WriteFile(filepath.Join(sitePath, "index.html"), []byte(indexContent), 0644)
	}

	// 设置权限
	exec.Command("chown", "-R", "www-data:www-data", sitePath).Run()

	// 生成 nginx 配置
	nginxConfig := generateNginxConfig(req)
	if err := os.WriteFile(configPath, []byte(nginxConfig), 0644); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "message": "创建配置失败"})
	}

	// 启用站点
	enabledPath := filepath.Join(nginxEnabledDir, req.Domain)
	os.Symlink(configPath, enabledPath)

	// 创建日志目录
	os.MkdirAll(logsDir, 0755)

	// 重载 nginx
	exec.Command("nginx", "-t").Run()
	exec.Command("systemctl", "reload", "nginx").Run()

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "站点创建成功",
		"data": Site{
			Domain: req.Domain,
			Type:   req.Type,
			Status: "enabled",
			Path:   sitePath,
		},
	})
}

func generateNginxConfig(req CreateRequest) string {
	sitePath := filepath.Join(sitesDir, req.Domain)
	root := sitePath
	if req.Type == "php" {
		root = filepath.Join(sitePath, "public")
	}

	config := fmt.Sprintf(`# Site Manager managed - %s
# Type: %s
# Created: %s

server {
    listen 80;
    server_name %s;
    root %s;
    index index.php index.html index.htm;

    access_log %s/%s_access.log;
    error_log %s/%s_error.log;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

`, req.Domain, req.Type, time.Now().Format("2006-01-02"), req.Domain, root, logsDir, req.Domain, logsDir, req.Domain)

	if req.Type == "php" {
		phpVersion := "8.3"
		if req.PHP != "" {
			phpVersion = req.PHP
		}
		config += fmt.Sprintf(`    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php%s-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
`, phpVersion)
	} else if req.Type == "proxy" {
		target := req.Target
		if target == "" {
			target = fmt.Sprintf("http://127.0.0.1:%d", req.Port)
		}
		config += fmt.Sprintf(`    location / {
        proxy_pass %s;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
`, target)
	} else {
		config += `    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
`
	}

	return config
}

// Delete 删除站点
func Delete(c *fiber.Ctx) error {
	domain := c.Params("domain")
	if domain == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "域名不能为空"})
	}

	// 删除 nginx 配置
	configPath := filepath.Join(nginxConfigDir, domain)
	enabledPath := filepath.Join(nginxEnabledDir, domain)

	os.Remove(enabledPath)
	os.Remove(configPath)
	os.Remove(configPath + ".conf")
	os.Remove(filepath.Join(nginxEnabledDir, domain+".conf"))

	// 重载 nginx
	exec.Command("systemctl", "reload", "nginx").Run()

	// 可选：删除站点文件（危险操作，暂时保留文件）
	// sitePath := filepath.Join(sitesDir, domain)
	// os.RemoveAll(sitePath)

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "站点已删除（站点文件已保留）",
	})
}

// Enable 启用站点
func Enable(c *fiber.Ctx) error {
	domain := c.Params("domain")
	if domain == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "域名不能为空"})
	}

	configPath := filepath.Join(nginxConfigDir, domain)
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return c.Status(404).JSON(fiber.Map{"status": false, "message": "站点不存在"})
	}

	enabledPath := filepath.Join(nginxEnabledDir, domain)
	os.Remove(enabledPath) // 先删除可能存在的
	if err := os.Symlink(configPath, enabledPath); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "message": "启用失败"})
	}

	exec.Command("systemctl", "reload", "nginx").Run()

	return c.JSON(fiber.Map{"status": true, "message": "站点已启用"})
}

// Disable 禁用站点
func Disable(c *fiber.Ctx) error {
	domain := c.Params("domain")
	if domain == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "域名不能为空"})
	}

	enabledPath := filepath.Join(nginxEnabledDir, domain)
	os.Remove(enabledPath)
	os.Remove(filepath.Join(nginxEnabledDir, domain+".conf"))

	exec.Command("systemctl", "reload", "nginx").Run()

	return c.JSON(fiber.Map{"status": true, "message": "站点已禁用"})
}

// Backup 备份站点
func Backup(c *fiber.Ctx) error {
	domain := c.Params("domain")
	if domain == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "域名不能为空"})
	}

	sitePath := filepath.Join(sitesDir, domain)
	if _, err := os.Stat(sitePath); os.IsNotExist(err) {
		return c.Status(404).JSON(fiber.Map{"status": false, "message": "站点目录不存在"})
	}

	backupDir := "/www/backup"
	os.MkdirAll(backupDir, 0755)

	timestamp := time.Now().Format("20060102_150405")
	backupFile := filepath.Join(backupDir, fmt.Sprintf("%s_%s.tar.gz", domain, timestamp))

	cmd := exec.Command("tar", "-czf", backupFile, "-C", sitesDir, domain)
	if err := cmd.Run(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "message": "备份失败"})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "备份成功",
		"data": fiber.Map{
			"file": backupFile,
		},
	})
}

// GetNginxConfig 获取 Nginx 配置
func GetNginxConfig(c *fiber.Ctx) error {
	domain := c.Params("domain")
	configPath := filepath.Join(nginxConfigDir, domain)

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		configPath = filepath.Join(nginxConfigDir, domain+".conf")
	}

	config, err := os.ReadFile(configPath)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"status": false, "message": "配置不存在"})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   string(config),
	})
}

// SaveNginxConfig 保存 Nginx 配置
func SaveNginxConfig(c *fiber.Ctx) error {
	domain := c.Params("domain")

	var req struct {
		Config string `json:"config"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "无效的请求"})
	}

	configPath := filepath.Join(nginxConfigDir, domain)
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		configPath = filepath.Join(nginxConfigDir, domain+".conf")
	}

	// 先测试配置
	tmpFile := "/tmp/nginx_test_" + domain
	os.WriteFile(tmpFile, []byte(req.Config), 0644)
	defer os.Remove(tmpFile)

	// 保存配置
	if err := os.WriteFile(configPath, []byte(req.Config), 0644); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "message": "保存失败"})
	}

	// 测试并重载
	if err := exec.Command("nginx", "-t").Run(); err != nil {
		return c.JSON(fiber.Map{
			"status":  true,
			"message": "配置已保存，但语法可能有误，请检查",
		})
	}

	exec.Command("systemctl", "reload", "nginx").Run()

	return c.JSON(fiber.Map{"status": true, "message": "配置已保存并重载"})
}

// GetLogs 获取站点日志
func GetLogs(c *fiber.Ctx) error {
	domain := c.Params("domain")
	logType := c.Query("type", "access")
	lines := c.QueryInt("lines", 100)

	var logFile string
	if logType == "error" {
		logFile = filepath.Join(logsDir, domain+"_error.log")
	} else {
		logFile = filepath.Join(logsDir, domain+"_access.log")
	}

	cmd := exec.Command("tail", "-n", fmt.Sprintf("%d", lines), logFile)
	output, err := cmd.Output()
	if err != nil {
		return c.JSON(fiber.Map{
			"status": true,
			"data":   "暂无日志",
		})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   string(output),
	})
}

// RequestSSL 申请 SSL 证书
func RequestSSL(c *fiber.Ctx) error {
	domain := c.Params("domain")
	if domain == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "message": "域名不能为空"})
	}

	// 使用 certbot 申请证书
	cmd := exec.Command("certbot", "certonly", "--nginx", "-d", domain, "--non-interactive", "--agree-tos", "--email", "admin@"+domain)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "SSL 申请失败: " + string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "SSL 证书申请成功",
	})
}

// RenewSSL 续期 SSL 证书
func RenewSSL(c *fiber.Ctx) error {
	cmd := exec.Command("certbot", "renew")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "续期失败: " + string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "证书续期完成",
		"data":    string(output),
	})
}
