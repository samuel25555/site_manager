package software

import (
	"os/exec"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type Software struct {
	Name        string `json:"name"`
	Version     string `json:"version"`
	Status      string `json:"status"`
	Description string `json:"description"`
	Installed   bool   `json:"installed"`
}

// 预定义软件列表
var softwareList = []struct {
	Name        string
	Service     string
	VersionCmd  string
	Description string
}{
	{"nginx", "nginx", "nginx -v 2>&1 | grep -oP '\\d+\\.\\d+\\.\\d+'", "高性能 Web 服务器"},
	{"php8.3-fpm", "php8.3-fpm", "php8.3 -v 2>&1 | head -1 | grep -oP '\\d+\\.\\d+\\.\\d+'", "PHP 8.3 FastCGI 进程管理器"},
	{"php8.1-fpm", "php8.1-fpm", "php8.1 -v 2>&1 | head -1 | grep -oP '\\d+\\.\\d+\\.\\d+'", "PHP 8.1 FastCGI 进程管理器"},
	{"mysql", "mysql", "mysql --version 2>&1 | grep -oP '\\d+\\.\\d+\\.\\d+'", "MySQL 数据库服务器"},
	{"mariadb", "mariadb", "mariadb --version 2>&1 | grep -oP '\\d+\\.\\d+\\.\\d+'", "MariaDB 数据库服务器"},
	{"redis", "redis-server", "redis-server --version 2>&1 | grep -oP 'v=\\d+\\.\\d+\\.\\d+' | cut -d= -f2", "Redis 内存数据库"},
	{"supervisor", "supervisor", "supervisord --version 2>&1 | grep -oP '\\d+\\.\\d+\\.\\d+'", "进程管理工具"},
	{"docker", "docker", "docker --version 2>&1 | grep -oP '\\d+\\.\\d+\\.\\d+'", "容器运行时"},
	{"postgresql", "postgresql", "psql --version 2>&1 | grep -oP '\\d+\\.\\d+'", "PostgreSQL 数据库"},
	{"mongodb", "mongod", "mongod --version 2>&1 | grep -oP 'v\\d+\\.\\d+\\.\\d+' | tr -d v", "MongoDB NoSQL 数据库"},
}

// List 获取软件列表
func List(c *fiber.Ctx) error {
	var results []Software

	for _, sw := range softwareList {
		soft := Software{
			Name:        sw.Name,
			Description: sw.Description,
		}

		// 检查是否安装（通过 which 或 dpkg）
		whichCmd := exec.Command("which", strings.Split(sw.Service, "-")[0])
		if err := whichCmd.Run(); err == nil {
			soft.Installed = true

			// 获取版本
			verCmd := exec.Command("sh", "-c", sw.VersionCmd)
			if output, err := verCmd.Output(); err == nil {
				soft.Version = strings.TrimSpace(string(output))
			}

			// 检查服务状态
			statusCmd := exec.Command("systemctl", "is-active", sw.Service)
			if output, err := statusCmd.Output(); err == nil {
				soft.Status = strings.TrimSpace(string(output))
			} else {
				soft.Status = "inactive"
			}
		} else {
			soft.Installed = false
			soft.Status = "not installed"
		}

		results = append(results, soft)
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   results,
	})
}

// Start 启动服务
func Start(c *fiber.Ctx) error {
	name := c.Params("name")
	return serviceAction(c, name, "start")
}

// Stop 停止服务
func Stop(c *fiber.Ctx) error {
	name := c.Params("name")
	return serviceAction(c, name, "stop")
}

// Restart 重启服务
func Restart(c *fiber.Ctx) error {
	name := c.Params("name")
	return serviceAction(c, name, "restart")
}

// Reload 重载配置
func Reload(c *fiber.Ctx) error {
	name := c.Params("name")
	return serviceAction(c, name, "reload")
}

func serviceAction(c *fiber.Ctx, name, action string) error {
	// 验证服务名
	valid := false
	for _, sw := range softwareList {
		if sw.Name == name || sw.Service == name {
			name = sw.Service // 使用实际服务名
			valid = true
			break
		}
	}

	if !valid {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid service name",
		})
	}

	cmd := exec.Command("systemctl", action, name)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to " + action + " service",
			"error":   string(output),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Service " + action + " successfully",
	})
}

// Status 获取服务详细状态
func Status(c *fiber.Ctx) error {
	name := c.Params("name")

	// 验证服务名
	var serviceName string
	for _, sw := range softwareList {
		if sw.Name == name || sw.Service == name {
			serviceName = sw.Service
			break
		}
	}

	if serviceName == "" {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid service name",
		})
	}

	cmd := exec.Command("systemctl", "status", serviceName)
	output, _ := cmd.CombinedOutput()

	return c.JSON(fiber.Map{
		"status": true,
		"data": fiber.Map{
			"name":   name,
			"output": string(output),
		},
	})
}
