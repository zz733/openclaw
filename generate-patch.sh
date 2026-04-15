#!/bin/bash
# 生成 SessionKey 补丁文件
# 用法：
#   ./generate-patch.sh                    # 生成所有修改的补丁
#   ./generate-patch.sh --name my-patch    # 指定补丁名称

set -e

PATCH_DIR="/Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw-patches"
OPENCLAW_DIR="/Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw"

# 解析参数
PATCH_NAME="session-key-$(date +%Y%m%d-%H%M%S)"
for arg in "$@"; do
    case $arg in
        --name) PATCH_NAME="$2"; shift 2 ;;
        *) echo "未知参数: $arg"; echo "用法: $0 [--name <patch-name>]"; exit 1 ;;
    esac
done

echo "========================================="
echo "生成 OpenClaw SessionKey 补丁"
echo "========================================="

cd "$OPENCLAW_DIR"

# 检查是否有修改
if [ -z "$(git status --porcelain)" ]; then
    echo "✗ 当前没有未提交的修改"
    echo "请先修改源码，然后运行此脚本"
    exit 1
fi

# 创建补丁目录
mkdir -p "$PATCH_DIR"

# 生成补丁
PATCH_FILE="$PATCH_DIR/$PATCH_NAME.patch"
git diff HEAD > "$PATCH_FILE"

# 统计变更
LINES_CHANGED=$(git diff HEAD | grep -c '^[+-]' | grep -v '^[+-][+-][+-]' || true)
FILES_CHANGED=$(git diff HEAD --name-only | wc -l | tr -d ' ')

echo ""
echo "补丁已生成: $PATCH_FILE"
echo "  变更文件数: $FILES_CHANGED"
echo "  变更行数: $LINES_CHANGED"
echo ""
echo "变更文件列表:"
git diff HEAD --name-only | sed 's/^/  - /'
echo ""
echo "补丁预览（前 50 行）:"
echo "---"
head -50 "$PATCH_FILE"
echo "..."
echo ""
echo "========================================="
echo "使用此补丁："
echo "  cd $OPENCLAW_DIR"
echo "  git apply $PATCH_FILE"
echo ""
echo "撤销此补丁："
echo "  git apply -R $PATCH_FILE"
echo "========================================="
