#!/usr/bin/env bash
# 构建可分发的 DMG 安装镜像（拖入 Applications 即装）
# 产物: dist/JianMi-<版本>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
mkdir -p "$OUT"

VERSION="$(grep 'MARKETING_VERSION' "$ROOT/apps/macos/project.yml" | head -1 | awk '{print $2}')"

echo "── 1/3 打包浏览器扩展…"
"$ROOT/scripts/build_extension.sh"

echo "── 2/3 Release 构建（ad-hoc 签名）…"
cd "$ROOT/apps/macos"
xcodegen generate >/dev/null
xcodebuild -project JianMi.xcodeproj -scheme JianMi -configuration Release \
    -derivedDataPath "$OUT/DerivedData" build 2>&1 | grep -E "^\*\* BUILD" || true

APP="$OUT/DerivedData/Build/Products/Release/JianMi.app"
[ -d "$APP" ] || { echo "构建失败"; exit 1; }

echo "── 3/3 生成 DMG…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$OUT/JianMi-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "简密 JianMi" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo ""
echo "✓ $DMG"
echo "  提示: 未经公证的 App 首次打开需 右键 → 打开，"
echo "  或执行: xattr -cr /Applications/JianMi.app"
