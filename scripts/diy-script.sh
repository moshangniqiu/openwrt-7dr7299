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

# 3. 完美的智能防报错克隆函数（物归原主 🌟）
clone_if_missing() {
  local repo="$1" branch="$2" dest="$3"
  if [ -d "$dest" ]; then
    echo "[diy] 跳过已存在的仓库: $dest"
  else
    echo "[diy] 克隆: $repo -> $dest"
    git clone --depth=1 ${branch:+-b "$branch"} "$repo" "$dest"
  fi
}

# 4. 使用你的高级函数克隆最新版 DAED、MosDNS 以及规则包
echo "[diy] 开始克隆最新版 DAED、MosDNS 及规则包"
clone_if_missing https://github.com/QiuSimons/luci-app-daed "" package/dae
clone_if_missing https://github.com/sbwml/luci-app-mosdns -b v5 "" package/luci-app-mosdns
clone_if_missing https://github.com/sbwml/v2ray-geodata "" package/v2ray-geodata

# 5. 刷新 feeds 确保系统底层依赖完备
./scripts/feeds update -a
./scripts/feeds install -a

# 6. 修改固件版本号为当天编译日期
DATE_VERSION="$(date +%Y.%m.%d)"
VERSION_FILE="include/version.mk"
echo "[diy] 修改版本为编译日期: $DATE_VERSION"
sed -i "s/^VERSION_NUMBER:=.*/VERSION_NUMBER:=-$DATE_VERSION by Imouto-Advanced/" "$VERSION_FILE" 2>/dev/null || true

echo "=== diy-script: 配置完成 ==="
