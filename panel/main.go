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
	"site_manager_panel/internal/cron"
	"site_manager_panel/internal/files"
	"site_manager_panel/internal/firewall"
	"site_manager_panel/internal/logs"
	"site_manager_panel/internal/models"
	"site_manager_panel/internal/site"
	"site_manager_panel/internal/software"
	"site_manager_panel/internal/system"
	"site_manager_panel/internal/terminal"
)

func main() {
	port := flag.Int("port", 8888, "Server port")
	flag.Parse()

	cfg := config.Load()
	auth.SetJWTSecret(cfg.JWTSecret)
	terminal.SetJWTSecret(cfg.JWTSecret)

	if err := models.InitDB(cfg.DataDir); err != nil {
		log.Fatalf("Failed to init database: %v", err)
	}

	app := fiber.New(fiber.Config{
		AppName:      "Site Manager Panel",
		BodyLimit:    100 * 1024 * 1024,
		ServerHeader: "Site Manager",
	})

	app.Use(logger.New())

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

	api := app.Group("/api")
	authRoutes := api.Group("/auth")
	authRoutes.Post("/login", auth.Login)

	protected := api.Group("", auth.JWTMiddleware())
	protected.Get("/auth/me", auth.Me)
	protected.Post("/auth/logout", auth.Logout)
	protected.Post("/auth/password", auth.ChangePassword)

	protected.Get("/system/status", system.GetStatus)
	protected.Get("/system/services", system.GetServices)

	protected.Get("/sites", site.List)
	protected.Post("/sites", site.Create)
	protected.Get("/sites/:domain", site.Info)
	protected.Delete("/sites/:domain", site.Delete)
	protected.Post("/sites/:domain/enable", site.Enable)
	protected.Post("/sites/:domain/disable", site.Disable)
	protected.Post("/sites/:domain/backup", site.Backup)
	protected.Get("/sites/:domain/nginx", site.GetNginxConfig)
	protected.Put("/sites/:domain/nginx", site.SaveNginxConfig)
	protected.Get("/sites/:domain/logs", site.GetLogs)
	protected.Post("/sites/:domain/ssl", site.RequestSSL)
	protected.Post("/sites/:domain/ssl/renew", site.RenewSSL)

	protected.Get("/software", software.List)
	protected.Get("/software/:name/status", software.Status)
	protected.Post("/software/:name/start", software.Start)
	protected.Post("/software/:name/stop", software.Stop)
	protected.Post("/software/:name/restart", software.Restart)
	protected.Post("/software/:name/reload", software.Reload)

	protected.Get("/logs", logs.List)
	protected.Get("/logs/read", logs.Read)
	protected.Get("/logs/search", logs.Search)
	protected.Post("/logs/clear", logs.Clear)

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

	termHandler := terminal.NewTerminalHandler()
	protected.Post("/terminal/exec", termHandler.ExecuteCommand)
	termHandler.RegisterRoutes(app)

	firewallHandler := firewall.NewFirewallHandler()
	firewallHandler.RegisterRoutes(protected)

	cronHandler := cron.NewCronHandler()
	cronHandler.RegisterRoutes(protected)

	app.Static("/", "./web/dist", fiber.Static{
		Index:         "index.html",
		CacheDuration: 0,
	})

	app.Get("/*", func(c *fiber.Ctx) error {
		return c.SendFile("./web/dist/index.html")
	})

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Starting server on %s", addr)

	if pwd := os.Getenv("INIT_PASSWORD"); pwd != "" {
		log.Printf("\n==================================")
		log.Printf("Initial admin password: %s", pwd)
		log.Printf("==================================\n")
	}

	if os.Getenv("JWT_SECRET") == "" {
		log.Printf("[WARN] JWT_SECRET environment variable not set!")
	}

	if err := app.Listen(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
