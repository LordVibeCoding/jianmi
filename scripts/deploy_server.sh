#!/usr/bin/env bash
# 简密服务端一键部署脚本
# 用法: ./scripts/deploy_server.sh user@your-server-ip [端口]
set -euo pipefail

REMOTE="${1:?用法: $0 user@server-ip [端口，默认8787]}"
PORT="${2:-8787}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "── 1/3 交叉编译（Linux x86_64）…"
cd "$DIR/server"
if ! rustup target list --installed | grep -q x86_64-unknown-linux-musl; then
    rustup target add x86_64-unknown-linux-musl
fi
# musl 静态链接：产物零依赖，任何 Linux 直接跑
if command -v cargo-zigbuild >/dev/null; then
    cargo zigbuild --release --target x86_64-unknown-linux-musl
else
    echo "提示: brew install cargo-zigbuild zig 可获得最顺滑的交叉编译体验"
    cargo build --release --target x86_64-unknown-linux-musl
fi
BIN="target/x86_64-unknown-linux-musl/release/jianmi-server"

echo "── 2/3 上传…"
ssh "$REMOTE" "mkdir -p ~/jianmi"
scp "$BIN" "$REMOTE:~/jianmi/jianmi-server"
scp "$DIR/scripts/jianmi-server.service" "$REMOTE:~/jianmi/"

echo "── 3/3 安装 systemd 服务…"
ssh "$REMOTE" bash -s <<EOF
chmod +x ~/jianmi/jianmi-server
sed -i "s|__HOME__|\$HOME|g; s|__PORT__|$PORT|g" ~/jianmi/jianmi-server.service
sudo mv ~/jianmi/jianmi-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now jianmi-server
sleep 1
sudo systemctl status jianmi-server --no-pager | head -5
echo ""
echo "访问令牌:"
cat \$HOME/jianmi/data/token.txt 2>/dev/null || echo "(首次启动日志里查看: journalctl -u jianmi-server)"
EOF

echo ""
echo "✓ 部署完成: http://\$(ssh $REMOTE 'curl -s ifconfig.me'):$PORT"
echo "  把地址和令牌填入简密 App 的 设置 → 同步 即可。"
