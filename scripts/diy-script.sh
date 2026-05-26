#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")/.." && pwd)"
readonly LOG_PREFIX="[diy]"

# 日志函数
log() { echo "$LOG_PREFIX $*"; }
error() { echo "$LOG_PREFIX [ERROR] $*" >&2; }
warn() { echo "$LOG_PREFIX [WARN] $*" >&2; }

# 检查文件存在
check_file_exists() {
  local file="$1"
  if [ ! -f "$file" ]; then
    error "文件不存在: $file"
    return 1
  fi
}

# 安全的克隆函数
clone_if_missing() {
  local repo="$1"
  local branch="$2"
  local dest="$3"
  
  if [ -d "$dest" ]; then
    log "跳过已存在的仓库: $dest"
    return 0
  fi
  
  local cmd="git clone --depth=1"
  if [ -n "$branch" ]; then
    cmd="$cmd -b $branch"
    log "克隆专属分支 [-b $branch]: $repo -> $dest"
  else
    log "克隆默认分支: $repo -> $dest"
  fi
  
  if ! $cmd "$repo" "$dest" 2>&1; then
    error "克隆失败: $repo"
    return 1
  fi
}

# 主函数
main() {
  log "============================================"
  log "开始配置 纯净版原厂增强固件 专属环境"
  log "核心诉求：预装 MosDNS+WG，daed 仅锁死底层内核依赖"
  log "============================================"
  
  # ============================================
  # 1. 修改默认IP为 10.1.1.1，并清除 root 默认登录密码
  # ============================================
  log "修改默认IP为 10.1.1.1"
  if ! check_file_exists "package/base-files/files/bin/config_generate"; then
    return 1
  fi
  sed -i 's/192.168.6.1/10.1.1.1/g' package/base-files/files/bin/config_generate
  sed -i 's/192.168.1.1/10.1.1.1/g' package/base-files/files/bin/config_generate
  
  if ! check_file_exists "package/base-files/files/etc/shadow"; then
    return 1
  fi
  sed -i -E 's|^root:[^:]*:|root::|' package/base-files/files/etc/shadow
  
  # ============================================
  # 2. 彻底清除源码及 Feeds 中关于 dae/daed 的一切残余
  # ============================================
  log "强制清理所有 dae / daed 编译源码与临时占位"
  rm -rf \
    feeds/packages/net/mosdns \
    feeds/packages/net/dae \
    feeds/packages/net/daed \
    package/dae \
    package/daed \
    package/feeds/luci/luci-app-dae \
    package/feeds/luci/luci-app-daed \
    package/v2ray-geodata \
    package/v2ray-geoip \
    package/v2ray-geosite \
    package/daed-i18n-placeholder \
    2>/dev/null || true
  
  # ============================================
  # 3. 克隆必要的仓库（仅保留 MosDNS）
  # ============================================
  log "开始克隆最新版 MosDNS 源码"
  if ! clone_if_missing "https://github.com/sbwml/luci-app-mosdns" "v5" "package/luci-app-mosdns"; then
    return 1
  fi
  log "开始克隆最新版 luci-app-daed 源码"
  if ! clone_if_missing "https://github.com/QiuSimons/luci-app-daed" "master" "package/luci-app-daed"; then
    return 1
  fi

  # ============================================
  # 4. 满血刷新 feeds 补充缺失的组件依赖
  # ============================================
  log "刷新 feeds，补齐系统工具链..."
  if ! ./scripts/feeds update -a 2>&1; then
    error "feeds update 失败"
    return 1
  fi
  if ! ./scripts/feeds install -a 2>&1; then
    error "feeds install 失败"
    return 1
  fi

   # 4.3 【新增】从你的仓库路径复制并注入 Go 1.26
  # ============================================
  local workspace_root="${GITHUB_WORKSPACE:-$(pwd)}"
  local golang126_src_dir="$workspace_root/scripts/golang1.26"
  local golang126_feed_dir="feeds/packages/lang/golang1.26"

  log "检查源码仓中的 Go 1.26 工具链..."
  if [ -d "$golang126_src_dir" ]; then
    log "成功定位！正在注入 Go 1.26 独立工具链..."
    rm -rf "$golang126_feed_dir"
    mkdir -p "$golang126_feed_dir"
    cp -rf "$golang126_src_dir/." "$golang126_feed_dir/"
    
    # 注册组件索引使其在编译树中生效
    ./scripts/feeds install golang1.26
  else
    error "致命错误: 无法在 $golang126_src_dir 找到 Go 1.26 源码！请确认文件已提交！"
    return 1
  fi


  # ============================================
  # 4.5 定向配置：仅让 mosdns 和 dae 使用 golang1.26 工具链
  # ============================================
  log "开始为 mosdns 和 dae 强绑定 golang1.26 独立工具链"
  
  # 深度遍历所有包含 mosdns 或 dae 关键字的 Makefile 并精准替换
  find package/ feeds/ -type f -name "Makefile" 2>/dev/null | grep -E "mosdns|dae" | while read -r makefile; do
    log "-> 正在定向替换工具链: $makefile"
    sed -i -e 's|golang/golang-package.mk|golang1.26/golang-package.mk|g' \
           -e 's|golang/host|golang1.26/host|g' "$makefile"
  done

  # 4.6 【新增】清除 Go 1.26 不再支持的过时实验性参数 runtimefreegc
  log "正在清理 daed 源码中过时的 runtimefreegc 参数..."
  find package/ feeds/ -type f -name "Makefile" 2>/dev/null | grep -E "daed|dae" | while read -r makefile; do
    sed -i '/GO_EXPERIMENT:=runtimefreegc/d' "$makefile"
    sed -i '/GO_EXPERIMENT = runtimefreegc/d' "$makefile"
  done

  # 额外防御：检查 mosdns 和 dae 源码目录下的 go.mod 限制，统一提升至 go 1.26 释放兼容性
  find package/ feeds/ -type f -name "go.mod" 2>/dev/null | grep -E "mosdns|dae" | while read -r gomod; do
    log "-> 正在调整 Go 版本声明: $gomod"
    sed -i -E 's/go 1\.[0-9]+/go 1.26/g' "$gomod"
  done
  
  # ============================================
  # 5. 修改固件版本号为当天编译日期
  # ============================================
  local date_version
  date_version="$(date +%Y.%m.%d)"
  local version_file="include/version.mk"
  
  log "修改版本为编译日期: $date_version"
  if ! check_file_exists "$version_file"; then
    warn "版本文件不存在: $version_file，跳过版本修改"
  else
    sed -i "s/^VERSION_NUMBER:=.*/VERSION_NUMBER:=-$date_version by Imouto-Advanced/" "$version_file"
  fi

    # 👇=== 就是这里！把下面这 5 行复制到这里 ===👇
  log "正在从种子配置中剔除 btop 组件..."
  if [ -f ".config" ]; then
    sed -i '/CONFIG_PACKAGE_btop=y/d' .config
    echo "CONFIG_PACKAGE_btop=n" >> .config
  fi
  # 👆========================================👆

  # ============================================
  # 6. 【全面修复】强力注入 BPF 内核头文件支持与组件勾选
  # ============================================
  log "开始终极配置：强制开启内核 eBPF 全套支持与头文件分发"
  
  # 6.1 解除 generic 目录和所有平台特定的内核配置硬限制（解决 dae 无法启动）
  find target/linux/ -name "config-*" -exec sed -i 's/# CONFIG_NET_CLS_BPF is not set/CONFIG_NET_CLS_BPF=y/g' {} +
  find target/linux/ -name "config-*" -exec sed -i 's/# CONFIG_NET_SCH_INGRESS is not set/CONFIG_NET_SCH_INGRESS=y/g' {} +
  find target/linux/ -name "config-*" -exec sed -i 's/# CONFIG_BPF_SYSCALL is not set/CONFIG_BPF_SYSCALL=y/g' {} +
  
  # 6.2 向通用内核配置追加覆盖选项
  cat << 'EOF' >> target/linux/generic/config-6.6
  CONFIG_NET_CLS_BPF=y
  CONFIG_NET_SCH_INGRESS=y
  CONFIG_NET_CLS_ACT=y
  CONFIG_BPF_SYSCALL=y
  CONFIG_CGROUP_BPF=y
  CONFIG_BPF_JIT=y
  CONFIG_BPF_JIT_ALWAYS_ON=y
  CONFIG_DEBUG_INFO_BTF=y
  EOF
  
  # 6.3 强行注入主 .config 配置（确保编译输出内核头文件与防火墙兼容组件，解决 LuCI 打不开）
  if [ -f ".config" ]; then
    log "正在追加核心 BPF 工具链与 LuCI 防火墙配置至 .config..."
    cat << 'EOF' >> .config
  # BPF Developer Tools & Headers (修复 go generate 编译闪退的关键)
  CONFIG_KERNEL_BPF_EVENTS=y
  CONFIG_KERNEL_CGROUP_BPF=y
  CONFIG_PACKAGE_kmod-sched-core=y
  CONFIG_PACKAGE_kmod-sched-bpf=y

  # 强制 OpenWrt 在编译阶段解压并分发 Linux 官方内核 BPF 头文件
  CONFIG_PACKAGE_bpf-headers=y

  # Firewall & LuCI Compatibility 
  CONFIG_PACKAGE_kmod-nft-compat=y
  CONFIG_PACKAGE_xtables-nft=y
  CONFIG_PACKAGE_uhttpd=y
  CONFIG_PACKAGE_luci=y
  CONFIG_LUCI_LANG_zh_Hans=y
  CONFIG_PACKAGE_luci-mod-admin-full=y
  CONFIG_PACKAGE_rpcd=y
  CONFIG_PACKAGE_uhttpd-mod-ubus=y
  EOF
  fi

  log "✓ 所有定制环境完美配置完成！"
}

# 执行主函数
main "$@" || {
  error "脚本执行失败，请检查上述错误信息"
  exit 1
}
