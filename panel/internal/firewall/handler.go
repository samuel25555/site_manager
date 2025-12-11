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
	SSHPort string `json:"ssh_port"`
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
				SSHPort: detectSSHPort(),
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
			SSHPort: detectSSHPort(),
		},
	})
}

// detectSSHPort 检测当前 SSH 端口
// 优先从 sshd 进程和配置文件检测，确保准确
func detectSSHPort() string {
	// 方法1: 从 ss/netstat 检测 sshd 监听端口（最可靠）
	out, err := exec.Command("bash", "-c", "ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -1").Output()
	if err == nil {
		port := strings.TrimSpace(string(out))
		if port != "" && isValidPort(port) {
			return port
		}
	}

	// 方法2: 从 sshd_config 读取
	out, err = exec.Command("bash", "-c", "grep -E '^\\s*Port\\s+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1").Output()
	if err == nil {
		port := strings.TrimSpace(string(out))
		if port != "" && isValidPort(port) {
			return port
		}
	}

	// 方法3: 检查当前 SSH 连接的端口 (SSH_CONNECTION 环境变量)
	out, err = exec.Command("bash", "-c", "echo $SSH_CONNECTION | awk '{print $4}'").Output()
	if err == nil {
		port := strings.TrimSpace(string(out))
		if port != "" && isValidPort(port) {
			return port
		}
	}

	// 默认返回 22
	return "22"
}

// isValidPort 检查端口号是否有效
func isValidPort(port string) bool {
	n, err := strconv.Atoi(port)
	return err == nil && n > 0 && n <= 65535
}

// Enable 开启防火墙
func (h *FirewallHandler) Enable(c *fiber.Ctx) error {
	// 检测 SSH 端口并确保开放
	sshPort := detectSSHPort()

	// 先放行所有关键端口，再启用防火墙
	exec.Command("ufw", "allow", sshPort+"/tcp", "comment", "SSH").Run()
	exec.Command("ufw", "allow", "80/tcp", "comment", "HTTP").Run()
	exec.Command("ufw", "allow", "443/tcp", "comment", "HTTPS").Run()
	exec.Command("ufw", "allow", "8888/tcp", "comment", "Site Manager Panel").Run()

	// 设置默认策略
	exec.Command("ufw", "default", "deny", "incoming").Run()
	exec.Command("ufw", "default", "allow", "outgoing").Run()

	// 启用
	cmd := exec.Command("ufw", "--force", "enable")
	if err := cmd.Run(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": "启用防火墙失败"})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "防火墙已开启，已自动放行 SSH(" + sshPort + ")、HTTP(80)、HTTPS(443)、面板(8888)",
	})
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

	// 保护关键端口
	sshPort := detectSSHPort()
	protectedPorts := map[int]string{
		8888: "面板端口",
	}

	// 添加 SSH 端口到保护列表
	if port, _ := strconv.Atoi(sshPort); port > 0 {
		protectedPorts[port] = "SSH 端口"
	}

	if name, protected := protectedPorts[req.Port]; protected {
		return c.Status(400).JSON(fiber.Map{
			"status": false,
			"error":  "禁止关闭 " + name + "，否则您将无法访问服务器",
		})
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

	// 先获取规则详情，检查是否是保护端口
	out, _ := exec.Command("ufw", "status", "numbered").Output()
	output := string(out)
	rules := parseRules(output)

	ruleNum, _ := strconv.Atoi(number)
	for _, rule := range rules {
		if rule.Number == ruleNum {
			sshPort := detectSSHPort()
			// 检查是否是 SSH 或面板端口
			if rule.Port == sshPort || rule.Port == "8888" {
				return c.Status(400).JSON(fiber.Map{
					"status": false,
					"error":  "禁止删除此规则，否则您将无法访问服务器",
				})
			}
			break
		}
	}

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
