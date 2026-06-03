//go:build windows

// Package winenv 负责 Windows 环境检查和 usbdk 驱动静默安装。
// usbdk 让 libusb 可以绕过 Windows 已加载的驱动直接访问 USB 设备，
// 无需用户手动安装或替换任何驱动。
package winenv

import (
	"embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// usbdk 安装包内嵌进二进制，运行时释放到临时目录
//
//go:embed usbdk/*.msi
var usbdkFS embed.FS

// CheckAndInstall 检查 usbdk 是否已安装，未安装则静默安装。
// 返回每个步骤的状态，通过 progress 回调实时输出。
func CheckAndInstall(progress func(msg string, ok bool)) error {
	progress("操作系统："+osInfo(), true)
	progress("CPU架构："+runtime.GOARCH, true)

	progress("检查 USB 驱动环境...", true)
	time.Sleep(300 * time.Millisecond)

	if isUsbdkInstalled() {
		progress("USB驱动：已就绪", true)
		return nil
	}

	progress("USB驱动：未安装，正在自动安装...", true)

	if err := installUsbdk(); err != nil {
		return fmt.Errorf("USB驱动安装失败：%w", err)
	}

	// 等待服务启动
	time.Sleep(1 * time.Second)

	if !isUsbdkInstalled() {
		return fmt.Errorf("USB驱动安装后验证失败，请重启程序重试")
	}

	progress("USB驱动：安装完成", true)
	return nil
}

// isUsbdkInstalled 检查 usbdk 服务是否存在
func isUsbdkInstalled() bool {
	out, err := exec.Command("sc", "query", "UsbDk").Output()
	if err != nil {
		// sc query 找不到服务时返回非0退出码
		return false
	}
	// 服务存在时输出里会有 SERVICE_NAME
	return strings.Contains(string(out), "SERVICE_NAME")
}

// installUsbdk 释放内嵌的 msi 到临时目录并静默安装
func installUsbdk() error {
	tmpDir, err := os.MkdirTemp("", "flashtool_usbdk_*")
	if err != nil {
		return fmt.Errorf("创建临时目录失败：%w", err)
	}
	defer os.RemoveAll(tmpDir)

	// 根据系统架构选择对应的 msi
	var msiName string
	switch runtime.GOARCH {
	case "amd64":
		msiName = "usbdk_x64.msi"
	case "386":
		msiName = "usbdk_x86.msi"
	default:
		msiName = "usbdk_x64.msi"
	}

	// 从内嵌 FS 读取 msi
	data, err := usbdkFS.ReadFile("usbdk/" + msiName)
	if err != nil {
		return fmt.Errorf("内嵌驱动文件读取失败（%s）：%w", msiName, err)
	}

	// 写到临时目录
	msiPath := filepath.Join(tmpDir, msiName)
	if err := os.WriteFile(msiPath, data, 0644); err != nil {
		return fmt.Errorf("写入临时文件失败：%w", err)
	}

	// 静默安装：/quiet /norestart
	cmd := exec.Command("msiexec", "/i", msiPath, "/quiet", "/norestart")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("msiexec 安装失败：%w", err)
	}

	return nil
}

func osInfo() string {
	out, err := exec.Command("cmd", "/c", "ver").Output()
	if err != nil {
		return "Windows"
	}
	return strings.TrimSpace(string(out))
}
