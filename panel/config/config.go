package config

import (
	"os"
	"path/filepath"
)

type Config struct {
	DataDir   string
	BaseDir   string // 网站根目录，用于文件管理器
	JWTSecret string
	SiteCLI   string
}

func Load() *Config {
	// 默认配置
	cfg := &Config{
		DataDir:   "/opt/site_manager/panel/data",
		BaseDir:   getEnv("BASE_DIR", "/www"),
		JWTSecret: getEnv("JWT_SECRET", "site_manager_panel_secret_key_change_me"),
		SiteCLI:   "/usr/local/bin/site-new",
	}

	// 确保数据目录存在
	os.MkdirAll(cfg.DataDir, 0755)

	return cfg
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func (c *Config) DBPath() string {
	return filepath.Join(c.DataDir, "panel.db")
}
