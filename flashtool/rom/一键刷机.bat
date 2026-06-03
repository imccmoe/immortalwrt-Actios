@echo off
chcp 65001 >nul
color 0A
echo ============================================
echo        OpenStick 一键刷机工具
echo ============================================
echo.
echo  如需下载对应设备的 OpenWrt 固件包，请访问：
echo  https://github.com/x7780/immortalwrt-Actios
echo.
echo ============================================
echo.
echo [1/4] 正在检测设备连接...
echo.

:check_device
adb devices | findstr /R "device$" >nul 2>&1
if not errorlevel 1 (
    echo  [OK] 检测到 ADB 设备，正在重启进入 Bootloader 模式...
    adb reboot bootloader
    timeout /NOBREAK /T 5 >nul
    goto fastboot_ready
)

fastboot devices | findstr /R "." >nul 2>&1
if not errorlevel 1 (
    echo  [OK] 检测到设备已在 Fastboot 模式，直接继续...
    goto fastboot_ready
)

echo  [!] 未检测到设备！
echo(
echo  请插入高通410随身WiFi设备，并确认：
echo    - USB 数据线已正确连接
echo    - 设备已开机或已进入 Fastboot 模式
echo    - 已安装 ADB / Fastboot 驱动
echo(
echo  插入后按任意键重新检测...
pause >nul
goto check_device

:fastboot_ready

echo.
echo [2/4] 正在刷入 lk2nd 引导...
fastboot erase boot
fastboot flash boot lk2nd.img
echo  lk2nd 刷入完成，正在重启...
fastboot reboot
echo.
echo  等待设备重新进入 fastboot 模式...
timeout /NOBREAK /T 3 >nul
echo  按任意键继续...
pause >nul

echo.
echo [3/4] 正在备份基带分区...
fastboot oem dump fsc && fastboot get_staged fsc.bin
fastboot oem dump fsg && fastboot get_staged fsg.bin
fastboot oem dump modemst1 && fastboot get_staged modemst1.bin
fastboot oem dump modemst2 && fastboot get_staged modemst2.bin
echo  基带分区备份完成
echo.
echo  正在刷入底层固件...
fastboot erase lk2nd
fastboot erase boot
fastboot reboot bootloader
echo.
echo  等待设备重新进入 fastboot 模式...
timeout /NOBREAK /T 3 >nul
echo  按任意键继续...
pause >nul

fastboot flash partition gpt_both0.bin
fastboot flash hyp hyp.mbn
fastboot flash rpm rpm.mbn
fastboot flash sbl1 sbl1.mbn
fastboot flash tz tz.mbn
fastboot flash fsc fsc.bin
fastboot flash fsg fsg.bin
fastboot flash modemst1 modemst1.bin
fastboot flash modemst2 modemst2.bin
fastboot flash aboot aboot.bin
fastboot flash cdt sbc_1.0_8016.bin
fastboot erase boot
fastboot erase rootfs
echo  底层固件刷入完成，正在重启...
fastboot reboot
echo.
echo  等待设备重新进入 fastboot 模式...
timeout /NOBREAK /T 3 >nul
echo  按任意键继续...
pause >nul

echo.
echo [4/4] 正在刷入系统镜像...
fastboot flash boot boot.img
fastboot -S 200m flash rootfs system.img
echo  系统镜像刷入完成，正在重启...
fastboot reboot

echo.
echo ============================================
echo           刷机完成！
echo.
echo  如需更换更好玩 OpenWrt ，请访问：
echo  https://github.com/x7780/immortalwrt-Actios
echo  下载对应设备的固件包后替换 rootfs.img 重新刷入
echo ============================================
echo.
echo  按任意键退出...
pause >nul
