package files

import (
	"archive/zip"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

// FileInfo 文件信息
type FileInfo struct {
	Name       string    `json:"name"`
	Path       string    `json:"path"`
	Size       int64     `json:"size"`
	Mode       string    `json:"mode"`
	ModTime    time.Time `json:"mod_time"`
	IsDir      bool      `json:"is_dir"`
	IsSymlink  bool      `json:"is_symlink"`
	LinkTarget string    `json:"link_target,omitempty"`
}

// ListRequest 列表请求
type ListRequest struct {
	Path       string `json:"path" query:"path"`
	ShowHidden bool   `json:"show_hidden" query:"show_hidden"`
}

// ListResponse 列表响应
type ListResponse struct {
	Path    string     `json:"path"`
	Files   []FileInfo `json:"files"`
	Parent  string     `json:"parent"`
	CanEdit bool       `json:"can_edit"`
}

// FileHandler 文件管理处理器
type FileHandler struct {
	baseDir string
}

// NewFileHandler 创建处理器
func NewFileHandler(baseDir string) *FileHandler {
	return &FileHandler{baseDir: baseDir}
}

// RegisterRoutes 注册路由
func (h *FileHandler) RegisterRoutes(app *fiber.App) {
	files := app.Group("/api/files")
	files.Get("/list", h.List)
	files.Get("/read", h.Read)
	files.Post("/save", h.Save)
	files.Post("/create", h.Create)
	files.Post("/rename", h.Rename)
	files.Post("/delete", h.Delete)
	files.Post("/copy", h.Copy)
	files.Post("/move", h.Move)
	files.Post("/upload", h.Upload)
	files.Get("/download", h.Download)
	files.Post("/compress", h.Compress)
	files.Post("/extract", h.Extract)
	files.Post("/chmod", h.Chmod)
	files.Get("/search", h.Search)
}

// 验证路径安全
func (h *FileHandler) validatePath(path string) (string, error) {
	// 清理路径
	path = filepath.Clean(path)

	// 默认路径
	if path == "" || path == "." {
		path = h.baseDir
	}

	// 确保绝对路径
	if !filepath.IsAbs(path) {
		path = filepath.Join(h.baseDir, path)
	}

	// 检查是否在允许的目录内
	// 只允许访问 /www, /etc, /var/log 等
	allowedPaths := []string{"/www", "/srv", "/home", "/var/log", "/etc/nginx", "/etc/php", "/tmp"}
	allowed := false
	for _, ap := range allowedPaths {
		if strings.HasPrefix(path, ap) {
			allowed = true
			break
		}
	}

	if !allowed {
		return "", fmt.Errorf("禁止访问该路径: %s", path)
	}

	return path, nil
}

// List 列出目录内容
func (h *FileHandler) List(c *fiber.Ctx) error {
	var req ListRequest
	if err := c.QueryParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	path, err := h.validatePath(req.Path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	// 检查目录是否存在
	info, err := os.Stat(path)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"status": false, "error": "路径不存在"})
	}

	if !info.IsDir() {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "不是目录"})
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	files := make([]FileInfo, 0)
	for _, entry := range entries {
		name := entry.Name()

		// 隐藏文件过滤
		if !req.ShowHidden && strings.HasPrefix(name, ".") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		fileInfo := FileInfo{
			Name:    name,
			Path:    filepath.Join(path, name),
			Size:    info.Size(),
			Mode:    info.Mode().String(),
			ModTime: info.ModTime(),
			IsDir:   entry.IsDir(),
		}

		// 检查符号链接
		if info.Mode()&os.ModeSymlink != 0 {
			fileInfo.IsSymlink = true
			target, _ := os.Readlink(filepath.Join(path, name))
			fileInfo.LinkTarget = target
		}

		files = append(files, fileInfo)
	}

	// 排序: 目录在前，然后按名称
	sort.Slice(files, func(i, j int) bool {
		if files[i].IsDir != files[j].IsDir {
			return files[i].IsDir
		}
		return strings.ToLower(files[i].Name) < strings.ToLower(files[j].Name)
	})

	// 计算父目录
	parent := filepath.Dir(path)
	if parent == path {
		parent = ""
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data": ListResponse{
			Path:    path,
			Files:   files,
			Parent:  parent,
			CanEdit: true,
		},
	})
}

// Read 读取文件内容
func (h *FileHandler) Read(c *fiber.Ctx) error {
	path := c.Query("path")
	path, err := h.validatePath(path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	info, err := os.Stat(path)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"status": false, "error": "文件不存在"})
	}

	if info.IsDir() {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "不是文件"})
	}

	// 限制文件大小 (10MB)
	if info.Size() > 10*1024*1024 {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "文件过大，无法在线编辑"})
	}

	content, err := os.ReadFile(path)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data": fiber.Map{
			"path":    path,
			"content": string(content),
			"size":    info.Size(),
			"mode":    info.Mode().String(),
		},
	})
}

// Save 保存文件内容
func (h *FileHandler) Save(c *fiber.Ctx) error {
	var req struct {
		Path    string `json:"path"`
		Content string `json:"content"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	path, err := h.validatePath(req.Path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	// 创建备份
	if _, err := os.Stat(path); err == nil {
		backupPath := path + ".bak"
		os.Rename(path, backupPath)
		defer os.Remove(backupPath)
	}

	if err := os.WriteFile(path, []byte(req.Content), 0644); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	return c.JSON(fiber.Map{"status": true, "message": "文件保存成功"})
}

// Create 创建文件/目录
func (h *FileHandler) Create(c *fiber.Ctx) error {
	var req struct {
		Path  string `json:"path"`
		IsDir bool   `json:"is_dir"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	path, err := h.validatePath(req.Path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if _, err := os.Stat(path); err == nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "文件已存在"})
	}

	if req.IsDir {
		if err := os.MkdirAll(path, 0755); err != nil {
			return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
		}
	} else {
		// 确保父目录存在
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
		}
		if err := os.WriteFile(path, []byte{}, 0644); err != nil {
			return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
		}
	}

	return c.JSON(fiber.Map{"status": true, "message": "创建成功"})
}

// Rename 重命名
func (h *FileHandler) Rename(c *fiber.Ctx) error {
	var req struct {
		OldPath string `json:"old_path"`
		NewPath string `json:"new_path"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	oldPath, err := h.validatePath(req.OldPath)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	newPath, err := h.validatePath(req.NewPath)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if err := os.Rename(oldPath, newPath); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	return c.JSON(fiber.Map{"status": true, "message": "重命名成功"})
}

// Delete 删除文件/目录
func (h *FileHandler) Delete(c *fiber.Ctx) error {
	var req struct {
		Paths []string `json:"paths"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	for _, p := range req.Paths {
		path, err := h.validatePath(p)
		if err != nil {
			continue
		}

		if err := os.RemoveAll(path); err != nil {
			return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
		}
	}

	return c.JSON(fiber.Map{"status": true, "message": "删除成功"})
}

// Copy 复制
func (h *FileHandler) Copy(c *fiber.Ctx) error {
	var req struct {
		Source string `json:"source"`
		Dest   string `json:"dest"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	src, err := h.validatePath(req.Source)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	dst, err := h.validatePath(req.Dest)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if err := copyPath(src, dst); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	return c.JSON(fiber.Map{"status": true, "message": "复制成功"})
}

// Move 移动
func (h *FileHandler) Move(c *fiber.Ctx) error {
	var req struct {
		Source string `json:"source"`
		Dest   string `json:"dest"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	src, err := h.validatePath(req.Source)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	dst, err := h.validatePath(req.Dest)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if err := os.Rename(src, dst); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	return c.JSON(fiber.Map{"status": true, "message": "移动成功"})
}

// Upload 上传文件
func (h *FileHandler) Upload(c *fiber.Ctx) error {
	path := c.FormValue("path")
	path, err := h.validatePath(path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	form, err := c.MultipartForm()
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	files := form.File["files"]
	for _, file := range files {
		dst := filepath.Join(path, file.Filename)
		if err := c.SaveFile(file, dst); err != nil {
			return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
		}
	}

	return c.JSON(fiber.Map{"status": true, "message": fmt.Sprintf("上传成功 %d 个文件", len(files))})
}

// Download 下载文件
func (h *FileHandler) Download(c *fiber.Ctx) error {
	path := c.Query("path")
	path, err := h.validatePath(path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	return c.Download(path)
}

// Compress 压缩
func (h *FileHandler) Compress(c *fiber.Ctx) error {
	var req struct {
		Paths  []string `json:"paths"`
		Target string   `json:"target"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	target, err := h.validatePath(req.Target)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	// 创建 zip 文件
	zipFile, err := os.Create(target)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}
	defer zipFile.Close()

	zipWriter := zip.NewWriter(zipFile)
	defer zipWriter.Close()

	for _, p := range req.Paths {
		srcPath, err := h.validatePath(p)
		if err != nil {
			continue
		}

		filepath.Walk(srcPath, func(path string, info fs.FileInfo, err error) error {
			if err != nil {
				return err
			}

			relPath, _ := filepath.Rel(filepath.Dir(srcPath), path)
			if info.IsDir() {
				_, err = zipWriter.Create(relPath + "/")
				return err
			}

			writer, err := zipWriter.Create(relPath)
			if err != nil {
				return err
			}

			file, err := os.Open(path)
			if err != nil {
				return err
			}
			defer file.Close()

			_, err = io.Copy(writer, file)
			return err
		})
	}

	return c.JSON(fiber.Map{"status": true, "message": "压缩成功"})
}

// Extract 解压
func (h *FileHandler) Extract(c *fiber.Ctx) error {
	var req struct {
		Source string `json:"source"`
		Target string `json:"target"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	src, err := h.validatePath(req.Source)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	target, err := h.validatePath(req.Target)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	reader, err := zip.OpenReader(src)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}
	defer reader.Close()

	for _, file := range reader.File {
		fpath := filepath.Join(target, file.Name)

		if file.FileInfo().IsDir() {
			os.MkdirAll(fpath, 0755)
			continue
		}

		os.MkdirAll(filepath.Dir(fpath), 0755)

		dstFile, err := os.Create(fpath)
		if err != nil {
			continue
		}

		srcFile, err := file.Open()
		if err != nil {
			dstFile.Close()
			continue
		}

		io.Copy(dstFile, srcFile)
		dstFile.Close()
		srcFile.Close()
	}

	return c.JSON(fiber.Map{"status": true, "message": "解压成功"})
}

// Chmod 修改权限
func (h *FileHandler) Chmod(c *fiber.Ctx) error {
	var req struct {
		Path string      `json:"path"`
		Mode os.FileMode `json:"mode"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	path, err := h.validatePath(req.Path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if err := os.Chmod(path, req.Mode); err != nil {
		return c.Status(500).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	return c.JSON(fiber.Map{"status": true, "message": "权限修改成功"})
}

// Search 搜索文件
func (h *FileHandler) Search(c *fiber.Ctx) error {
	path := c.Query("path")
	keyword := c.Query("keyword")

	path, err := h.validatePath(path)
	if err != nil {
		return c.Status(403).JSON(fiber.Map{"status": false, "error": err.Error()})
	}

	if keyword == "" {
		return c.Status(400).JSON(fiber.Map{"status": false, "error": "请输入搜索关键词"})
	}

	var results []FileInfo
	filepath.Walk(path, func(p string, info fs.FileInfo, err error) error {
		if err != nil {
			return nil
		}

		if strings.Contains(strings.ToLower(info.Name()), strings.ToLower(keyword)) {
			results = append(results, FileInfo{
				Name:    info.Name(),
				Path:    p,
				Size:    info.Size(),
				Mode:    info.Mode().String(),
				ModTime: info.ModTime(),
				IsDir:   info.IsDir(),
			})
		}

		// 限制结果数量
		if len(results) >= 100 {
			return filepath.SkipAll
		}

		return nil
	})

	return c.JSON(fiber.Map{
		"status": true,
		"data":   results,
	})
}

// 辅助函数: 递归复制
func copyPath(src, dst string) error {
	info, err := os.Stat(src)
	if err != nil {
		return err
	}

	if info.IsDir() {
		return copyDir(src, dst)
	}
	return copyFile(src, dst)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

func copyDir(src, dst string) error {
	if err := os.MkdirAll(dst, 0755); err != nil {
		return err
	}

	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		srcPath := filepath.Join(src, entry.Name())
		dstPath := filepath.Join(dst, entry.Name())

		if entry.IsDir() {
			if err := copyDir(srcPath, dstPath); err != nil {
				return err
			}
		} else {
			if err := copyFile(srcPath, dstPath); err != nil {
				return err
			}
		}
	}

	return nil
}
