#!/usr/bin/env bash
# 打包浏览器扩展：Chrome 系 + Firefox 两个 zip
# 产物: dist/jianmi-extension-{chrome,firefox}.zip
# 同时复制进 App 资源目录（App 内可一键导出安装）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
RES="$ROOT/apps/macos/JianMi/Resources"
mkdir -p "$OUT" "$RES"

# ── Chrome / Edge / Arc / Brave（Manifest V3, service worker）──
rm -f "$OUT/jianmi-extension-chrome.zip"
(cd "$ROOT/extension" && zip -qr "$OUT/jianmi-extension-chrome.zip" . -x ".*" -x "__MACOSX*")

# ── Firefox（MV3: background.scripts + gecko id）──
TMP="$(mktemp -d)"
cp -R "$ROOT/extension/." "$TMP/"
python3 - "$TMP/manifest.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
m = json.load(open(path))
m["background"] = {"scripts": ["background.js"]}
m["browser_specific_settings"] = {
    "gecko": {"id": "jianmi@jianmi.local", "strict_min_version": "115.0"}
}
json.dump(m, open(path, "w"), ensure_ascii=False, indent=2)
PYEOF
rm -f "$OUT/jianmi-extension-firefox.zip"
(cd "$TMP" && zip -qr "$OUT/jianmi-extension-firefox.zip" . -x ".*" -x "__MACOSX*")
rm -rf "$TMP"

# ── 打进 App 资源（设置 → 浏览器扩展 → 导出安装）──
cp "$OUT/jianmi-extension-chrome.zip" "$RES/"
cp "$OUT/jianmi-extension-firefox.zip" "$RES/"

echo "✓ dist/jianmi-extension-chrome.zip"
echo "✓ dist/jianmi-extension-firefox.zip"
echo "✓ 已同步到 App 资源目录"
