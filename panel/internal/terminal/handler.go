package terminal

import (
	"bufio"
	"io"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"unsafe"

	"github.com/creack/pty"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
	"github.com/golang-jwt/jwt/v5"
)

var jwtSecret []byte

// SetJWTSecret 设置 JWT 密钥（从 auth 包调用）
func SetJWTSecret(secret string) {
	jwtSecret = []byte(secret)
}

// TerminalSession 终端会话
type TerminalSession struct {
	ID     string
	Cmd    *exec.Cmd
	Pty    *os.File
	mu     sync.Mutex
	closed bool
}

// TerminalHandler 终端处理器
type TerminalHandler struct {
	sessions sync.Map
}

// NewTerminalHandler 创建处理器
func NewTerminalHandler() *TerminalHandler {
	return &TerminalHandler{}
}

// validateToken 验证 JWT token
func validateToken(tokenString string) (int64, string, error) {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})

	if err != nil || !token.Valid {
		return 0, "", fiber.ErrUnauthorized
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return 0, "", fiber.ErrUnauthorized
	}

	userID := int64(claims["user_id"].(float64))
	username := claims["username"].(string)

	return userID, username, nil
}

// RegisterRoutes 注册路由
func (h *TerminalHandler) RegisterRoutes(app *fiber.App) {
	// WebSocket 升级中间件 - 必须验证 token
	app.Use("/ws/terminal", func(c *fiber.Ctx) error {
		if websocket.IsWebSocketUpgrade(c) {
			// 从 query 参数获取 token
			token := c.Query("token")
			if token == "" {
				return c.Status(401).JSON(fiber.Map{
					"status":  false,
					"message": "Token is required",
				})
			}

			// 验证 token
			userID, username, err := validateToken(token)
			if err != nil {
				return c.Status(401).JSON(fiber.Map{
					"status":  false,
					"message": "Invalid or expired token",
				})
			}

			// 将用户信息存入 Locals，传递给 WebSocket handler
			c.Locals("user_id", userID)
			c.Locals("username", username)
			c.Locals("allowed", true)

			return c.Next()
		}
		return fiber.ErrUpgradeRequired
	})

	app.Get("/ws/terminal", websocket.New(h.HandleWebSocket))
}

// HandleWebSocket 处理 WebSocket 连接
func (h *TerminalHandler) HandleWebSocket(c *websocket.Conn) {
	defer c.Close()

	// 二次检查（防止绕过中间件）
	allowed, ok := c.Locals("allowed").(bool)
	if !ok || !allowed {
		c.WriteMessage(websocket.TextMessage, []byte("Unauthorized"))
		return
	}

	// 创建 PTY
	cmd := exec.Command("/bin/bash")
	cmd.Env = append(os.Environ(),
		"TERM=xterm-256color",
		"LANG=en_US.UTF-8",
		"LC_ALL=en_US.UTF-8",
	)

	ptmx, err := pty.Start(cmd)
	if err != nil {
		c.WriteMessage(websocket.TextMessage, []byte("Error: "+err.Error()))
		return
	}
	defer func() {
		cmd.Process.Kill()
		ptmx.Close()
	}()

	// 设置初始窗口大小
	setWinsize(ptmx, 80, 24)

	// 读取 PTY 输出并发送到 WebSocket
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := ptmx.Read(buf)
			if err != nil {
				if err != io.EOF {
					c.WriteMessage(websocket.TextMessage, []byte("\r\n[连接已断开]\r\n"))
				}
				c.Close()
				return
			}
			if n > 0 {
				if err := c.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
					return
				}
			}
		}
	}()

	// 从 WebSocket 读取并写入 PTY
	for {
		msgType, msg, err := c.ReadMessage()
		if err != nil {
			break
		}

		switch msgType {
		case websocket.TextMessage, websocket.BinaryMessage:
			// 检查是否是调整窗口大小的消息
			if len(msg) > 0 && msg[0] == 1 {
				// 格式: [1, cols高字节, cols低字节, rows高字节, rows低字节]
				if len(msg) >= 5 {
					cols := uint16(msg[1])<<8 | uint16(msg[2])
					rows := uint16(msg[3])<<8 | uint16(msg[4])
					setWinsize(ptmx, cols, rows)
				}
			} else {
				// 普通输入
				ptmx.Write(msg)
			}
		}
	}
}

// setWinsize 设置终端窗口大小
func setWinsize(f *os.File, cols, rows uint16) {
	ws := struct {
		Rows uint16
		Cols uint16
		X    uint16
		Y    uint16
	}{
		Rows: rows,
		Cols: cols,
	}
	syscall.Syscall(
		syscall.SYS_IOCTL,
		f.Fd(),
		syscall.TIOCSWINSZ,
		uintptr(unsafe.Pointer(&ws)),
	)
}

// ExecuteCommand 执行单个命令 (非交互式)
func (h *TerminalHandler) ExecuteCommand(c *fiber.Ctx) error {
	var req struct {
		Command string `json:"command"`
		Timeout int    `json:"timeout"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if req.Command == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "命令不能为空"})
	}

	// 禁止危险命令
	dangerousCommands := []string{"rm -rf /", "mkfs", "> /dev/sda", "dd if=", ":(){:|:&};:"}
	for _, dc := range dangerousCommands {
		if len(req.Command) >= len(dc) && req.Command[:len(dc)] == dc {
			return c.Status(403).JSON(fiber.Map{"status": false, "error": "禁止执行危险命令"})
		}
	}

	cmd := exec.Command("bash", "-c", req.Command)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if err := cmd.Start(); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	var output string
	scanner := bufio.NewScanner(io.MultiReader(stdout, stderr))
	for scanner.Scan() {
		output += scanner.Text() + "\n"
	}

	err = cmd.Wait()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		}
	}

	return c.JSON(fiber.Map{
		"status":    true,
		"output":    output,
		"exit_code": exitCode,
	})
}
