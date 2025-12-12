package logs

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

// 预定义日志文件列表
var logFiles = []struct {
	Name     string
	Path     string
	Category string
}{
	{"Nginx Access", "/var/log/nginx/access.log", "web"},
	{"Nginx Error", "/var/log/nginx/error.log", "web"},
	{"PHP-FPM 8.3", "/var/log/php8.3-fpm.log", "php"},
	{"PHP-FPM 8.1", "/var/log/php8.1-fpm.log", "php"},
	{"MySQL Error", "/var/log/mysql/error.log", "database"},
	{"MySQL Slow Query", "/var/log/mysql/slow.log", "database"},
	{"System Messages", "/var/log/syslog", "system"},
	{"Auth Log", "/var/log/auth.log", "system"},
	{"Supervisor", "/var/log/supervisor/supervisord.log", "process"},
	{"Redis", "/var/log/redis/redis-server.log", "database"},
	{"UFW Firewall", "/var/log/ufw.log", "firewall"},
}

type LogFile struct {
	Name     string `json:"name"`
	Path     string `json:"path"`
	Category string `json:"category"`
	Exists   bool   `json:"exists"`
	Size     int64  `json:"size"`
}

// List 获取日志文件列表
func List(c *fiber.Ctx) error {
	var results []LogFile

	for _, lf := range logFiles {
		item := LogFile{
			Name:     lf.Name,
			Path:     lf.Path,
			Category: lf.Category,
		}

		if info, err := os.Stat(lf.Path); err == nil {
			item.Exists = true
			item.Size = info.Size()
		}

		results = append(results, item)
	}

	// 扫描站点日志目录
	siteLogsDir := "/www/wwwlogs/nginx"
	if entries, err := os.ReadDir(siteLogsDir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			name := entry.Name()
			fullPath := filepath.Join(siteLogsDir, name)

			item := LogFile{
				Path:     fullPath,
				Category: "site",
				Exists:   true,
			}

			if strings.HasSuffix(name, ".access.log") {
				item.Name = strings.TrimSuffix(name, ".access.log") + " Access"
			} else if strings.HasSuffix(name, ".error.log") {
				item.Name = strings.TrimSuffix(name, ".error.log") + " Error"
			} else {
				item.Name = name
			}

			if info, err := entry.Info(); err == nil {
				item.Size = info.Size()
			}

			results = append(results, item)
		}
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   results,
	})
}

// Read 读取日志内容
func Read(c *fiber.Ctx) error {
	path := c.Query("path")
	lines := c.Query("lines", "100")

	if path == "" {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Path is required",
		})
	}

	// 验证路径安全性
	if !isValidLogPath(path) {
		return c.Status(403).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid log path",
		})
	}

	// 检查文件是否存在
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return c.Status(404).JSON(fiber.Map{
			"status":  false,
			"message": "Log file not found",
		})
	}

	// 读取日志
	numLines, _ := strconv.Atoi(lines)
	if numLines < 1 {
		numLines = 100
	}
	if numLines > 1000 {
		numLines = 1000
	}

	cmd := exec.Command("tail", "-n", strconv.Itoa(numLines), path)
	output, err := cmd.Output()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to read log",
		})
	}

	content := strings.TrimSpace(string(output))
	logLines := []string{}
	if content != "" {
		logLines = strings.Split(content, "\n")
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data": fiber.Map{
			"path":  path,
			"lines": logLines,
			"count": len(logLines),
		},
	})
}

// Search 搜索日志
func Search(c *fiber.Ctx) error {
	path := c.Query("path")
	keyword := c.Query("keyword")
	lines := c.Query("lines", "100")

	if path == "" || keyword == "" {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Path and keyword are required",
		})
	}

	if !isValidLogPath(path) {
		return c.Status(403).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid log path",
		})
	}

	numLines, _ := strconv.Atoi(lines)
	if numLines < 1 {
		numLines = 100
	}

	// 使用 grep 搜索
	cmd := exec.Command("grep", "-i", keyword, path)
	output, _ := cmd.Output() // grep 未找到时会返回错误，忽略

	content := strings.TrimSpace(string(output))
	logLines := []string{}
	if content != "" {
		all := strings.Split(content, "\n")
		// 只返回最后 N 行
		if len(all) > numLines {
			logLines = all[len(all)-numLines:]
		} else {
			logLines = all
		}
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data": fiber.Map{
			"path":    path,
			"keyword": keyword,
			"lines":   logLines,
			"count":   len(logLines),
		},
	})
}

// Clear 清空日志
func Clear(c *fiber.Ctx) error {
	var req struct {
		Path string `json:"path"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request",
		})
	}

	if !isValidLogPath(req.Path) {
		return c.Status(403).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid log path",
		})
	}

	// 清空文件（保留文件，清空内容）
	if err := os.Truncate(req.Path, 0); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to clear log",
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Log cleared",
	})
}

// 验证日志路径
func isValidLogPath(path string) bool {
	// 只允许访问特定目录下的日志
	allowedPaths := []string{
		"/var/log/",
		"/www/wwwlogs/",
		"/srv/logs/",
		"/tmp/",
	}

	cleanPath := filepath.Clean(path)
	for _, allowed := range allowedPaths {
		if strings.HasPrefix(cleanPath, allowed) {
			return true
		}
	}
	return false
}
