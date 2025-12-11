package auth

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
)

func TestSetJWTSecret(t *testing.T) {
	// 保存原始密钥
	originalSecret := string(jwtSecret)
	defer func() { jwtSecret = []byte(originalSecret) }()

	// 测试设置 JWT 密钥
	SetJWTSecret("test_secret_123")
	if string(jwtSecret) != "test_secret_123" {
		t.Error("SetJWTSecret failed to set the secret")
	}

	// 空字符串不应该修改密钥
	SetJWTSecret("")
	if string(jwtSecret) != "test_secret_123" {
		t.Error("SetJWTSecret should not set empty secret")
	}
}

func TestLoginRequestValidation(t *testing.T) {
	app := fiber.New()
	app.Post("/login", Login)

	tests := []struct {
		name       string
		body       map[string]string
		wantStatus int
	}{
		{
			name:       "Empty body",
			body:       map[string]string{},
			wantStatus: 400,
		},
		{
			name:       "Missing password",
			body:       map[string]string{"username": "admin"},
			wantStatus: 400,
		},
		{
			name:       "Missing username",
			body:       map[string]string{"password": "secret"},
			wantStatus: 400,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			bodyBytes, _ := json.Marshal(tt.body)
			req := httptest.NewRequest("POST", "/login", bytes.NewReader(bodyBytes))
			req.Header.Set("Content-Type", "application/json")

			resp, err := app.Test(req)
			if err != nil {
				t.Fatalf("Request failed: %v", err)
			}

			if resp.StatusCode != tt.wantStatus {
				body, _ := io.ReadAll(resp.Body)
				t.Errorf("Expected status %d, got %d. Body: %s", tt.wantStatus, resp.StatusCode, string(body))
			}
		})
	}
}

func TestJWTMiddleware(t *testing.T) {
	app := fiber.New()
	app.Use(JWTMiddleware())
	app.Get("/protected", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": true})
	})

	tests := []struct {
		name       string
		authHeader string
		wantStatus int
	}{
		{
			name:       "No auth header",
			authHeader: "",
			wantStatus: 401,
		},
		{
			name:       "Invalid format - no Bearer",
			authHeader: "InvalidToken123",
			wantStatus: 401,
		},
		{
			name:       "Invalid format - wrong prefix",
			authHeader: "Basic abc123",
			wantStatus: 401,
		},
		{
			name:       "Invalid token",
			authHeader: "Bearer invalid.token.here",
			wantStatus: 401,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/protected", nil)
			if tt.authHeader != "" {
				req.Header.Set("Authorization", tt.authHeader)
			}

			resp, err := app.Test(req)
			if err != nil {
				t.Fatalf("Request failed: %v", err)
			}

			if resp.StatusCode != tt.wantStatus {
				body, _ := io.ReadAll(resp.Body)
				t.Errorf("Expected status %d, got %d. Body: %s", tt.wantStatus, resp.StatusCode, string(body))
			}
		})
	}
}

func TestChangePasswordValidation(t *testing.T) {
	app := fiber.New()

	// 模拟已认证的中间件
	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", int64(1))
		return c.Next()
	})
	app.Post("/password", ChangePassword)

	tests := []struct {
		name       string
		body       map[string]string
		wantStatus int
	}{
		{
			name:       "Empty body",
			body:       map[string]string{},
			wantStatus: 400,
		},
		{
			name:       "Missing new password",
			body:       map[string]string{"old_password": "old123"},
			wantStatus: 400,
		},
		{
			name:       "Password too short",
			body:       map[string]string{"old_password": "old123", "new_password": "12345"},
			wantStatus: 400,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			bodyBytes, _ := json.Marshal(tt.body)
			req := httptest.NewRequest("POST", "/password", bytes.NewReader(bodyBytes))
			req.Header.Set("Content-Type", "application/json")

			resp, err := app.Test(req)
			if err != nil {
				t.Fatalf("Request failed: %v", err)
			}

			if resp.StatusCode != tt.wantStatus {
				body, _ := io.ReadAll(resp.Body)
				t.Errorf("Expected status %d, got %d. Body: %s", tt.wantStatus, resp.StatusCode, string(body))
			}
		})
	}
}
