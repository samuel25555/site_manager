package system

import (
	"os/exec"
	"runtime"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type SystemStatus struct {
	CPU     CPUInfo    `json:"cpu"`
	Memory  MemoryInfo `json:"memory"`
	Disk    DiskInfo   `json:"disk"`
	Uptime  string     `json:"uptime"`
	OS      string     `json:"os"`
}

type CPUInfo struct {
	Cores int     `json:"cores"`
	Usage float64 `json:"usage"`
}

type MemoryInfo struct {
	Total   uint64  `json:"total"`
	Used    uint64  `json:"used"`
	Free    uint64  `json:"free"`
	Percent float64 `json:"percent"`
}

type DiskInfo struct {
	Total   uint64  `json:"total"`
	Used    uint64  `json:"used"`
	Free    uint64  `json:"free"`
	Percent float64 `json:"percent"`
}

func GetStatus(c *fiber.Ctx) error {
	status := SystemStatus{
		OS:     runtime.GOOS,
		CPU:    getCPUInfo(),
		Memory: getMemoryInfo(),
		Disk:   getDiskInfo(),
		Uptime: getUptime(),
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   status,
	})
}

func getCPUInfo() CPUInfo {
	info := CPUInfo{
		Cores: runtime.NumCPU(),
	}

	// 简单的 CPU 使用率（使用 /proc/loadavg）
	out, err := exec.Command("cat", "/proc/loadavg").Output()
	if err == nil {
		fields := strings.Fields(string(out))
		if len(fields) > 0 {
			load, _ := strconv.ParseFloat(fields[0], 64)
			// 转换为百分比（粗略估计）
			info.Usage = (load / float64(info.Cores)) * 100
			if info.Usage > 100 {
				info.Usage = 100
			}
		}
	}

	return info
}

func getMemoryInfo() MemoryInfo {
	info := MemoryInfo{}

	out, err := exec.Command("sh", "-c", "free -b | grep Mem").Output()
	if err == nil {
		fields := strings.Fields(string(out))
		if len(fields) >= 3 {
			info.Total, _ = strconv.ParseUint(fields[1], 10, 64)
			info.Used, _ = strconv.ParseUint(fields[2], 10, 64)
			info.Free = info.Total - info.Used
			if info.Total > 0 {
				info.Percent = float64(info.Used) / float64(info.Total) * 100
			}
		}
	}

	return info
}

func getDiskInfo() DiskInfo {
	info := DiskInfo{}

	out, err := exec.Command("sh", "-c", "df -B1 / | tail -1").Output()
	if err == nil {
		fields := strings.Fields(string(out))
		if len(fields) >= 4 {
			info.Total, _ = strconv.ParseUint(fields[1], 10, 64)
			info.Used, _ = strconv.ParseUint(fields[2], 10, 64)
			info.Free, _ = strconv.ParseUint(fields[3], 10, 64)
			if info.Total > 0 {
				info.Percent = float64(info.Used) / float64(info.Total) * 100
			}
		}
	}

	return info
}

func getUptime() string {
	out, err := exec.Command("uptime", "-p").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

type ServiceStatus struct {
	Name   string `json:"name"`
	Status string `json:"status"`
	Active bool   `json:"active"`
}

func GetServices(c *fiber.Ctx) error {
	services := []ServiceStatus{
		checkService("nginx"),
		checkService("php8.3-fpm"),
		checkService("supervisor"),
	}

	return c.JSON(fiber.Map{
		"status": true,
		"data":   services,
	})
}

func checkService(name string) ServiceStatus {
	status := ServiceStatus{Name: name}

	out, err := exec.Command("systemctl", "is-active", name).Output()
	if err == nil {
		status.Status = strings.TrimSpace(string(out))
		status.Active = status.Status == "active"
	} else {
		status.Status = "inactive"
		status.Active = false
	}

	return status
}
