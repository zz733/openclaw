#!/bin/bash
# OpenClaw 升级 + SessionKey 补丁完整自动化脚本
# 功能：
#   1. 检查服务器 openclaw 版本
#   2. 从官方仓库下载对应版本的源码（智能覆盖，保留自定义文件）
#   3. 动态修改源码添加 sessionKey 支持
#   4. 编译并部署到服务器
#
# 用法：
#   ./upgrade-and-patch.sh              # 完整流程
#   ./upgrade-and-patch.sh --skip-sync  # 跳过版本同步（本地已对齐）
#   ./upgrade-and-patch.sh --check-only # 仅检查版本状态
#   ./upgrade-and-patch.sh --skip-deploy # 仅下载到本地并打补丁，不部署

set -e

# ==================== 配置区 ====================
SERVER="root@jxgy.52iptv.net"
OFFICIAL_REPO="https://github.com/openclaw/openclaw.git"
WORK_DIR="/Users/liuguanghua/CascadeProjects/openclaw-erp"
OPENCLAW_DIR="$WORK_DIR/openclaw"
SERVER_OPENCLAW_PATH="/usr/lib/node_modules/openclaw"
TEMP_DIR="/tmp/openclaw-deploy-$$"
SKIP_SYNC=false
CHECK_ONLY=false
SKIP_DEPLOY=false
PATCH_METHOD="auto"

# 解析参数
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-sync)
            SKIP_SYNC=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --patch-method)
            if [ -z "${2:-}" ]; then
                echo "错误: --patch-method 需要参数 (sed|git|auto)"
                echo "用法: $0 [--skip-sync] [--check-only] [--skip-deploy] [--patch-method sed|git|auto]"
                exit 1
            fi
            PATCH_METHOD="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--skip-sync] [--check-only] [--skip-deploy] [--patch-method sed|git|auto]"
            exit 1
            ;;
    esac
done

if [ "$PATCH_METHOD" != "sed" ] && [ "$PATCH_METHOD" != "git" ] && [ "$PATCH_METHOD" != "auto" ]; then
    echo "错误: --patch-method 仅支持 sed 、 git 或 auto"
    exit 1
fi

echo "========================================="
echo "OpenClaw 升级 + SessionKey 补丁自动化"
echo "========================================="

# ==================== 步骤 1: 检查服务器版本 ====================
echo ""
echo "[步骤 1/6] 检查服务器 OpenClaw 版本..."
SERVER_VERSION=$(ssh "$SERVER" "openclaw --version 2>/dev/null | head -1" || echo "unknown")
echo "  服务器版本: $SERVER_VERSION"

# 提取版本号（如 2026.4.11）
VERSION_NUM=$(echo "$SERVER_VERSION" | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+' || echo "")
if [ -z "$VERSION_NUM" ]; then
    echo "  ⚠️  无法解析版本号"
    read -p "请手动输入服务器版本号 (如 2026.4.11): " VERSION_NUM
    if [ -z "$VERSION_NUM" ]; then
        echo "错误：未提供版本号"
        exit 1
    fi
fi

# ==================== 步骤 2: 下载官方源码（智能覆盖） ====================
echo ""
echo "[步骤 2/6] 下载官方 OpenClaw 源码 (版本: $VERSION_NUM)..."

if [ "$CHECK_ONLY" = true ]; then
    echo "  检查模式，跳过下载"
    exit 0
fi

if [ "$SKIP_SYNC" = false ]; then
    # 创建临时目录下载官方源码
    TEMP_CLONE_DIR="$WORK_DIR/.openclaw-temp-$VERSION_NUM"
    
    # 如果临时目录已存在，先清理
    if [ -d "$TEMP_CLONE_DIR" ]; then
        echo "  清理旧的临时目录..."
        rm -rf "$TEMP_CLONE_DIR"
    fi
    
    # 克隆官方仓库到临时目录
    echo "  克隆官方仓库到临时目录..."
    git clone --depth 1 --branch "v$VERSION_NUM" "$OFFICIAL_REPO" "$TEMP_CLONE_DIR" 2>/dev/null || {
        echo "  ⚠️  未找到 tag v$VERSION_NUM，尝试使用版本号..."
        git clone --depth 1 --branch "$VERSION_NUM" "$OFFICIAL_REPO" "$TEMP_CLONE_DIR" 2>/dev/null || {
            echo "  ✗ 克隆失败，尝试克隆 main 分支..."
            git clone --depth 1 "$OFFICIAL_REPO" "$TEMP_CLONE_DIR"
        }
    }
    
    cd "$TEMP_CLONE_DIR"
    
    # 获取官方文件列表
    OFFICIAL_FILES=$(git ls-files)
    OFFICIAL_FILE_COUNT=$(echo "$OFFICIAL_FILES" | wc -l | tr -d ' ')
    echo "  官方版本包含 $OFFICIAL_FILE_COUNT 个文件"
    
    # 智能覆盖：只覆盖官方文件，保留自定义文件
    if [ -d "$OPENCLAW_DIR" ]; then
        echo "  检测到现有目录: $OPENCLAW_DIR"
        echo "  使用智能覆盖模式（保留自定义文件）..."
        
        # 统计自定义文件
        CUSTOM_FILES=()
        cd "$OPENCLAW_DIR"
        while IFS= read -r file; do
            file="${file#./}"  # 移除开头的 ./
            if [ -n "$file" ] && [[ ! "$file" =~ ^node_modules/ ]] && [[ ! "$file" =~ ^dist/ ]] && [[ ! "$file" =~ ^\.git/ ]]; then
                if ! echo "$OFFICIAL_FILES" | grep -q "^${file}$"; then
                    CUSTOM_FILES+=("$file")
                fi
            fi
        done < <(find . -type f | head -10000)
        
        if [ ${#CUSTOM_FILES[@]} -gt 0 ]; then
            echo "  发现 ${#CUSTOM_FILES[@]} 个自定义文件（将被保留）："
            for file in "${CUSTOM_FILES[@]}"; do
                echo "    - $file"
            done
        else
            echo "  未发现自定义文件"
        fi
        
        # 删除旧的官方文件
        echo "  清理旧的官方文件..."
        cd "$OPENCLAW_DIR"
        DELETE_COUNT=0
        while IFS= read -r file; do
            if [ -f "$file" ]; then
                rm -f "$file"
                DELETE_COUNT=$((DELETE_COUNT + 1))
            fi
        done <<< "$OFFICIAL_FILES"
        echo "  已删除 $DELETE_COUNT 个旧文件"
        
        # 复制新的官方文件
        echo "  复制新的官方文件..."
        cd "$TEMP_CLONE_DIR"
        COPY_COUNT=0
        while IFS= read -r file; do
            file_dir=$(dirname "$file")
            mkdir -p "$OPENCLAW_DIR/$file_dir"
            cp "$file" "$OPENCLAW_DIR/$file"
            COPY_COUNT=$((COPY_COUNT + 1))
        done <<< "$OFFICIAL_FILES"
        echo "  已复制 $COPY_COUNT 个新文件"
        
    else
        # 如果目标目录不存在，直接移动
        echo "  目标目录不存在，直接移动..."
        mv "$TEMP_CLONE_DIR" "$OPENCLAW_DIR"
    fi
    
    # 清理临时目录
    if [ -d "$TEMP_CLONE_DIR" ]; then
        rm -rf "$TEMP_CLONE_DIR"
    fi
    
    cd "$OPENCLAW_DIR"
    
    # 安装依赖
    echo "  安装依赖..."
    if command -v bun &> /dev/null; then
        bun install
    elif command -v npm &> /dev/null; then
        npm install
    else
        echo "  ✗ 未找到 bun 或 npm"
        exit 1
    fi
else
    echo "  跳过版本同步（--skip-sync）"
    cd "$OPENCLAW_DIR"
fi

# ==================== 步骤 3: 动态应用 SessionKey 补丁 ====================
echo ""
echo "[步骤 3/6] 应用 SessionKey 补丁到官方源码..."
echo "  补丁方式: $PATCH_METHOD"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_SCRIPT="$SCRIPT_DIR/apply-sessionkey-patch.sh"

if [ ! -f "$PATCH_SCRIPT" ]; then
    echo "  ✗ 补丁脚本不存在: $PATCH_SCRIPT"
    exit 1
fi

# 应用补丁
bash "$PATCH_SCRIPT" --method "$PATCH_METHOD"

# 验证补丁
echo ""
echo "  验证补丁..."
if bash "$PATCH_SCRIPT" --check --method "$PATCH_METHOD" 2>&1 | grep -q "✓"; then
    echo "  ✓ 补丁验证成功"
else
    echo "  ✗ 补丁验证失败"
    echo "  请检查修改："
    echo "    git diff src/agents/pi-bundle-mcp-materialize.ts src/agents/pi-embedded-runner/compact.ts"
    read -p "是否继续？(y/N): " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        echo "已取消"
        exit 1
    fi
fi

if [ "$CHECK_ONLY" = true ] || [ "$SKIP_DEPLOY" = true ]; then
    echo ""
    echo "========================================="
    echo "源码下载和补丁应用完成！"
    echo "========================================="
    echo "源码位置: $OPENCLAW_DIR"
    echo ""
    echo "手动编译："
    echo "  cd $OPENCLAW_DIR"
    echo "  bun run build"
    echo ""
    echo "手动部署："
    echo "  ./deploy-patch.sh --skip-build"
    exit 0
fi

# ==================== 步骤 4: 编译 ====================
echo ""
echo "[步骤 4/6] 编译 OpenClaw..."
echo "  执行: bun run build"
bun run build
echo "  ✓ 编译完成"

# ==================== 步骤 5: 打包上传 ====================
echo ""
echo "[步骤 5/6] 打包并上传到服务器..."

mkdir -p "$TEMP_DIR"
echo "  打包编译产物..."
tar czf "$TEMP_DIR/openclaw-dist.tar.gz" -C "$OPENCLAW_DIR" dist/
PACKAGE_SIZE=$(du -h "$TEMP_DIR/openclaw-dist.tar.gz" | cut -f1)
echo "  打包完成: $PACKAGE_SIZE"

echo "  上传到服务器..."
scp "$TEMP_DIR/openclaw-dist.tar.gz" "$SERVER:/tmp/openclaw-dist.tar.gz"
echo "  ✓ 上传完成"

# ==================== 步骤 6: 部署到服务器 ====================
echo ""
echo "[步骤 6/6] 部署到服务器..."

ssh "$SERVER" << 'DEPLOY_SCRIPT'
set -e
OPENCLAW_PATH="/usr/lib/node_modules/openclaw"
BACKUP_PATH="$OPENCLAW_PATH/dist.bak.$(date +%s)"

echo "    备份现有 dist 目录..."
cp -r "$OPENCLAW_PATH/dist" "$BACKUP_PATH"

echo "    解压新编译的 dist 目录..."
cd "$OPENCLAW_PATH"
rm -rf dist
tar xzf /tmp/openclaw-dist.tar.gz

echo "    设置权限..."
chown -R root:root "$OPENCLAW_PATH/dist"
chmod -R 755 "$OPENCLAW_PATH/dist"

echo "    验证部署..."
JS_COUNT=$(find "$OPENCLAW_PATH/dist" -name "*.js" | wc -l)
if [ "$JS_COUNT" -gt 100 ]; then
    echo "    ✓ dist 目录已更新（$JS_COUNT 个 JS 文件）"
else
    echo "    ✗ 部署失败（JS 文件数量异常），正在恢复..."
    rm -rf "$OPENCLAW_PATH/dist"
    mv "$BACKUP_PATH" "$OPENCLAW_PATH/dist"
    exit 1
fi

echo "    重启 OpenClaw 服务..."
if pgrep -f "openclaw gateway" > /dev/null; then
    echo "    停止现有进程..."
    pkill -f "openclaw gateway" || true
    sleep 2
fi

echo "    启动 OpenClaw..."
cd /root
nohup openclaw gateway > /var/log/openclaw.log 2>&1 &
sleep 3

if pgrep -f "openclaw gateway" > /dev/null; then
    echo "    ✓ OpenClaw 已重启"
    openclaw --version
else
    echo "    ✗ OpenClaw 启动失败，正在恢复..."
    rm -rf "$OPENCLAW_PATH/dist"
    mv "$BACKUP_PATH" "$OPENCLAW_PATH/dist"
    cd /root
    nohup openclaw gateway > /var/log/openclaw.log 2>&1 &
    exit 1
fi

rm -f /tmp/openclaw-dist.tar.gz
echo "    ✓ 部署完成！"
DEPLOY_SCRIPT

# 清理
rm -rf "$TEMP_DIR"

echo ""
echo "========================================="
echo "升级 + 补丁部署完成！"
echo "========================================="
echo ""
echo "验证命令："
echo "  ssh $SERVER 'openclaw --version'"
echo "  ssh $SERVER 'tail -30 /var/log/openclaw.log'"
echo "  ssh $SERVER \"grep -c 'sessionKey: params.sessionKey' $SERVER_OPENCLAW_PATH/dist/pi-embedded-runner-*.js\""
echo ""
echo "回滚命令（如果出现问题）："
echo "  ssh $SERVER 'cd $SERVER_OPENCLAW_PATH && rm -rf dist && mv dist.bak.* dist && pkill -f \"openclaw gateway\" && nohup openclaw gateway > /var/log/openclaw.log 2>&1 &'"
