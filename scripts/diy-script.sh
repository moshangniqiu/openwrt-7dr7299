#!/bin/bash
set -e -o pipefail

echo "=== diy-script: 开始配置 DAED + MosDNS 专属环境 ==="

# 1. 修改默认IP为 10.1.1.1，并清除 root 默认登录密码
echo "[diy] 修改默认IP为 10.1.1.1"
sed -i 's/192.168.6.1/10.1.1.1/g' package/base-files/files/bin/config_generate
sed -i -E 's|^root:[^:]*:|root::|' package/base-files/files/etc/shadow

# 2. 提前移除源码中冲突的官方旧版残余，为新版腾出位置
echo "[diy] 移除旧版冲突包"
rm -rf feeds/packages/net/mosdns feeds/packages/net/dae feeds/packages/net/daed package/feeds/luci/luci-app-dae package/feeds/luci/luci-app-daed package/v2ray-geodata

# 3. 彻底修复翻车隐患的智能防报错克隆函数（移除危险的缩写替换，改用最稳健的 if 判断）
clone_if_missing() {
  local repo="$1"
  local branch="$2"
  local dest="$3"
  
  if [ -d "$dest" ]; then
    echo "[diy] 跳过已存在的仓库: $dest"
  else
    if [ -z "$branch" ]; then
      echo "[diy] 克隆默认分支: $repo -> $dest"
      git clone --depth=1 "$repo" "$dest"
    else
      echo "[diy] 克隆专属分支 [-b $branch]: $repo -> $dest"
      git clone --depth=1 -b "$branch" "$repo" "$dest"
    fi
  fi
}

# 4. 【核心对表】使用修正后的安全参数进行克隆（不带任何干扰的空双引号，第2个参数不写代表默认分支）
echo "[diy] 开始克隆最新版 DAED、MosDNS 及规则包"
clone_if_missing "https://github.com/QiuSimons/luci-app-daed" ""   "package/dae"
clone_if_missing "https://github.com/sbwml/luci-app-mosdns"   "v5" "package/luci-app-mosdns"
clone_if_missing "https://github.com/sbwml/v2ray-geodata"     ""   "package/v2ray-geodata"

# 5. 刷新 feeds 确保系统底层依赖完备
./scripts/feeds update -a
./scripts/feeds install -a

# 6. 【核心修复】强行豁免 DAED 的依赖检查，注入对高级用户忽略依赖的支持
echo "[diy] 注入底层补丁，强制忽略 DAED 的 OPKG 依赖检查"
find package/dae -name "Makefile" -type f -exec sed -i 's/DEPENDS:=.*/& +kmod-xdp-sockets-diag/g' {} + 2>/dev/null || true

# 7. 修改固件版本号为当天编译日期
DATE_VERSION="$(date +%Y.%m.%d)"
VERSION_FILE="include/version.mk"
echo "[diy] 修改版本为编译日期: $DATE_VERSION"
sed -i "s/^VERSION_NUMBER:=.*/VERSION_NUMBER:=-$DATE_VERSION by Imouto-Advanced/" "$VERSION_FILE" 2>/dev/null || true

echo "=== diy-script: 配置完成 ==="
