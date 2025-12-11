package main

import (
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/filesystem"
	"github.com/gofiber/fiber/v2/middleware/logger"

	"site_manager_panel/config"
	"site_manager_panel/internal/auth"
	"site_manager_panel/internal/models"
	"site_manager_panel/internal/site"
	"site_manager_panel/internal/system"
)

//go:embed web/dist/*
var webFS embed.FS

func main() {
	port := flag.Int("port", 8888, "Server port")
	flag.Parse()

	// 加载配置
	cfg := config.Load()

	// 从配置初始化 JWT 密钥
	auth.SetJWTSecret(cfg.JWTSecret)

	// 初始化数据库
	if err := models.InitDB(cfg.DataDir); err != nil {
		log.Fatalf("Failed to init database: %v", err)
	}

	// 创建 Fiber 应用
	app := fiber.New(fiber.Config{
		AppName: "Site Manager Panel",
	})

	// 中间件
	app.Use(logger.New())

	// CORS 配置 - 生产环境应限制来源
	allowedOrigins := os.Getenv("CORS_ORIGINS")
	if allowedOrigins == "" {
		// 默认允许所有来源 (开发模式)
		// 生产环境应设置 CORS_ORIGINS 环境变量，如: CORS_ORIGINS="https://example.com,https://admin.example.com"
		allowedOrigins = "*"
	}
	app.Use(cors.New(cors.Config{
		AllowOrigins:     allowedOrigins,
		AllowHeaders:     "Origin, Content-Type, Accept, Authorization",
		AllowMethods:     "GET, POST, PUT, DELETE, OPTIONS",
		AllowCredentials: allowedOrigins != "*", // 通配符模式不能开启 credentials
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

	// 静态文件 (Vue 前端)
	webDist, err := fs.Sub(webFS, "web/dist")
	if err != nil {
		log.Printf("No embedded web files, serving from filesystem")
		app.Static("/", "./web/dist")
	} else {
		app.Use("/", filesystem.New(filesystem.Config{
			Root:         http.FS(webDist),
			Browse:       false,
			Index:        "index.html",
			NotFoundFile: "index.html",
		}))
	}

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
