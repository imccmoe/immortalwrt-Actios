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


# ===== 去除基带（内部 modem）相关 =====
# 目标默认包：去掉基带内核驱动（rpmsg-wwan-ctrl / bam-dmux / qcom-rproc-modem）与 rmtfs
sed -i '/DEFAULT_PACKAGES += kmod-rpmsg-wwan-ctrl kmod-bam-dmux kmod-qcom-rproc-modem/d' target/linux/msm89xx/Makefile
sed -i '/DEFAULT_PACKAGES += rmtfs/d' target/linux/msm89xx/Makefile
# 设备默认包：去掉基带固件（保留 wcnss WiFi 固件与 nv 校准）
sed -i 's/ qcom-msm8916-modem-[^ ]*//g' target/linux/msm89xx/image/msm8916.mk

# ===== 启用 IPv6（仅获取使用，不下发） =====
# 目标默认包：只加 DHCPv6 客户端，不加 odhcpd（随身WiFi不需要向客户端下发IPv6）
sed -i '/^DEFAULT_PACKAGES += kmod-wcn36xx kmod-rproc-wcnss/a DEFAULT_PACKAGES += odhcp6c' target/linux/msm89xx/Makefile

# ===== CPU 调频说明 =====
# 上游 config-* 已默认开启 CPU_FREQ/CPUFREQ_DT/SCHEDUTIL/CPU_FREQ_THERMAL（=y），无需改动；
# 发热控制靠 luci-app-cpufreq 限频（用户态），过热自动降频由 tsens+cooling-maps 内建生效


