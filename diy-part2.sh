#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part2.sh
# 功能说明: OpenWrt DIY脚本第2部分（更新feeds之后）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 修改默认IP地址
#sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

# ===== 已移除的修复（上游已修复，勿恢复）=====
# 1. argon 默认主题兜底（99-argon-default + luci.themes 注册）：
#    luci feed 的 luci-theme-argon 已升级到 2.4.7-r20260824，自带
#    root/etc/uci-defaults/30_luci-theme-argon（设置 mediaurlbase 与注册主题），
#    与旧补丁功能完全一致
# 2. argon 官方源强制替换（jerrykuku git clone 覆盖 luci/smpackage feed）：
#    luci feed 版本已与 jerrykuku 官方同步（同为 2.4.7-r20260824），无需替换
# 3. argon 模板自愈（旧语法 / import 'math' 检测与拉取）：
#    2.4.7 模板已为新语法且无 math 依赖

# ===== 移除内置无线（WCN36xx/WCNSS）释放内存 =====
# 注意：这里【不能】再用 sed 改 .config。
# 工作流顺序是 diy-part2.sh -> make defconfig，defconfig 会依据
# config/<机型>.config 里的上一级符号（DEFAULT_/PACKAGE_ 原本都是 =y）
# 以及 wcnss 固件包的依赖，把 kmod-wcn36xx / kmod-qcom-rproc-wcnss 拉回 =y，
# 所以旧版的 sed 写法实际无效（固件里一直带着这两个驱动）。
# 现在直接在 config/*.config 里写 "# ... is not set"（13 个机型已全部改好），
# 以基准配置的形式存在，defconfig 便无法恢复。
# 已处理符号：kmod-wcn36xx、kmod-qcom-rproc-wcnss、openstick-*-wcnss-firmware、
#             wcnss-openstick-*-nv，以及基带残留 rmtfs、kmod-bam-dmux、
#             kmod-qcom-rproc-modem、kmod-rpmsg-wwan-ctrl
# diy-part1 仍负责从 target/linux/msm89xx 的 DEFAULT_PACKAGES / DEVICE_PACKAGES 摘除

# ===== 网络性能调优：确保 BBR 拥塞控制可用 =====
sed -i 's/^# CONFIG_PACKAGE_kmod-tcp-bbr is not set$/CONFIG_PACKAGE_kmod-tcp-bbr=y/' .config
grep -q '^CONFIG_PACKAGE_kmod-tcp-bbr=y' .config || echo 'CONFIG_PACKAGE_kmod-tcp-bbr=y' >> .config

# ===== 只补 Realtek rtl_nic 固件，不额外开驱动包 =====
# 背景：
#   - RTL8153/RTL8153B 的驱动（r8152）已进主线内核，由 target 内核 config 提供，
#     不需要再通过 CONFIG_PACKAGE_kmod-usb-net-rtl8152 拉一份模块。
#   - 但 firmware patch（/lib/firmware/rtl_nic/rtl8153a-2.fw、rtl8153b-2.fw 等）
#     没有随默认固件包进镜像，驱动启动时 request_firmware 会拿不到，
#     所以只单独打开 r8152-firmware（纯数据包，无依赖）。
# 注意：不要再把 kmod-usb-net-rtl8152 加回来 —— 它依赖 kmod-crypto-sha256，
#       会把这两个包一起拖进构建，曾导致编译失败。
for sym in CONFIG_PACKAGE_r8152-firmware; do
  sed -i "s/^# ${sym} is not set$/${sym}=y/" .config
  if ! grep -q "^${sym}=y" .config; then
    echo "${sym}=y" >> .config
  fi
done

# ===== 修复 glib2 子包对 libffi 的构建顺序（新 package-pack 框架 .provides 竞态）=====
# 现象：Package glib2-gobject is missing dependencies for the following libraries: libffi.so.8
# 原因：glib2-gobject 依赖 +libffi，但它的 .provides 可能先于 libffi 的 .provides 生成，
#       并行编译时会漏掉 libffi.so.8；且失败重跑会复用那份不完整的 .provides。
# 处理：给 glib2 增加 target 构建依赖，强制 libffi 先完成打包；并确保 libffi 被选中。
if [ -f feeds/packages/libs/glib2/Makefile ]; then
  grep -q '^PKG_BUILD_DEPENDS:=.*libffi' feeds/packages/libs/glib2/Makefile || \
    sed -i '/^HOST_BUILD_DEPENDS:=/a PKG_BUILD_DEPENDS:=libffi' feeds/packages/libs/glib2/Makefile
fi
sed -i 's/^# CONFIG_PACKAGE_libffi is not set$/CONFIG_PACKAGE_libffi=y/' .config
grep -q '^CONFIG_PACKAGE_libffi=y' .config || echo 'CONFIG_PACKAGE_libffi=y' >> .config

# 修复 LuCI 状态页 29_ports.js 因 undefined/null 统计值导致 cbi.js toString 报错
# 注：上游 luci 尚未修复（29_ports.js 仍直接 .format(可能为 null 的值)），此修复保留
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-fix-29-ports <<'EOF'
#!/bin/sh

PORTS_JS="/www/luci-static/resources/view/status/include/29_ports.js"

if [ -f "$PORTS_JS" ] && ! grep -q "_format_before_29_ports_fix" "$PORTS_JS"; then
    cp "$PORTS_JS" "$PORTS_JS.orig"

    cat > /tmp/ports_patch.js <<'EOP'
(function() {
	if (!String.prototype._format_before_29_ports_fix) {
		String.prototype._format_before_29_ports_fix = String.prototype.format;

		String.prototype.format = function() {
			for (var i = 0; i < arguments.length; i++) {
				if (arguments[i] == null)
					arguments[i] = 0;
			}

			return String.prototype._format_before_29_ports_fix.apply(this, arguments);
		};
	}
})();
EOP

    cat /tmp/ports_patch.js "$PORTS_JS.orig" > "$PORTS_JS"
    rm -f /tmp/ports_patch.js
fi

exit 0
EOF

chmod +x files/etc/uci-defaults/99-fix-29-ports

# USB host 自动切换服务脚本权限
chmod +x files/etc/init.d/usb-host-auto 2>/dev/null || true
# LED 开机策略服务脚本权限
chmod +x files/etc/init.d/led-boot 2>/dev/null || true
# rc.local 可执行权限（OpenWrt done 服务用 -x 检查后执行）
chmod +x files/etc/rc.local 2>/dev/null || true

# 首次启动时 enable 自定义 init 服务（files/ 拷入的脚本不会自动建 /etc/rc.d 链接）
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-enable-custom-services <<'EOF'
#!/bin/sh

/etc/init.d/usb-host-auto enable 2>/dev/null
/etc/init.d/led-boot enable 2>/dev/null

exit 0
EOF
chmod +x files/etc/uci-defaults/99-enable-custom-services

for cfg in target/linux/msm89xx/config-*; do
  [ -f "$cfg" ] || continue

  sed -i '/CONFIG_IP_ADVANCED_ROUTER/d' "$cfg"
  sed -i '/CONFIG_IP_MULTIPLE_TABLES/d' "$cfg"
  sed -i '/CONFIG_IPV6_MULTIPLE_TABLES/d' "$cfg"

  echo 'CONFIG_IP_ADVANCED_ROUTER=y' >> "$cfg"
  echo 'CONFIG_IP_MULTIPLE_TABLES=y' >> "$cfg"
  echo 'CONFIG_IPV6_MULTIPLE_TABLES=y' >> "$cfg"
done

echo "Check msm89xx kernel routing config:"
grep -R "CONFIG_IP_ADVANCED_ROUTER\|CONFIG_IP_MULTIPLE_TABLES\|CONFIG_IPV6_MULTIPLE_TABLES" target/linux/msm89xx/config-* || true

# ===== 移除 ARMv8 Crypto Extensions（CE），只保留 NEON / bit-sliced 加速 =====
# 参考稳定版固件：msm8916 不支持 ARM64_CE（CE 实现是给 msm8996/8998 等 SoC 用的），
# 这里显式关闭所有 CE 实现，NEON / bit-sliced 实现保持开启
for cfg in target/linux/msm89xx/config-*; do
  [ -f "$cfg" ] || continue

  for sym in \
    CONFIG_CRYPTO_AES_ARM64_CE \
    CONFIG_CRYPTO_AES_ARM64_CE_BLK \
    CONFIG_CRYPTO_AES_ARM64_CE_CCM \
    CONFIG_CRYPTO_GHASH_ARM64_CE \
    CONFIG_CRYPTO_SHA1_ARM64_CE \
    CONFIG_CRYPTO_SHA2_ARM64_CE \
    CONFIG_CRYPTO_SHA512_ARM64_CE \
    CONFIG_CRYPTO_SM3_ARM64_CE \
    CONFIG_CRYPTO_SM4_ARM64_CE \
    CONFIG_CRYPTO_SM4_ARM64_CE_BLK \
    CONFIG_CRYPTO_SM4_ARM64_CE_CCM \
    CONFIG_CRYPTO_SM4_ARM64_CE_GCM \
    CONFIG_CRYPTO_CRCT10DIF_ARM64_CE ; do
    sed -i "/^${sym}=/d" "$cfg"
    if ! grep -q "^# ${sym} is not set" "$cfg"; then
      echo "# ${sym} is not set" >> "$cfg"
    fi
  done

  # 确保 NEON / bit-sliced 实现开启
  for sym in CONFIG_CRYPTO_AES_ARM64_NEON_BLK CONFIG_CRYPTO_AES_ARM64_BS; do
    sed -i "/^${sym}=/d" "$cfg"
    sed -i "/^# ${sym} is not set/d" "$cfg"
    echo "${sym}=y" >> "$cfg"
  done
done

echo "Check msm89xx arm64 crypto (CE removed / NEON kept):"
grep -R "ARM64_CE\|ARM64_NEON_BLK\|ARM64_BS" target/linux/msm89xx/config-* || true

# 启用 IPv4 策略路由（直接写入内核 platform config，绕过 make defconfig 的依赖检查）
# CONFIG_KERNEL_IP_ADVANCED_ROUTER 在 OpenWrt Config.in 中无对应 wrapper，必须用此方式
#for cfg in target/linux/msm89xx/config-*; do
#  grep -q 'CONFIG_IP_ADVANCED_ROUTER' "$cfg" || echo 'CONFIG_IP_ADVANCED_ROUTER=y' >> "$cfg"
#  grep -q 'CONFIG_IP_MULTIPLE_TABLES' "$cfg" || echo 'CONFIG_IP_MULTIPLE_TABLES=y' >> "$cfg"
#done


# 临时添加的插件
# git clone https://github.com/lkiuyu/luci-app-cpu-perf package/luci-app-cpu-perf
# git clone https://github.com/lkiuyu/luci-app-cpu-status package/luci-app-cpu-status
# git clone https://github.com/gSpotx2f/luci-app-cpu-status-mini package/luci-app-cpu-status-mini
# git clone https://github.com/lkiuyu/luci-app-temp-status package/luci-app-temp-status
# git clone https://github.com/lkiuyu/DbusSmsForwardCPlus package/DbusSmsForwardCPlus


# ===== 去除基带（内部 modem）相关 =====
# openstick-tweaks 去掉基带依赖（qmi-modem-410-init 开机初始化基带 / luci-proto-modemmanager）
sed -i 's/ +qmi-modem-410-init//' feeds/openstick/utils/openstick-tweaks/Makefile
sed -i 's/ +PACKAGE_luci:luci-proto-modemmanager//' feeds/openstick/utils/openstick-tweaks/Makefile
# 其开机脚本不再创建 modem 接口与 wwan0 防火墙条目
sed -i '/network\.modem/d; /wwan0/d' feeds/openstick/utils/openstick-tweaks/files/openstick_tweak
# 其开机脚本 DNS 上游换成国内可用公共 DNS（原 1.1.1.1/8.8.8.8/8.8.4.4 国内不可用，保留 223.5.5.5）
sed -i "/server='1.1.1.1'/d; /server='8.8.8.8'/d; /server='8.8.4.4'/d" feeds/openstick/utils/openstick-tweaks/files/openstick_tweak
sed -i "/server='223.5.5.5'/a uci add_list dhcp.@dnsmasq[0].server='119.29.29.29'" feeds/openstick/utils/openstick-tweaks/files/openstick_tweak
sed -i "/server='223.5.5.5'/a uci add_list dhcp.@dnsmasq[0].server='114.114.114.114'" feeds/openstick/utils/openstick-tweaks/files/openstick_tweak
# 脚本结尾的 apk del 在本系统（opkg）不存在会失败，导致 uci-defaults 认为脚本失败、每次重启重跑
# 删除该行并强制 exit 0，让脚本只执行一次
sed -i '/^apk del openstick-tweaks$/d' feeds/openstick/utils/openstick-tweaks/files/openstick_tweak
echo 'exit 0' >> feeds/openstick/utils/openstick-tweaks/files/openstick_tweak
