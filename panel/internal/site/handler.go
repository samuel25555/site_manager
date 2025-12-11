package site

import (
	"bufio"
	"fmt"
	"os/exec"
	"regexp"
	"strings"

	"github.com/gofiber/fiber/v2"
)

const siteCLI = "/usr/local/bin/site-new"

type Site struct {
	Domain  string `json:"domain"`
	Type    string `json:"type"`
	Status  string `json:"status"`
	Path    string `json:"path"`
}

type SiteDetail struct {
	Site
	Size     string `json:"size"`
	SSL      string `json:"ssl"`
	Config   string `json:"config"`
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
	// 简单验证：只允许字母、数字、点和横线
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
		
		// 跳过标题行
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

	// 验证
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

	// 构建命令参数
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

func Delete(c *fiber.Ctx) error {
	domain := c.Params("domain")
	
	if !isValidDomain(domain) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid domain name",
		})
	}

	// 使用 yes 命令自动确认
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
