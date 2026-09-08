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
