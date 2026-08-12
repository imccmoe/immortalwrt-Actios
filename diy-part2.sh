#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part2.sh
# 功能说明: OpenWrt DIY脚本第2部分（更新feeds之后）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 修改默认IP地址
#sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate


# 修改默认主题为 argon（显式在 config/*.config 中启用 luci-theme-argon，此处只做首启兜底）
# 注意：当前 luci 合集的 Makefile 不直接依赖 luci-theme-bootstrap，旧的 sed 替换已失效，勿恢复
mkdir -p files/etc/uci-defaults

# 首启强制默认主题为 argon（仅当 argon 已安装时生效；bootstrap 保留可切换）
# 同时兜底注册主题到 luci.themes，避免 argon 自带 uci-defaults 未执行导致下拉框为空
cat > files/etc/uci-defaults/99-argon-default <<'EOF'
#!/bin/sh

if [ -d "/www/luci-static/argon" ]; then
	uci -q get luci.themes.Argon >/dev/null 2>&1 || uci -q set luci.themes.Argon='/luci-static/argon'
	uci -q set luci.main.mediaurlbase='/luci-static/argon'
	uci -q commit luci
fi

exit 0
EOF

chmod +x files/etc/uci-defaults/99-argon-default

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


# ===== 去除基带（内部 modem）相关 =====
# openstick-tweaks 去掉基带依赖（qmi-modem-410-init 开机初始化基带 / luci-proto-modemmanager）
sed -i 's/ +qmi-modem-410-init//' feeds/openstick/utils/openstick-tweaks/Makefile
sed -i 's/ +PACKAGE_luci:luci-proto-modemmanager//' feeds/openstick/utils/openstick-tweaks/Makefile
# 其开机脚本不再创建 modem 接口与 wwan0 防火墙条目
sed -i '/network\.modem/d; /wwan0/d' feeds/openstick/utils/openstick-tweaks/files/openstick_tweak


# ===== argon 主题：强制使用 jerrykuku 官方最新源码 =====
# smpackage 是滚动源，编译时可能拉到旧版（如 2.4.3，模板依赖 ucode-mod-math 且不兼容 luci 26.x）
# 直接整体替换为官方仓库（当前 2.4.6，新语法无 math 依赖），拉取失败则回退 smpackage 版本
if [ -d feeds/smpackage/luci-theme-argon ]; then
  mv feeds/smpackage/luci-theme-argon feeds/smpackage/luci-theme-argon.bak
  if git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git feeds/smpackage/luci-theme-argon 2>/dev/null; then
    echo ">>> argon 已替换为官方最新版: $(grep -m1 'PKG_VERSION' feeds/smpackage/luci-theme-argon/Makefile 2>/dev/null || echo '?')"
    rm -rf feeds/smpackage/luci-theme-argon.bak
  else
    echo "!!! 官方 argon 拉取失败，回退 smpackage 版本"
    mv feeds/smpackage/luci-theme-argon.bak feeds/smpackage/luci-theme-argon
  fi
fi

# ===== argon 主题模板自愈（兜底）=====
# luci 26.x 的 ucode 渲染器不支持旧语法（<% %>），且旧模板 import 'math' 需要 ucode-mod-math
# 若最终拉到的 argon 模板仍是旧版，自动替换为 kenzok8 master 的最新模板
ARGON_DIR="feeds/smpackage/luci-theme-argon/ucode/template/themes/argon"
if [ -f "$ARGON_DIR/header.ut" ] && grep -qE "'math'|<%" "$ARGON_DIR/header.ut" 2>/dev/null; then
  echo ">>> argon 模板过旧（旧语法或依赖 ucode-mod-math），拉取最新模板..."
  for f in footer footer_login head_meta header header_login out_header_login sysauth; do
    curl -fsSL "https://raw.githubusercontent.com/kenzok8/small-package/master/luci-theme-argon/ucode/template/themes/argon/$f.ut" \
      -o "$ARGON_DIR/$f.ut" 2>/dev/null && echo "    更新 $f.ut" || echo "    跳过 $f.ut"
  done
fi
