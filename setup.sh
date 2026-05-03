#!/bin/bash
# openclaw_ok 一键安装脚本
# 用途：在新电脑上从原版 openclaw 安装并应用所有补丁
set -e

OK_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "OpenClaw 一键安装"
echo "  补丁目录: $OK_DIR"
echo "========================================="

# 询问安装目录
TARGET_DIR="${1:-./openclaw}"

# 1. 下载原版 openclaw
if [ ! -d "$TARGET_DIR" ]; then
  echo ""
  echo "[1/4] 下载 openclaw v2026.4.10..."
  git clone --depth=1 --branch v2026.4.10 https://github.com/openclaw/openclaw.git "$TARGET_DIR"
else
  echo ""
  echo "[1/4] 使用已有目录: $TARGET_DIR"
fi

# 2. 复制补丁脚本和扩展
echo "[2/4] 复制补丁文件..."
cp "$OK_DIR"/apply-sessionkey-patch.sh "$TARGET_DIR/"
cp "$OK_DIR"/deploy.sh "$TARGET_DIR/" 2>/dev/null || true
cp -r "$OK_DIR/extensions/deepseek"/* "$TARGET_DIR/extensions/deepseek/"
cp -r "$OK_DIR/extensions/opencode-go"/* "$TARGET_DIR/extensions/opencode-go/"
mkdir -p "$TARGET_DIR/src/plugin-sdk"
cp "$OK_DIR/src/plugin-sdk/provider-stream-shared.ts" "$TARGET_DIR/src/plugin-sdk/"
echo "  ✓ 补丁文件已复制"

# 3. 执行一键部署
echo "[3/4] 执行部署..."
cd "$TARGET_DIR"
chmod +x deploy.sh apply-sessionkey-patch.sh
bash deploy.sh

# 4. 完成
echo "[4/4] 完成！"
echo ""
echo "========================================="
echo "安装完成！"
echo "========================================="
echo ""
echo "目录: $TARGET_DIR"
echo ""
echo "重启 Gateway: openclaw gateway restart"
echo ""
