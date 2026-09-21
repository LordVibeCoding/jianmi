#!/usr/bin/env bash
# 本机一键安装：Release 构建 → 装入 /Applications
#
# 为什么用 mv 而不是 cp/DMG：
# Xcode 构建时会为产物注册"执行策略豁免"(RegisterExecutionPolicyException)，
# mv 保留 inode → 豁免跟随，首次启动无需 Gatekeeper 在线核查。
# （在开启 TUN 模式代理的机器上，该在线核查可能被黑洞导致 App 卡死在启动）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/dist/DerivedData-install"

echo "── 1/3 打包浏览器扩展…"
"$ROOT/scripts/build_extension.sh" >/dev/null

echo "── 2/3 Release 构建…"
cd "$ROOT/apps/macos"
xcodegen generate >/dev/null
xcodebuild -project JianMi.xcodeproj -scheme JianMi -configuration Release \
    -derivedDataPath "$BUILD_DIR" build 2>&1 | grep -E "^\*\* BUILD" || { echo "构建失败"; exit 1; }

APP="$BUILD_DIR/Build/Products/Release/JianMi.app"

echo "── 3/3 安装到 /Applications…"
killall JianMi 2>/dev/null || true
sleep 1

# 在被豁免的构建路径内先执行一次，触发 syspolicyd 的 cdhash 级放行缓存；
# 之后搬到 /Applications 首启即命中缓存，不再触发（可能被代理黑洞的）在线核查
"$APP/Contents/MacOS/JianMi" >/dev/null 2>&1 &
WARM_PID=$!
sleep 2
kill $WARM_PID 2>/dev/null || true
sleep 1
rm -rf /Applications/JianMi.app
mv "$APP" /Applications/JianMi.app

VERSION=$(plutil -extract CFBundleShortVersionString raw /Applications/JianMi.app/Contents/Info.plist)
echo ""
echo "✓ 简密 v$VERSION 已安装到 /Applications"
open /Applications/JianMi.app
