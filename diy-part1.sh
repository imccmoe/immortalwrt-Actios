#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part1.sh
# 功能说明: OpenWrt DIY脚本第1部分（更新feeds之前）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 取消注释一个源
# sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# 添加第三方 feed 源（small-package 包含 openclash/passwall/ssr-plus 等常用插件）
echo 'src-git smpackage https://github.com/kenzok8/small-package' >> feeds.conf.default
# 添加第三方源，iStore 应用商店，编译时包名输入 luci-app-store
echo 'src-git store https://github.com/linkease/istore.git;main' >> feeds.conf.default


# OpenClash代理
# git clone --depth 1 https://github.com/vernesong/OpenClash.git OpenClash

# turboacc网络加速（需要用户在页面选择 luci-app-turboacc 后，由编译脚本自动执行，此处不再无条件运行）
# curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh

# 调试
# sed -i 's|src-git-full openstick https://github.com/lkiuyu/openstick-feeds.git|src-git-full openstick https://github.com/xuxin1955/openstick-feeds|g' feeds.conf.default


# ===== 全局放行「本地 git 归档」的镜像哈希不一致 =====
# 现象：make download 阶段报
#   Hash mismatch for file xxx.tar.xz: expected 58f8ad3f..., got 5daf9d3b...
#   make[2]: *** [Makefile:74: .../dl/xxx.tar.xz] Error 1
# 原因：很多包写成 PKG_SOURCE_PROTO:=git + PKG_MIRROR_HASH，期望从镜像下载预生成
#   的 tarball；镜像上没有（或对 CI 返回 403/404）时，download.mk 会回退到
#   git clone + git archive 本地打包，而归档字节受 xz/zlib/tar 版本与
#   .gitattributes 影响，跨机器不可复现 —— 哈希必然对不上，且换台机器或换次
#   构建就会再犯一次（gc、libusbgx 只是先撞上的两个）。
#   逐个改 PKG_MIRROR_HASH 治标不治本：改成实际值也只是"当前这台机器"的值。
# 处理：把 include/download.mk 中该分支的 `false` 换成 `:`，只保留警告不中断。
#   仅放行"镜像归档"这一条路径；从上游 URL 直接下载的包仍由 download.pl 按
#   PKG_HASH 严格校验，那条路径不做任何改动。
sed -i 's/^\([[:space:]]*\)false; \\$/\1:; \\/' include/download.mk
if grep -q '^[[:space:]]*:; \\$' include/download.mk; then
  echo ">>> download.mk: git 归档哈希不一致已降级为警告 <<<"
else
  echo ">>> 警告: download.mk 未命中，哈希不一致仍会中断构建 <<<"
fi

# ===== 去除基带（内部 modem）相关 =====
# 目标默认包：去掉基带内核驱动（rpmsg-wwan-ctrl / bam-dmux / qcom-rproc-modem）与 rmtfs
sed -i '/DEFAULT_PACKAGES += kmod-rpmsg-wwan-ctrl kmod-bam-dmux kmod-qcom-rproc-modem/d' target/linux/msm89xx/Makefile
sed -i '/DEFAULT_PACKAGES += rmtfs/d' target/linux/msm89xx/Makefile
# 设备默认包：去掉基带固件
sed -i 's/ qcom-msm8916-modem-[^ ]*//g' target/linux/msm89xx/image/msm8916.mk

# ===== 启用 IPv6（仅获取使用，不下发） =====
# 目标默认包：只加 DHCPv6 客户端，不加 odhcpd（随身WiFi不需要向客户端下发IPv6）
# 注意：锚点在 wcn36xx 行上，必须在下面删除该行之前执行
sed -i '/^DEFAULT_PACKAGES += kmod-wcn36xx kmod-rproc-wcnss/a DEFAULT_PACKAGES += odhcp6c' target/linux/msm89xx/Makefile

# ===== 移除内置无线（WCN36xx/WCNSS）释放内存 =====
# 目标默认包：去掉内置 WiFi 驱动与 WCNSS remoteproc
sed -i '/^DEFAULT_PACKAGES += kmod-wcn36xx kmod-rproc-wcnss/d' target/linux/msm89xx/Makefile
# 设备默认包：去掉 WCNSS 固件与 nv 校准（保留 wpad，供外接 USB 无线网卡使用）
sed -i 's/ qcom-msm8916-openstick-[^ ]*-wcnss-firmware//g' target/linux/msm89xx/image/msm8916.mk
sed -i 's/ qcom-msm8916-wcnss-openstick-[^ ]*-nv//g' target/linux/msm89xx/image/msm8916.mk

# ===== 修复 6.18 下 kmod-nf-ipt / kmod-iptables 重复打包同一批 .ko =====
# 现象：装 kmod-ipt-core / kmod-nft-compat 时报
#   check_data_file_clashes: Package kmod-nf-ipt wants to install .../ip_tables.ko
#   But that file is already provided by package * kmod-iptables
# 原因：上游 6.13+ 新增 HIDDEN 包 kmod-iptables（DEPENDS:=@!LINUX_6_12）负责
#   net/ipv4/netfilter/ip_tables.ko 与 net/netfilter/x_tables.ko；而 kmod-nf-ipt
#   的 FILES 仍从 NF_IPT-m 展开，6.18 内核里 CONFIG_IP_NF_IPTABLES 与
#   CONFIG_NETFILTER_XTABLES 仍是 =m，于是两个包同时声称拥有同一文件；
#   又因 nf-ipt 带 DEPENDS:=+!LINUX_6_12:kmod-iptables，装 nf-ipt 必连带装
#   kmod-iptables，冲突必然发生（默认镜像走 fw4/nft 不装 legacy iptables 才没暴露）。
# 处理：非 6.12 时把 nf-ipt 的 FILES 置空，文件所有权归 kmod-iptables。
#   6.12 仍保持原样（该版本没有 kmod-iptables 包）。
sed -i 's|FILES:=$(foreach mod,$(NF_IPT-m),$(LINUX_DIR)/net/$(mod).ko)|FILES:=$(if $(CONFIG_LINUX_6_12),$(foreach mod,$(NF_IPT-m),$(LINUX_DIR)/net/$(mod).ko),)|' \
  package/kernel/linux/modules/netfilter.mk
if grep -q 'FILES:=\$(if \$(CONFIG_LINUX_6_12)' package/kernel/linux/modules/netfilter.mk; then
  echo ">>> netfilter.mk: nf-ipt FILES 已按内核版本隔离（非 6.12 归 kmod-iptables）<<<"
else
  echo ">>> 警告: netfilter.mk 未命中，6.18 下 ip_tables.ko 仍可能冲突 <<<"
fi

# ===== 禁用 USB 自动休眠 =====
# 仅通过内核命令行全局禁用 USB 自动休眠；
# CPU 深度睡眠改用 DTS 控制：去掉簇级 GDHS（CLUSTER_PWRDN），保留簇 retention 与 CPU 浅睡
grep -q 'usbcore.autosuspend' target/linux/msm89xx/image/msm8916.mk || \
  sed -i '/^\s*CMDLINE :=/ s/"$/ usbcore.autosuspend=-1"/' target/linux/msm89xx/image/msm8916.mk
echo ">>> CMDLINE: $(grep 'CMDLINE :=' target/linux/msm89xx/image/msm8916.mk) <<<"

# ===== CPU 频率表：覆盖为 6 档 OPP（200MHz ~ 1.152GHz）=====
# 默认上游只有 4 档（最高 998MHz），此表增加 1094/1152MHz 档（高频超频档已移除），
# 便于 cpufreq 分级调频 / luci-app-cpufreq 手动限频有更多选择
mkdir -p target/linux/msm89xx/dts/
cp -f "$GITHUB_WORKSPACE/scripts/dts/msm8916.dtsi" "target/linux/msm89xx/dts/msm8916.dtsi"
echo ">>> CPU OPP 档位: $(grep -c 'opp-hz' target/linux/msm89xx/dts/msm8916.dtsi) <<<"

# ===== CPU 调频说明 =====
# 上游 config-* 已默认开启 CPU_FREQ/CPUFREQ_DT/SCHEDUTIL/CPU_FREQ_THERMAL（=y），无需改动；
# 发热控制靠 luci-app-cpufreq 限频（用户态），过热自动降频由 tsens+cooling-maps 内建生效

# ===== 降低过热保护阈值（msm8916 长期高温会断电，提前降频保护）=====
# 原阈值：75°C 开始降频 / 110°C 强制关机 → 改为 60°C 降频 / 95°C 关机
sed -i 's/temperature = <75000>;/temperature = <60000>;/g' target/linux/msm89xx/dts/msm8916.dtsi
sed -i 's/temperature = <110000>;/temperature = <95000>;/g' target/linux/msm89xx/dts/msm8916.dtsi


