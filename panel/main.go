package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"

	"site_manager_panel/config"
	"site_manager_panel/internal/auth"
	"site_manager_panel/internal/files"
	"site_manager_panel/internal/firewall"
	"site_manager_panel/internal/models"
	"site_manager_panel/internal/site"
	"site_manager_panel/internal/system"
	"site_manager_panel/internal/terminal"
)

func main() {
	port := flag.Int("port", 8888, "Server port")
	flag.Parse()

	// 加载配置
	cfg := config.Load()

	// 从配置初始化 JWT 密钥
	auth.SetJWTSecret(cfg.JWTSecret)
	terminal.SetJWTSecret(cfg.JWTSecret)

	// 初始化数据库
	if err := models.InitDB(cfg.DataDir); err != nil {
		log.Fatalf("Failed to init database: %v", err)
	}

	// 创建 Fiber 应用
	app := fiber.New(fiber.Config{
		AppName:      "Site Manager Panel",
		BodyLimit:    100 * 1024 * 1024, // 100MB for file upload
		ServerHeader: "Site Manager",
	})

	// 中间件
	app.Use(logger.New())

	// CORS 配置 - 生产环境应限制来源
	allowedOrigins := os.Getenv("CORS_ORIGINS")
	if allowedOrigins == "" {
		allowedOrigins = "*"
	}
	app.Use(cors.New(cors.Config{
		AllowOrigins:     allowedOrigins,
		AllowHeaders:     "Origin, Content-Type, Accept, Authorization",
		AllowMethods:     "GET, POST, PUT, DELETE, OPTIONS",
		AllowCredentials: allowedOrigins != "*",
	}))

	// API 路由
	api := app.Group("/api")

	// 认证路由 (无需 JWT)
	authRoutes := api.Group("/auth")
	authRoutes.Post("/login", auth.Login)

	// 需要认证的路由
	protected := api.Group("", auth.JWTMiddleware())
	protected.Get("/auth/me", auth.Me)
	protected.Post("/auth/logout", auth.Logout)
	protected.Post("/auth/password", auth.ChangePassword)

	// 系统状态
	protected.Get("/system/status", system.GetStatus)
	protected.Get("/system/services", system.GetServices)

	// 站点管理
	protected.Get("/sites", site.List)
	protected.Post("/sites", site.Create)
	protected.Get("/sites/:domain", site.Info)
	protected.Delete("/sites/:domain", site.Delete)
	protected.Post("/sites/:domain/enable", site.Enable)
	protected.Post("/sites/:domain/disable", site.Disable)
	protected.Post("/sites/:domain/backup", site.Backup)

	// 文件管理器
	fileHandler := files.NewFileHandler(cfg.BaseDir)
	filesGroup := protected.Group("/files")
	filesGroup.Get("/list", fileHandler.List)
	filesGroup.Get("/read", fileHandler.Read)
	filesGroup.Post("/save", fileHandler.Save)
	filesGroup.Post("/create", fileHandler.Create)
	filesGroup.Post("/rename", fileHandler.Rename)
	filesGroup.Post("/delete", fileHandler.Delete)
	filesGroup.Post("/copy", fileHandler.Copy)
	filesGroup.Post("/move", fileHandler.Move)
	filesGroup.Post("/upload", fileHandler.Upload)
	filesGroup.Get("/download", fileHandler.Download)
	filesGroup.Post("/compress", fileHandler.Compress)
	filesGroup.Post("/extract", fileHandler.Extract)
	filesGroup.Post("/chmod", fileHandler.Chmod)
	filesGroup.Get("/search", fileHandler.Search)

	// 终端 (非交互式命令执行)
	termHandler := terminal.NewTerminalHandler()
	protected.Post("/terminal/exec", termHandler.ExecuteCommand)

	// WebSocket 终端 (需要单独处理认证)
	termHandler.RegisterRoutes(app)

	// 防火墙管理
	firewallHandler := firewall.NewFirewallHandler()
	firewallHandler.RegisterRoutes(protected)

	// 静态文件 (Vue 前端) - 直接从文件系统提供
	app.Static("/", "./web/dist", fiber.Static{
		Index:         "index.html",
		CacheDuration: 0,
	})

	// SPA fallback - 所有未匹配的路由返回 index.html
	app.Get("/*", func(c *fiber.Ctx) error {
		return c.SendFile("./web/dist/index.html")
	})

	// 启动服务器
	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Starting server on %s", addr)

	// 首次启动提示
	if pwd := os.Getenv("INIT_PASSWORD"); pwd != "" {
		log.Printf("\n==================================")
		log.Printf("Initial admin password: %s", pwd)
		log.Printf("==================================\n")
	}

	// JWT 密钥警告
	if os.Getenv("JWT_SECRET") == "" {
		log.Printf("[WARN] JWT_SECRET environment variable not set!")
		log.Printf("[WARN] Using config default or random secret. Set JWT_SECRET for production.")
	}

	if err := app.Listen(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
