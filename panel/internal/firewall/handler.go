package firewall

import (
	"os/exec"
	"regexp"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type FirewallHandler struct{}

func NewFirewallHandler() *FirewallHandler {
	return &FirewallHandler{}
}

type Rule struct {
	Number   int    `json:"number"`
	To       string `json:"to"`
	Action   string `json:"action"`
	From     string `json:"from"`
	Port     string `json:"port"`
	Protocol string `json:"protocol"`
	Comment  string `json:"comment"`
}

type StatusResponse struct {
	Enabled bool   `json:"enabled"`
	Rules   []Rule `json:"rules"`
}

// RegisterRoutes 注册路由
func (h *FirewallHandler) RegisterRoutes(router fiber.Router) {
	fw := router.Group("/firewall")
	fw.Get("/status", h.Status)
	fw.Post("/enable", h.Enable)
	fw.Post("/disable", h.Disable)
	fw.Post("/allow", h.AllowPort)
	fw.Post("/deny", h.DenyPort)
	fw.Delete("/rule/:number", h.DeleteRule)
}

// Status 获取防火墙状态
func (h *FirewallHandler) Status(c *fiber.Ctx) error {
	// 检查 ufw 状态
	out, err := exec.Command("ufw", "status", "numbered").Output()
	if err != nil {
		return c.JSON(fiber.Map{
			"status": true,
			"data": StatusResponse{
				Enabled: false,
				Rules:   []Rule{},
			},
		})
	}

	output := string(out)
	enabled := !strings.Contains(output, "inactive")

	rules := parseRules(output)

	return c.JSON(fiber.Map{
		"status": true,
		"data": StatusResponse{
			Enabled: enabled,
			Rules:   rules,
		},
	})
}

// Enable 开启防火墙
func (h *FirewallHandler) Enable(c *fiber.Ctx) error {
	// 确保 SSH 端口开放
	exec.Command("ufw", "allow", "22/tcp").Run()
	exec.Command("ufw", "allow", "80/tcp").Run()
	exec.Command("ufw", "allow", "443/tcp").Run()
	exec.Command("ufw", "allow", "8888/tcp").Run()

	// 设置默认策略
	exec.Command("ufw", "default", "deny", "incoming").Run()
	exec.Command("ufw", "default", "allow", "outgoing").Run()

	// 启用
	cmd := exec.Command("ufw", "--force", "enable")
	if err := cmd.Run(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": "启用防火墙失败"})
	}

	return c.JSON(fiber.Map{"status": true, "message": "防火墙已开启"})
}

// Disable 关闭防火墙
func (h *FirewallHandler) Disable(c *fiber.Ctx) error {
	cmd := exec.Command("ufw", "disable")
	if err := cmd.Run(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": "关闭防火墙失败"})
	}

	return c.JSON(fiber.Map{"status": true, "message": "防火墙已关闭"})
}

// AllowPort 开放端口
func (h *FirewallHandler) AllowPort(c *fiber.Ctx) error {
	var req struct {
		Port     int    `json:"port"`
		Protocol string `json:"protocol"`
		Comment  string `json:"comment"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if req.Port < 1 || req.Port > 65535 {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "无效的端口号"})
	}

	if req.Protocol == "" {
		req.Protocol = "tcp"
	}

	rule := strconv.Itoa(req.Port) + "/" + req.Protocol
	args := []string{"allow", rule}
	if req.Comment != "" {
		args = append(args, "comment", req.Comment)
	}

	cmd := exec.Command("ufw", args...)
	if err := cmd.Run(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": "添加规则失败"})
	}

	return c.JSON(fiber.Map{"status": true, "message": "端口 " + rule + " 已开放"})
}

// DenyPort 关闭端口
func (h *FirewallHandler) DenyPort(c *fiber.Ctx) error {
	var req struct {
		Port     int    `json:"port"`
		Protocol string `json:"protocol"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if req.Port < 1 || req.Port > 65535 {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "无效的端口号"})
	}

	if req.Protocol == "" {
		req.Protocol = "tcp"
	}

	rule := strconv.Itoa(req.Port) + "/" + req.Protocol
	cmd := exec.Command("ufw", "delete", "allow", rule)
	if err := cmd.Run(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": "删除规则失败"})
	}

	return c.JSON(fiber.Map{"status": true, "message": "端口 " + rule + " 规则已删除"})
}

// DeleteRule 删除规则
func (h *FirewallHandler) DeleteRule(c *fiber.Ctx) error {
	number := c.Params("number")

	cmd := exec.Command("bash", "-c", "echo y | ufw delete "+number)
	if err := cmd.Run(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": "删除规则失败"})
	}

	return c.JSON(fiber.Map{"status": true, "message": "规则已删除"})
}

// parseRules 解析 ufw 输出
func parseRules(output string) []Rule {
	var rules []Rule
	lines := strings.Split(output, "\n")

	// 匹配规则行: [ 1] 22/tcp                     ALLOW IN    Anywhere
	re := regexp.MustCompile(`\[\s*(\d+)\]\s+(.+?)\s+(ALLOW|DENY)\s+IN\s+(.+?)(?:\s+#\s*(.+))?$`)

	for _, line := range lines {
		matches := re.FindStringSubmatch(line)
		if matches != nil {
			num, _ := strconv.Atoi(matches[1])
			to := strings.TrimSpace(matches[2])
			action := matches[3]
			from := strings.TrimSpace(matches[4])
			comment := ""
			if len(matches) > 5 {
				comment = matches[5]
			}

			// 解析端口和协议
			port := ""
			protocol := ""
			if strings.Contains(to, "/") {
				parts := strings.Split(to, "/")
				port = parts[0]
				protocol = parts[1]
			} else {
				port = to
			}

			rules = append(rules, Rule{
				Number:   num,
				To:       to,
				Action:   action,
				From:     from,
				Port:     port,
				Protocol: protocol,
				Comment:  comment,
			})
		}
	}

	return rules
}
