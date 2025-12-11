package site

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/gofiber/fiber/v2"
)

const siteCLI = "/usr/local/bin/site"
const nginxConfigDir = "/srv/config/nginx"
const logsDir = "/srv/logs/nginx"
const sslDir = "/etc/letsencrypt/live"

type Site struct {
	Domain string `json:"domain"`
	Type   string `json:"type"`
	Status string `json:"status"`
	Path   string `json:"path"`
}

type SiteDetail struct {
	Site
	Size    string `json:"size"`
	SSL     string `json:"ssl"`
	SSLInfo *SSLInfo `json:"ssl_info,omitempty"`
	Config  string `json:"config"`
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

func List(c *fiber.Ctx) error {
	cmd := exec.Command(siteCLI, "list")
	output, err := cmd.Output()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to list sites",
		})
	}

	sites := parseSiteList(string(output))

	return c.JSON(fiber.Map{
		"status": true,
		"data":   sites,
	})
}

func parseSiteList(output string) []Site {
	var sites []Site
	scanner := bufio.NewScanner(strings.NewReader(output))

	lineNum := 0
	for scanner.Scan() {
		line := scanner.Text()
		lineNum++

		if lineNum <= 3 || strings.TrimSpace(line) == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) >= 4 {
			sites = append(sites, Site{
				Domain: fields[0],
				Type:   fields[1],
				Status: fields[2],
				Path:   fields[3],
			})
		}
	}

	return sites
}

func Create(c *fiber.Ctx) error {
	var req CreateRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request body",
		})
	}

	if !isValidDomain(req.Domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	if !isValidType(req.Type) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid site type",
		})
	}

	args := []string{"create", req.Domain, req.Type}

	if req.PHP != "" {
		args = append(args, "--php="+req.PHP)
	}
	if req.Port > 0 {
		args = append(args, fmt.Sprintf("--port=%d", req.Port))
	}
	if req.Target != "" {
		args = append(args, "--target="+req.Target)
	}

	cmd := exec.Command(siteCLI, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to create site",
			"error":   string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Site created successfully",
		"output":  string(output),
	})
}

func Info(c *fiber.Ctx) error {
	domain := c.Params("domain")

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	cmd := exec.Command(siteCLI, "info", domain)
	output, err := cmd.Output()
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"status":  false,
			"message": "Site not found",
		})
	}

	detail := parseSiteInfo(string(output))
	detail.Domain = domain

	// 获取 SSL 信息
	detail.SSLInfo = getSSLInfo(domain)

	return c.JSON(fiber.Map{
		"status": true,
		"data":   detail,
	})
}

func parseSiteInfo(output string) SiteDetail {
	detail := SiteDetail{}

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch key {
		case "类型":
			detail.Type = value
		case "状态":
			detail.Status = value
		case "目录":
			detail.Path = value
		case "大小":
			detail.Size = value
		case "SSL":
			detail.SSL = value
		case "配置":
			detail.Config = value
		}
	}

	return detail
}

// 获取 SSL 证书信息
func getSSLInfo(domain string) *SSLInfo {
	certPath := filepath.Join(sslDir, domain, "fullchain.pem")
	keyPath := filepath.Join(sslDir, domain, "privkey.pem")

	info := &SSLInfo{Enabled: false}

	// 检查证书是否存在
	if _, err := os.Stat(certPath); os.IsNotExist(err) {
		return info
	}

	info.Enabled = true
	info.CertPath = certPath
	info.KeyPath = keyPath

	// 获取证书详情
	cmd := exec.Command("openssl", "x509", "-in", certPath, "-noout", "-dates", "-issuer")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.HasPrefix(line, "notBefore=") {
				info.ValidFrom = strings.TrimPrefix(line, "notBefore=")
			} else if strings.HasPrefix(line, "notAfter=") {
				info.ValidTo = strings.TrimPrefix(line, "notAfter=")
			} else if strings.HasPrefix(line, "issuer=") {
				info.Issuer = strings.TrimPrefix(line, "issuer=")
			}
		}
	}

	return info
}

func Delete(c *fiber.Ctx) error {
	domain := c.Params("domain")

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	cmd := exec.Command("sh", "-c", fmt.Sprintf("echo 'y' | %s delete %s", siteCLI, domain))
	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to delete site",
			"error":   string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Site deleted successfully",
	})
}

func Enable(c *fiber.Ctx) error {
	return siteAction(c, "enable")
}

func Disable(c *fiber.Ctx) error {
	return siteAction(c, "disable")
}

func Backup(c *fiber.Ctx) error {
	return siteAction(c, "backup")
}

func siteAction(c *fiber.Ctx, action string) error {
	domain := c.Params("domain")

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	cmd := exec.Command(siteCLI, action, domain)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": fmt.Sprintf("Failed to %s site", action),
			"error":   string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": fmt.Sprintf("Site %s successfully", action),
		"output":  string(output),
	})
}

// GetNginxConfig 获取 Nginx 配置
func GetNginxConfig(c *fiber.Ctx) error {
	domain := c.Params("domain")

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	configPath := filepath.Join(nginxConfigDir, domain+".conf")
	content, err := os.ReadFile(configPath)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"status":  false,
			"message": "Config file not found",
		})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data": fiber.Map{
			"path":    configPath,
			"content": string(content),
		},
	})
}

// SaveNginxConfig 保存 Nginx 配置
func SaveNginxConfig(c *fiber.Ctx) error {
	domain := c.Params("domain")

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	var req struct {
		Content string `json:"content"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request body",
		})
	}

	configPath := filepath.Join(nginxConfigDir, domain+".conf")

	// 先测试配置语法
	tempFile := "/tmp/nginx_test_" + domain + ".conf"
	if err := os.WriteFile(tempFile, []byte(req.Content), 0644); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to write temp file",
		})
	}
	defer os.Remove(tempFile)

	// 保存配置
	if err := os.WriteFile(configPath, []byte(req.Content), 0644); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to save config",
		})
	}

	// 测试 Nginx 配置
	testCmd := exec.Command("nginx", "-t")
	testOutput, testErr := testCmd.CombinedOutput()
	if testErr != nil {
		return c.JSON(fiber.Map{
			"status":  true,
			"message": "Config saved but Nginx test failed",
			"warning": string(testOutput),
		})
	}

	// 重载 Nginx
	reloadCmd := exec.Command("nginx", "-s", "reload")
	reloadOutput, reloadErr := reloadCmd.CombinedOutput()
	if reloadErr != nil {
		return c.JSON(fiber.Map{
			"status":  true,
			"message": "Config saved but reload failed",
			"warning": string(reloadOutput),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Config saved and Nginx reloaded",
	})
}

// GetLogs 获取访问日志
func GetLogs(c *fiber.Ctx) error {
	domain := c.Params("domain")
	logType := c.Query("type", "access") // access 或 error

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	var logFile string
	if logType == "error" {
		logFile = filepath.Join(logsDir, domain+".error.log")
	} else {
		logFile = filepath.Join(logsDir, domain+".access.log")
	}

	// 读取最后 100 行
	cmd := exec.Command("tail", "-n", "100", logFile)
	output, err := cmd.Output()
	if err != nil {
		// 日志文件可能不存在
		return c.JSON(fiber.Map{
			"status": true,
			"data": fiber.Map{
				"path":  logFile,
				"lines": []string{},
			},
		})
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) == 1 && lines[0] == "" {
		lines = []string{}
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data": fiber.Map{
			"path":  logFile,
			"lines": lines,
		},
	})
}

// RequestSSL 申请 SSL 证书
func RequestSSL(c *fiber.Ctx) error {
	domain := c.Params("domain")

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	var req struct {
		Email string `json:"email"`
	}
	if err := c.BodyParser(&req); err != nil {
		req.Email = "admin@" + domain
	}

	// 使用 certbot 申请证书
	cmd := exec.Command("certbot", "certonly",
		"--webroot",
		"-w", "/srv/www/"+domain,
		"-d", domain,
		"--email", req.Email,
		"--agree-tos",
		"--non-interactive",
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to request SSL certificate",
			"error":   string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "SSL certificate requested successfully",
		"output":  string(output),
	})
}

// RenewSSL 续期 SSL 证书
func RenewSSL(c *fiber.Ctx) error {
	domain := c.Params("domain")

	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	cmd := exec.Command("certbot", "renew", "--cert-name", domain, "--force-renewal")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to renew SSL certificate",
			"error":   string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "SSL certificate renewed successfully",
		"output":  string(output),
	})
}
