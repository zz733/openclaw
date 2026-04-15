#!/bin/bash
# 动态应用 SessionKey 补丁到官方 OpenClaw 源码
# 用法：
#   ./apply-sessionkey-patch.sh              # 应用到当前源码
#   ./apply-sessionkey-patch.sh --check      # 检查是否已应用
#   ./apply-sessionkey-patch.sh --revert     # 撤销补丁

set -e

OPENCLAW_DIR="/Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw"
CHECK_MODE=false
REVERT_MODE=false

# 解析参数
for arg in "$@"; do
    case $arg in
        --check) CHECK_MODE=true ;;
        --revert) REVERT_MODE=true ;;
        *) echo "未知参数: $arg"; echo "用法: $0 [--check] [--revert]"; exit 1 ;;
    esac
done

echo "========================================="
echo "SessionKey 补丁动态应用脚本"
echo "========================================="

cd "$OPENCLAW_DIR"

# ==================== 文件 1: pi-bundle-mcp-materialize.ts ====================
FILE1="src/agents/pi-bundle-mcp-materialize.ts"

echo ""
echo "[处理] $FILE1"

if [ "$CHECK_MODE" = true ]; then
    # 检查模式
    if grep -q "sessionKey?: string;" "$FILE1" && grep -q "sessionKey: params.sessionKey," "$FILE1"; then
        echo "  ✓ 补丁已应用"
    else
        echo "  ✗ 补丁未应用"
    fi
    exit 0
fi

if [ "$REVERT_MODE" = true ]; then
    # 撤销模式
    echo "  撤销补丁..."
    
    # 删除 sessionKey?: string; 行
    sed -i.bak '/sessionKey?: string;/d' "$FILE1"
    
    # 删除 sessionKey: params.sessionKey, 行
    sed -i.bak '/sessionKey: params.sessionKey,/d' "$FILE1"
    
    # 清理备份文件
    rm -f "${FILE1}.bak"
    
    echo "  ✓ 补丁已撤销"
    exit 0
fi

# 应用模式
echo "  应用补丁..."

# 检查是否已应用
if grep -q "sessionKey?: string;" "$FILE1"; then
    echo "  ⚠️  补丁可能已应用，跳过"
else
    # 在 reservedToolNames?: Iterable<string>; 后添加 sessionKey?: string;
    sed -i.bak 's/reservedToolNames?: Iterable<string>;/reservedToolNames?: Iterable<string>;\n  sessionKey?: string;/' "$FILE1"
    
    # 在 sessionId: `bundle-mcp:${crypto.randomUUID()}`, 后添加 sessionKey: params.sessionKey,
    sed -i.bak 's/sessionId: `bundle-mcp:${crypto.randomUUID()}`,/sessionId: `bundle-mcp:${crypto.randomUUID()}`,\n    sessionKey: params.sessionKey,/' "$FILE1"
    
    # 清理备份文件
    rm -f "${FILE1}.bak"
    
    echo "  ✓ 补丁已应用"
fi

# ==================== 文件 2: pi-embedded-runner/compact.ts ====================
FILE2="src/agents/pi-embedded-runner/compact.ts"

echo ""
echo "[处理] $FILE2"

if [ "$REVERT_MODE" = true ]; then
    # 撤销模式
    echo "  撤销补丁..."
    
    # 删除 reservedToolNames: tools.map((tool) => tool.name), 后面的 sessionKey 行
    sed -i.bak '/reservedToolNames: tools.map((tool) => tool.name),/{n;/sessionKey: params.sessionKey,/d;}' "$FILE2"
    
    # 清理备份文件
    rm -f "${FILE2}.bak"
    
    echo "  ✓ 补丁已撤销"
    exit 0
fi

# 应用模式
echo "  应用补丁..."

# 检查是否已应用
if grep -A1 "reservedToolNames: tools.map((tool) => tool.name)," "$FILE2" | grep -q "sessionKey: params.sessionKey,"; then
    echo "  ⚠️  补丁可能已应用，跳过"
else
    # 在 reservedToolNames: tools.map((tool) => tool.name), 后添加 sessionKey: params.sessionKey,
    sed -i.bak 's/reservedToolNames: tools.map((tool) => tool.name),/reservedToolNames: tools.map((tool) => tool.name),\n          sessionKey: params.sessionKey,/' "$FILE2"
    
    # 清理备份文件
    rm -f "${FILE2}.bak"
    
    echo "  ✓ 补丁已应用"
fi

# ==================== 文件 3: resolve-route.ts (normalizeId 大小写无关修复) ====================
FILE3="src/routing/resolve-route.ts"

echo ""
echo "[处理] $FILE3 - normalizeId peer.id 大小写无关修复"

if [ "$CHECK_MODE" = true ]; then
    if grep -q 'value.trim().toLowerCase()' "$FILE3"; then
        echo "  ✓ normalizeId 补丁已应用"
    else
        echo "  ✗ normalizeId 补丁未应用"
    fi
    # 不退出，继续检查其他补丁
    echo ""
    echo "========================================="
    echo "补丁检查完成！"
    echo "========================================="
    exit 0
fi

if [ "$REVERT_MODE" = true ]; then
    echo "  撤销 normalizeId 补丁..."
    # 恢复 .trim().toLowerCase() 为 .trim()
    sed -i.bak 's/\.trim()\.toLowerCase()/\.trim()/g' "$FILE3"
    rm -f "${FILE3}.bak"
    echo "  ✓ normalizeId 补丁已撤销"
    echo ""
    echo "========================================="
    echo "补丁撤销完成！"
    echo "========================================="
    exit 0
fi

# 应用模式
echo "  应用补丁..."

# 检查是否已应用
if grep -q 'value.trim().toLowerCase()' "$FILE3"; then
    echo "  ⚠️  normalizeId 补丁可能已应用，跳过"
else
    # 将 normalizeId 函数中的 .trim() 改为 .trim().toLowerCase()
    # 匹配两种模式：string 和 number/bigint
    sed -i.bak 's/return value\.trim();/return value.trim().toLowerCase();/' "$FILE3"
    sed -i.bak 's/return String(value)\.trim();/return String(value).trim().toLowerCase();/' "$FILE3"
    rm -f "${FILE3}.bak"
    echo "  ✓ normalizeId 补丁已应用"
fi

echo ""
echo "========================================="
echo "补丁应用完成！"
echo "========================================="
echo ""
echo "验证修改："
echo "  git diff $FILE1 $FILE2 $FILE3"
echo ""
echo "编译："
echo "  bun run build"
