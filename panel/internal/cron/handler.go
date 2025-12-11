package cron

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type CronJob struct {
	ID       int    `json:"id"`
	Minute   string `json:"minute"`
	Hour     string `json:"hour"`
	Day      string `json:"day"`
	Month    string `json:"month"`
	Weekday  string `json:"weekday"`
	Command  string `json:"command"`
	User     string `json:"user"`
	Enabled  bool   `json:"enabled"`
	Schedule string `json:"schedule"` // 人类可读的时间描述
}

type CronHandler struct{}

func NewCronHandler() *CronHandler {
	return &CronHandler{}
}

func (h *CronHandler) RegisterRoutes(r fiber.Router) {
	cron := r.Group("/cron")
	cron.Get("", h.List)
	cron.Post("", h.Create)
	cron.Put("/:id", h.Update)
	cron.Delete("/:id", h.Delete)
	cron.Post("/:id/toggle", h.Toggle)
	cron.Post("/run", h.RunNow)
}

// List 获取所有 cron 任务
func (h *CronHandler) List(c *fiber.Ctx) error {
	jobs, err := parseCrontab()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to read crontab: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   jobs,
	})
}

// Create 创建新的 cron 任务
func (h *CronHandler) Create(c *fiber.Ctx) error {
	var req struct {
		Minute  string `json:"minute"`
		Hour    string `json:"hour"`
		Day     string `json:"day"`
		Month   string `json:"month"`
		Weekday string `json:"weekday"`
		Command string `json:"command"`
		User    string `json:"user"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request",
		})
	}

	// 验证必填字段
	if req.Command == "" {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Command is required",
		})
	}

	// 设置默认值
	if req.Minute == "" {
		req.Minute = "*"
	}
	if req.Hour == "" {
		req.Hour = "*"
	}
	if req.Day == "" {
		req.Day = "*"
	}
	if req.Month == "" {
		req.Month = "*"
	}
	if req.Weekday == "" {
		req.Weekday = "*"
	}
	if req.User == "" {
		req.User = "root"
	}

	// 构建 cron 行
	cronLine := fmt.Sprintf("%s %s %s %s %s %s %s",
		req.Minute, req.Hour, req.Day, req.Month, req.Weekday, req.User, req.Command)

	// 添加到 crontab
	if err := addCronLine(cronLine); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to add cron job: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Cron job created",
	})
}

// Update 更新 cron 任务
func (h *CronHandler) Update(c *fiber.Ctx) error {
	idStr := c.Params("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid ID",
		})
	}

	var req struct {
		Minute  string `json:"minute"`
		Hour    string `json:"hour"`
		Day     string `json:"day"`
		Month   string `json:"month"`
		Weekday string `json:"weekday"`
		Command string `json:"command"`
		User    string `json:"user"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request",
		})
	}

	// 构建新的 cron 行
	cronLine := fmt.Sprintf("%s %s %s %s %s %s %s",
		req.Minute, req.Hour, req.Day, req.Month, req.Weekday, req.User, req.Command)

	if err := updateCronLine(id, cronLine); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to update cron job: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Cron job updated",
	})
}

// Delete 删除 cron 任务
func (h *CronHandler) Delete(c *fiber.Ctx) error {
	idStr := c.Params("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid ID",
		})
	}

	if err := deleteCronLine(id); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to delete cron job: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Cron job deleted",
	})
}

// Toggle 启用/禁用 cron 任务
func (h *CronHandler) Toggle(c *fiber.Ctx) error {
	idStr := c.Params("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid ID",
		})
	}

	if err := toggleCronLine(id); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to toggle cron job: " + err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Cron job toggled",
	})
}

// RunNow 立即执行命令
func (h *CronHandler) RunNow(c *fiber.Ctx) error {
	var req struct {
		Command string `json:"command"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request",
		})
	}

	if req.Command == "" {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Command is required",
		})
	}

	// 使用 bash 执行命令
	cmd := exec.Command("bash", "-c", req.Command)
	output, err := cmd.CombinedOutput()

	return c.JSON(fiber.Map{
		"status": err == nil,
		"data": fiber.Map{
			"output":  string(output),
			"success": err == nil,
		},
	})
}

// isValidCronField 检查是否是有效的 cron 时间字段
// 有效格式: *, 数字, */数字, 数字-数字, 数字,数字
func isValidCronField(field string) bool {
	if field == "*" {
		return true
	}
	// 匹配: 数字、*/数字、数字-数字、数字,数字 等组合
	cronFieldRegex := regexp.MustCompile(`^[\d\*,\-/]+$`)
	return cronFieldRegex.MatchString(field)
}

// isValidUser 检查用户名是否像是真实用户（不是示例占位符）
func isValidUser(user string) bool {
	// 排除明显的示例占位符
	invalidUsers := []string{
		"user-name",
		"username",
		"user",
	}
	lowerUser := strings.ToLower(user)
	for _, invalid := range invalidUsers {
		if lowerUser == invalid {
			return false
		}
	}
	// 用户名应该是字母数字和下划线，不包含连字符（user-name 是示例）
	// 但实际上 Linux 用户名可以包含连字符，所以我们只排除已知的示例
	return true
}

// isExampleLine 检查是否是示例/说明行
func isExampleLine(command string) bool {
	// 检查命令是否包含示例文本
	examplePatterns := []string{
		"command to be executed",
		"to be executed",
	}
	lowerCmd := strings.ToLower(command)
	for _, pattern := range examplePatterns {
		if strings.Contains(lowerCmd, pattern) {
			return true
		}
	}
	return false
}

// parseCrontab 解析 /etc/crontab 文件
func parseCrontab() ([]CronJob, error) {
	file, err := os.Open("/etc/crontab")
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var jobs []CronJob
	scanner := bufio.NewScanner(file)
	id := 0

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		// 跳过空行
		if trimmed == "" {
			continue
		}

		// 检查是否是被禁用的 cron（以 # 开头，后面跟有效的 cron 表达式）
		enabled := true
		parseLine := trimmed

		if strings.HasPrefix(trimmed, "#") {
			// 移除 # 和可能的空格
			parseLine = strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
			enabled = false

			// 如果移除 # 后是空的或者还是以 # 开头（多重注释），跳过
			if parseLine == "" || strings.HasPrefix(parseLine, "#") {
				continue
			}
		}

		// 跳过环境变量设置行 (包含 = 且第一个字段是变量名)
		if strings.Contains(parseLine, "=") {
			parts := strings.Fields(parseLine)
			if len(parts) > 0 && strings.Contains(parts[0], "=") {
				continue
			}
		}

		// 分割字段 (使用空白字符分割)
		fields := strings.Fields(parseLine)
		if len(fields) < 7 {
			continue
		}

		minute := fields[0]
		hour := fields[1]
		day := fields[2]
		month := fields[3]
		weekday := fields[4]
		user := fields[5]
		command := strings.Join(fields[6:], " ")

		// 验证前5个字段是否是有效的 cron 时间格式
		if !isValidCronField(minute) || !isValidCronField(hour) ||
			!isValidCronField(day) || !isValidCronField(month) ||
			!isValidCronField(weekday) {
			continue
		}

		// 检查是否是示例用户名
		if !isValidUser(user) {
			continue
		}

		// 检查是否是示例命令
		if isExampleLine(command) {
			continue
		}

		job := CronJob{
			ID:       id,
			Minute:   minute,
			Hour:     hour,
			Day:      day,
			Month:    month,
			Weekday:  weekday,
			User:     user,
			Command:  command,
			Enabled:  enabled,
			Schedule: formatSchedule(minute, hour, day, month, weekday),
		}

		jobs = append(jobs, job)
		id++
	}

	return jobs, scanner.Err()
}

// formatSchedule 生成人类可读的时间描述
func formatSchedule(minute, hour, day, month, weekday string) string {
	// 常见模式
	if minute == "*" && hour == "*" && day == "*" && month == "*" && weekday == "*" {
		return "每分钟"
	}
	if minute == "0" && hour == "*" && day == "*" && month == "*" && weekday == "*" {
		return "每小时"
	}
	if minute == "0" && hour == "0" && day == "*" && month == "*" && weekday == "*" {
		return "每天凌晨"
	}
	if minute == "0" && hour == "0" && day == "*" && month == "*" && weekday == "0" {
		return "每周日凌晨"
	}
	if minute == "0" && hour == "0" && day == "1" && month == "*" && weekday == "*" {
		return "每月1号凌晨"
	}

	// 通用格式
	parts := []string{}
	if minute != "*" {
		parts = append(parts, fmt.Sprintf("%s分", minute))
	}
	if hour != "*" {
		parts = append(parts, fmt.Sprintf("%s时", hour))
	}
	if day != "*" {
		parts = append(parts, fmt.Sprintf("每月%s日", day))
	}
	if month != "*" {
		parts = append(parts, fmt.Sprintf("%s月", month))
	}
	if weekday != "*" {
		weekdays := map[string]string{
			"0": "周日", "1": "周一", "2": "周二", "3": "周三",
			"4": "周四", "5": "周五", "6": "周六", "7": "周日",
		}
		if w, ok := weekdays[weekday]; ok {
			parts = append(parts, w)
		}
	}

	if len(parts) == 0 {
		return fmt.Sprintf("%s %s %s %s %s", minute, hour, day, month, weekday)
	}
	return strings.Join(parts, " ")
}

// addCronLine 添加 cron 行到 /etc/crontab
func addCronLine(line string) error {
	// 读取现有内容
	content, err := os.ReadFile("/etc/crontab")
	if err != nil {
		return err
	}

	// 追加新行
	newContent := string(content)
	if !strings.HasSuffix(newContent, "\n") {
		newContent += "\n"
	}
	newContent += line + "\n"

	return os.WriteFile("/etc/crontab", []byte(newContent), 0644)
}

// findCronLineIndex 找到第 id 个 cron 任务在文件中的行索引
func findCronLineIndex(lines []string, targetID int) int {
	cronIndex := 0

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		parseLine := trimmed
		if strings.HasPrefix(trimmed, "#") {
			parseLine = strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
			if parseLine == "" || strings.HasPrefix(parseLine, "#") {
				continue
			}
		}

		if strings.Contains(parseLine, "=") {
			parts := strings.Fields(parseLine)
			if len(parts) > 0 && strings.Contains(parts[0], "=") {
				continue
			}
		}

		fields := strings.Fields(parseLine)
		if len(fields) < 7 {
			continue
		}

		// 验证是否是有效的 cron 行
		if !isValidCronField(fields[0]) || !isValidCronField(fields[1]) ||
			!isValidCronField(fields[2]) || !isValidCronField(fields[3]) ||
			!isValidCronField(fields[4]) {
			continue
		}

		// 检查是否是示例
		user := fields[5]
		command := strings.Join(fields[6:], " ")
		if !isValidUser(user) || isExampleLine(command) {
			continue
		}

		if cronIndex == targetID {
			return i
		}
		cronIndex++
	}

	return -1
}

// updateCronLine 更新指定 ID 的 cron 行
func updateCronLine(id int, newLine string) error {
	content, err := os.ReadFile("/etc/crontab")
	if err != nil {
		return err
	}

	lines := strings.Split(string(content), "\n")
	lineIndex := findCronLineIndex(lines, id)

	if lineIndex == -1 {
		return fmt.Errorf("cron job not found")
	}

	lines[lineIndex] = newLine
	return os.WriteFile("/etc/crontab", []byte(strings.Join(lines, "\n")), 0644)
}

// deleteCronLine 删除指定 ID 的 cron 行
func deleteCronLine(id int) error {
	content, err := os.ReadFile("/etc/crontab")
	if err != nil {
		return err
	}

	lines := strings.Split(string(content), "\n")
	lineIndex := findCronLineIndex(lines, id)

	if lineIndex == -1 {
		return fmt.Errorf("cron job not found")
	}

	// 删除该行
	lines = append(lines[:lineIndex], lines[lineIndex+1:]...)
	return os.WriteFile("/etc/crontab", []byte(strings.Join(lines, "\n")), 0644)
}

// toggleCronLine 切换 cron 行的启用状态
func toggleCronLine(id int) error {
	content, err := os.ReadFile("/etc/crontab")
	if err != nil {
		return err
	}

	lines := strings.Split(string(content), "\n")
	lineIndex := findCronLineIndex(lines, id)

	if lineIndex == -1 {
		return fmt.Errorf("cron job not found")
	}

	line := lines[lineIndex]
	trimmed := strings.TrimSpace(line)

	if strings.HasPrefix(trimmed, "#") {
		// 启用：移除开头的 #
		lines[lineIndex] = strings.TrimPrefix(trimmed, "#")
		// 如果移除后开头有空格，也去掉
		lines[lineIndex] = strings.TrimSpace(lines[lineIndex])
	} else {
		// 禁用：添加 #
		lines[lineIndex] = "#" + trimmed
	}

	return os.WriteFile("/etc/crontab", []byte(strings.Join(lines, "\n")), 0644)
}
