#!/bin/bash
# OpenClaw Session Key 补丁部署脚本
# 功能：编译本地 OpenClaw 源码（含 sessionKey 补丁），上传到服务器并重启服务
# 用法：./deploy-patch.sh [--skip-build] [--check-only]
#
# 参数说明：
#   --skip-build   跳过本地编译，直接上传已编译的 dist 目录
#   --check-only   仅检查服务器补丁状态，不执行部署

set -e

# 配置
SERVER="root@jxgy.52iptv.net"
OPENCLAW_DIR="/Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw"
SERVER_OPENCLAW_PATH="/usr/lib/node_modules/openclaw"
TEMP_DIR="/tmp/openclaw-deploy-$$"
SKIP_BUILD=false
CHECK_ONLY=false

# 解析参数
for arg in "$@"; do
    case $arg in
        --skip-build) SKIP_BUILD=true ;;
        --check-only) CHECK_ONLY=true ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

echo "========================================="
echo "OpenClaw Session Key 补丁部署脚本"
echo "========================================="

# 检查本地 openclaw 目录
if [ ! -d "$OPENCLAW_DIR" ]; then
    echo "错误：本地 OpenClaw 目录不存在: $OPENCLAW_DIR"
    exit 1
fi

cd "$OPENCLAW_DIR"

# 检查本地补丁状态
echo ""
echo "[检查] 本地补丁状态..."
PATCH_COUNT=$(git diff HEAD -- src/agents/pi-bundle-mcp-materialize.ts src/agents/pi-embedded-runner/compact.ts | grep -c '^[+-]' | grep -v '^[+-][+-][+-]' || true)
if [ "$PATCH_COUNT" -gt 0 ]; then
    echo "  ✓ 检测到 sessionKey 补丁（$PATCH_COUNT 行变更）"
    git diff HEAD --stat -- src/agents/pi-bundle-mcp-materialize.ts src/agents/pi-embedded-runner/compact.ts | sed 's/^/    /'
else
    echo "  ⚠ 未检测到 sessionKey 补丁变更"
fi

# 检查服务器补丁状态
echo ""
echo "[检查] 服务器补丁状态..."
SESSION_KEY_COUNT=$(ssh "$SERVER" "grep -c 'sessionKey: params.sessionKey' /usr/lib/node_modules/openclaw/dist/pi-embedded-runner-*.js 2>/dev/null || echo 0")
if [ "$SESSION_KEY_COUNT" -gt 0 ]; then
    echo "  ✓ 服务器已包含 sessionKey 补丁（$SESSION_KEY_COUNT 处匹配）"
else
    echo "  ✗ 服务器未包含 sessionKey 补丁"
fi

if [ "$CHECK_ONLY" = true ]; then
    echo ""
    echo "检查完成，退出。"
    exit 0
fi

# 安装依赖（如果需要）
echo ""
echo "[1/5] 检查依赖..."
if [ ! -d "node_modules" ]; then
    echo "  安装依赖 (bun install)..."
    bun install
else
    echo "  依赖已存在"
fi

# 编译（可选）
if [ "$SKIP_BUILD" = false ]; then
    echo ""
    echo "[2/5] 编译 OpenClaw..."
    echo "  执行: bun run build"
    bun run build
else
    echo ""
    echo "[2/5] 跳过编译（使用已有 dist 目录）"
fi

# 打包
echo ""
echo "[3/5] 打包编译产物..."
mkdir -p "$TEMP_DIR"
tar czf "$TEMP_DIR/openclaw-dist.tar.gz" dist/
PACKAGE_SIZE=$(du -h "$TEMP_DIR/openclaw-dist.tar.gz" | cut -f1)
echo "  打包完成: $PACKAGE_SIZE"

# 上传
echo ""
echo "[4/5] 上传到服务器..."
scp "$TEMP_DIR/openclaw-dist.tar.gz" "$SERVER:/tmp/openclaw-dist.tar.gz"
echo "  上传完成"

# 部署
echo ""
echo "[5/5] 部署到服务器..."
ssh "$SERVER" << 'DEPLOY_SCRIPT'
set -e
OPENCLAW_PATH="/usr/lib/node_modules/openclaw"
BACKUP_PATH="$OPENCLAW_PATH/dist.bak.$(date +%s)"

echo "  备份现有 dist 目录..."
cp -r "$OPENCLAW_PATH/dist" "$BACKUP_PATH"

echo "  解压新编译的 dist 目录..."
cd "$OPENCLAW_PATH"
rm -rf dist
tar xzf /tmp/openclaw-dist.tar.gz

echo "  设置权限..."
chown -R root:root "$OPENCLAW_PATH/dist"
chmod -R 755 "$OPENCLAW_PATH/dist"

echo "  验证部署..."
JS_COUNT=$(find "$OPENCLAW_PATH/dist" -name "*.js" | wc -l)
if [ "$JS_COUNT" -gt 100 ]; then
    echo "  ✓ dist 目录已更新（$JS_COUNT 个 JS 文件）"
else
    echo "  ✗ 部署失败（JS 文件数量异常），正在恢复..."
    rm -rf "$OPENCLAW_PATH/dist"
    mv "$BACKUP_PATH" "$OPENCLAW_PATH/dist"
    exit 1
fi

echo "  重启 OpenClaw 服务..."
# 查找并重启 openclaw 进程
if pgrep -f "openclaw gateway" > /dev/null; then
    echo "  停止现有进程..."
    pkill -f "openclaw gateway" || true
    sleep 2
fi

echo "  启动 OpenClaw..."
cd /root
nohup openclaw gateway > /var/log/openclaw.log 2>&1 &
sleep 3

if pgrep -f "openclaw gateway" > /dev/null; then
    echo "  ✓ OpenClaw 已重启"
    openclaw --version
else
    echo "  ✗ OpenClaw 启动失败，正在恢复..."
    rm -rf "$OPENCLAW_PATH/dist"
    mv "$BACKUP_PATH" "$OPENCLAW_PATH/dist"
    cd /root
    nohup openclaw gateway > /var/log/openclaw.log 2>&1 &
    exit 1
fi

# 清理
rm -f /tmp/openclaw-dist.tar.gz
echo "  部署完成！"
DEPLOY_SCRIPT

# 清理本地临时文件
rm -rf "$TEMP_DIR"

echo ""
echo "========================================="
echo "部署完成！"
echo "========================================="
echo ""
echo "验证命令："
echo "  ssh $SERVER 'openclaw --version'"
echo "  ssh $SERVER 'tail -20 /var/log/openclaw.log'"
echo "  ssh $SERVER \"grep -c 'sessionKey: params.sessionKey' /usr/lib/node_modules/openclaw/dist/pi-embedded-runner-*.js\""
