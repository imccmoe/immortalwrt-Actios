#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part2.sh
# 功能说明: OpenWrt DIY脚本第2部分（更新feeds之后）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 修改默认IP地址
#sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate


# 修改默认主题为 argon（路径不存在时跳过，不中断编译）
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true

# 修复 LuCI 状态页 29_ports.js 因 undefined/null 统计值导致 cbi.js toString 报错
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
