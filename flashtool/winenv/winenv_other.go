//go:build !windows

// Package winenv 在非 Windows 系统上为空实现，无需任何驱动操作。
package winenv

// CheckAndInstall 在 Linux/macOS 上直接返回成功，无需任何驱动。
func CheckAndInstall(progress func(msg string, ok bool)) error {
	progress("操作系统：Linux/macOS，无需驱动配置", true)
	return nil
}
