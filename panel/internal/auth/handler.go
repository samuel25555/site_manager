package auth

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"

	"site_manager_panel/internal/models"
)

var jwtSecret []byte

func init() {
	// 优先从环境变量读取
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		// 如果没有设置，生成随机密钥（每次重启会变化，强制用户设置）
		randomBytes := make([]byte, 32)
		if _, err := rand.Read(randomBytes); err != nil {
			// 最后的后备方案
			secret = "fallback_secret_please_set_JWT_SECRET_env"
		} else {
			secret = hex.EncodeToString(randomBytes)
		}
		// 警告日志
		println("[WARN] JWT_SECRET not set, using random secret. Tokens will be invalidated on restart!")
	}
	jwtSecret = []byte(secret)
}

// SetJWTSecret 允许从配置中设置密钥
func SetJWTSecret(secret string) {
	if secret != "" {
		jwtSecret = []byte(secret)
	}
}

type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type LoginResponse struct {
	Token     string       `json:"token"`
	ExpiresAt int64        `json:"expires_at"`
	User      *models.User `json:"user"`
}

func Login(c *fiber.Ctx) error {
	var req LoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request body",
		})
	}

	if req.Username == "" || req.Password == "" {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Username and password are required",
		})
	}

	user, err := models.GetUserByUsername(req.Username)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Internal server error",
		})
	}

	if user == nil || !user.CheckPassword(req.Password) {
		return c.Status(401).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid username or password",
		})
	}

	// 生成 JWT
	expiresAt := time.Now().Add(24 * time.Hour)
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id":  user.ID,
		"username": user.Username,
		"exp":      expiresAt.Unix(),
	})

	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to generate token",
		})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data": LoginResponse{
			Token:     tokenString,
			ExpiresAt: expiresAt.Unix(),
			User:      user,
		},
	})
}

func Me(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(int64)

	user, err := models.GetUserByID(userID)
	if err != nil || user == nil {
		return c.Status(401).JSON(fiber.Map{
			"status":  false,
			"message": "User not found",
		})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   user,
	})
}

func Logout(c *fiber.Ctx) error {
	// JWT 是无状态的，客户端删除 token 即可
	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Logged out successfully",
	})
}

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password"`
	NewPassword string `json:"new_password"`
}

func ChangePassword(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(int64)

	var req ChangePasswordRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Invalid request body",
		})
	}

	if req.OldPassword == "" || req.NewPassword == "" {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Old and new passwords are required",
		})
	}

	if len(req.NewPassword) < 6 {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Password must be at least 6 characters",
		})
	}

	user, err := models.GetUserByID(userID)
	if err != nil || user == nil {
		return c.Status(401).JSON(fiber.Map{
			"status":  false,
			"message": "User not found",
		})
	}

	if !user.CheckPassword(req.OldPassword) {
		return c.Status(400).JSON(fiber.Map{
			"status":  false,
			"message": "Old password is incorrect",
		})
	}

	if err := user.UpdatePassword(req.NewPassword); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"status":  false,
			"message": "Failed to update password",
		})
	}

	return c.JSON(fiber.Map{
		"status":  true,
		"message": "Password changed successfully",
	})
}
