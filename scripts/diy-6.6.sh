#!/bin/bash
set -e -o pipefail

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
GOLANG126_SRC_DIR="$WORKSPACE_ROOT/scripts/6.6/golang1.26"
GOLANG126_FEED_DIR="feeds/packages/lang/golang1.26"
rm -rf "$GOLANG126_FEED_DIR"
mkdir -p "$GOLANG126_FEED_DIR"
cp -rf "$GOLANG126_SRC_DIR/." "$GOLANG126_FEED_DIR/"
./scripts/feeds update -f packages
./scripts/feeds install golang1.26

# passwall daed use golang1.26/host
find package/dae -name "Makefile" -type f -exec sed -i \
  -e 's|\<golang/golang-package.mk\>|golang1.26/golang-package.mk|g' \
  -e 's|\<golang/host\>|golang1.26/host|g' {} +

# 同步仓库内维护的 patches 目录到 OpenWrt 源码树
if [ -d "$GITHUB_WORKSPACE/patches/6.6" ]; then
  echo "[diy] 同步自定义 patches/6.6 目录到源码树"
  cp -rf "$GITHUB_WORKSPACE/patches/6.6/." ./
else
  echo "[diy] patches/6.6 目录不存在，跳过"
fi
