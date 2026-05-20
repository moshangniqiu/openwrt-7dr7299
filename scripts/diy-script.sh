#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# 安全的克隆函数（带完整错误处理）
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
  log "核心诉求：预装 MosDNS+WG，daed 仅锁死底层依赖"
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
  # 2. 彻底移除源码及 Feeds 中所有冲突的旧残余（防止系统扫描 Makefile 报错）
  # ============================================
  log "强制清理残留的 dae / daed 编译源码，确保眼不见为净"
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
    2>/dev/null || true
  
  # ============================================
  # 3. 克隆必要的仓库
  # ============================================
  log "开始克隆最新版 MosDNS 源码"
  # 克隆成熟的 MosDNS v5 分支（带完整中文面板）
  if ! clone_if_missing "https://github.com/sbwml/luci-app-mosdns" "v5" "package/luci-app-mosdns"; then
    return 1
  fi

  # 占位：克隆专属的 daed 汉化语言包（不含主程序 Makefile，编译绝不报错！）
  # 这样刷机后你手装 daed 的 IPK 时，系统会自动切到中文界面
  log "克隆 daed 中文语言包用于固件占位..."
  if ! clone_if_missing "https://github.com/QiuSimons/luci-app-daed" "main" "package/daed-i18n-placeholder"; then
    return 1
  fi
  # 骚操作：只保留语言包的 i18n 目录，把会引发编译报错的主程序和面板 Makefile 全部删掉
  find package/daed-i18n-placeholder -maxdepth 1 ! -name 'luci-i18n-daed-zh-cn' ! -name 'daed-i18n-placeholder' -exec rm -rf {} + 2>/dev/null || true
  
  # ============================================
  # 4. 满血刷新 feeds 补充缺失的 Python/Zabbix 依赖
  # ============================================
  log "刷新 feeds，补齐系统 host 工具链..."
  if ! ./scripts/feeds update -a 2>&1; then
    error "feeds update 失败"
    return 1
  fi
  if ! ./scripts/feeds install -a 2>&1; then
    error "feeds install 失败"
    return 1
  fi
  
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
  
  log "✓ 所有定制环境完美配置完成！"
}

# 执行主函数
main "$@" || {
  error "脚本执行失败，请检查上述错误信息"
  exit 1
}
