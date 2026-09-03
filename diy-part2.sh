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


# ===== argon 主题：强制使用 jerrykuku 官方最新源码 =====
# 实际编译使用的是 luci feed 自带的 luci-theme-argon（版本停在 2.4.3-r20250722，
# feeds 同名冲突时 luci feed 优先于 smpackage），旧版模板依赖 ucode-mod-math 易出问题
# 直接整体替换 luci feed 的包为官方仓库最新（当前 2.4.6），拉取失败则回退原版
ARGON_SRC="feeds/luci/themes/luci-theme-argon"
if [ -d "$ARGON_SRC" ]; then
  mv "$ARGON_SRC" "$ARGON_SRC.bak"
  if git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git "$ARGON_SRC"; then
    echo ">>> argon 已替换为官方最新版: $(grep -m1 'PKG_VERSION' "$ARGON_SRC/Makefile" 2>/dev/null || echo '?')"
    rm -rf "$ARGON_SRC.bak"
  else
    echo "!!! 官方 argon 拉取失败，回退 luci feed 版本（检查上方 git clone 报错）"
    mv "$ARGON_SRC.bak" "$ARGON_SRC"
  fi
fi

# 同步替换 smpackage 里的同名包（防止未来 feed 顺序变化导致旧版被编译）
if [ -d feeds/smpackage/luci-theme-argon ]; then
  mv feeds/smpackage/luci-theme-argon feeds/smpackage/luci-theme-argon.bak
  if git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git feeds/smpackage/luci-theme-argon; then
    echo ">>> smpackage 的 argon 已同步为官方最新版"
    rm -rf feeds/smpackage/luci-theme-argon.bak
  else
    echo "!!! smpackage argon 同步失败，保留原版（不影响，luci feed 优先级更高）"
    mv feeds/smpackage/luci-theme-argon.bak feeds/smpackage/luci-theme-argon
  fi
fi

# ===== argon 主题模板自愈（兜底）=====
# luci 26.x 的 ucode 渲染器不支持旧语法（<% %>），且旧模板 import 'math' 需要 ucode-mod-math
# 若最终生效的 argon 模板仍是旧版，自动替换为 kenzok8 master 的最新模板
for ARGON_DIR in feeds/luci/themes/luci-theme-argon/ucode/template/themes/argon feeds/smpackage/luci-theme-argon/ucode/template/themes/argon; do
  if [ -f "$ARGON_DIR/header.ut" ] && grep -qE "'math'|<%" "$ARGON_DIR/header.ut" 2>/dev/null; then
    echo ">>> $ARGON_DIR 模板过旧（旧语法或依赖 ucode-mod-math），拉取最新模板..."
    for f in footer footer_login head_meta header header_login out_header_login sysauth; do
      curl -fsSL "https://raw.githubusercontent.com/kenzok8/small-package/master/luci-theme-argon/ucode/template/themes/argon/$f.ut" \
        -o "$ARGON_DIR/$f.ut" 2>/dev/null && echo "    更新 $f.ut" || echo "    跳过 $f.ut"
    done
  fi
done
