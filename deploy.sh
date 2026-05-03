#!/bin/bash
# OpenClaw 一键安装部署脚本
# 用途：在新环境或当前环境重新安装 openclaw（含 session key 和 deepseek v4 补丁）
set -e

OPENCLAW_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "OpenClaw 部署脚本"
echo "  目录: $OPENCLAW_DIR"
echo "========================================="

# 1. 应用 session key 补丁
echo ""
echo "[1/5] 应用 session key 补丁..."
bash "$OPENCLAW_DIR/apply-sessionkey-patch.sh"

# 2. 安装依赖
echo ""
echo "[2/5] 安装依赖..."
cd "$OPENCLAW_DIR"
pnpm install

# 3. 编译
echo ""
echo "[3/5] 编译..."
pnpm run build

# 4. 全局安装
echo ""
echo "[4/5] 全局安装..."
sudo npm i -g .

# 5. 安装扩展
echo ""
echo "[5/5] 安装 deepseek v4 和 opencode-go 扩展..."
DEST="/opt/homebrew/lib/node_modules/openclaw"
if [ -d "$DEST/extensions/deepseek" ]; then
  cp -r "$OPENCLAW_DIR/extensions/deepseek"/* "$DEST/extensions/deepseek/"
  echo "  ✓ deepseek 扩展已更新"
else
  echo "  ⚠ deepseek 扩展目录不存在，跳过"
fi
if [ -d "$DEST/extensions/opencode-go" ]; then
  cp -r "$OPENCLAW_DIR/extensions/opencode-go"/* "$DEST/extensions/opencode-go/"
  echo "  ✓ opencode-go 扩展已更新"
else
  echo "  ⚠ opencode-go 扩展目录不存在，跳过"
fi

echo ""
echo "========================================="
echo "部署完成！"
echo "========================================="
echo ""
echo "重启 Gateway: openclaw gateway restart"
echo ""
