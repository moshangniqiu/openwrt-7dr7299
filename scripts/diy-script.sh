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

# 检查目录存在
check_dir_exists() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    error "目录不存在: $dir"
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
  log "开始配置 DAED + MosDNS 专属环境"
  
  # ============================================
  # 1. 修改默认IP为 10.1.1.1，并清除 root 默认登录密码
  # ============================================
  log "修改默认IP为 10.1.1.1"
  if ! check_file_exists "package/base-files/files/bin/config_generate"; then
    return 1
  fi
  sed -i 's/192.168.6.1/10.1.1.1/g' package/base-files/files/bin/config_generate
  
  if ! check_file_exists "package/base-files/files/etc/shadow"; then
    return 1
  fi
  sed -i -E 's|^root:[^:]*:|root::|' package/base-files/files/etc/shadow
  
  # ============================================
  # 2. 提前移除源码中冲突的官方旧版残余
  # ============================================
  log "移除旧版冲突包"
  rm -rf \
    feeds/packages/net/mosdns \
    feeds/packages/net/dae \
    feeds/packages/net/daed \
    package/feeds/luci/luci-app-dae \
    package/feeds/luci/luci-app-daed \
    package/v2ray-geodata \
    2>/dev/null || true
  
  # ============================================
  # 3. 克隆必要的仓库
  # ============================================
  log "开始克隆最新版 DAED、MosDNS 及规则包"
  if ! clone_if_missing "https://github.com/QiuSimons/luci-app-daed" "" "package/dae"; then
    return 1
  fi
  if ! clone_if_missing "https://github.com/sbwml/luci-app-mosdns" "v5" "package/luci-app-mosdns"; then
    return 1
  fi
  if ! clone_if_missing "https://github.com/sbwml/v2ray-geodata" "" "package/v2ray-geodata"; then
    return 1
  fi
  
  # ============================================
  # 4. 刷新 feeds 确保系统底层依赖完备
  # ============================================
  log "刷新 feeds..."
  if ! ./scripts/feeds update -a 2>&1; then
    error "feeds update 失败"
    return 1
  fi
  if ! ./scripts/feeds install -a 2>&1; then
    error "feeds install 失败"
    return 1
  fi
  
  # ============================================
  # 5. 强制忽略 DAED 的 OPKG 依赖检查
  # ============================================
  log "注入底层补丁，强制忽略 DAED 的 OPKG 依赖检查"
  if [ -d "package/dae" ]; then
    local makefile_count=0
    while IFS= read -r makefile; do
      sed -i 's/DEPENDS:=.*/& +kmod-xdp-sockets-diag/g' "$makefile"
      ((makefile_count++))
    done < <(find package/dae -name "Makefile" -type f)
    
    if [ "$makefile_count" -eq 0 ]; then
      warn "未找到 package/dae 中的 Makefile，跳过依赖注入"
    else
      log "已修改 $makefile_count 个 Makefile"
    fi
  else
    warn "package/dae 目录不存在，跳过依赖注入"
  fi
  
  # ============================================
  # 6. 修改固件版本号为当天编译日期
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
  
  log "✓ 配置完成"
}

# 执行主函数
main "$@" || {
  error "脚本执行失败，请检查上述错误信息"
  exit 1
}
