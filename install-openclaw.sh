#!/bin/bash
# OpenClaw 一键安装脚本（Linux 版）
# 含 session key 补丁 + opencode-go/deepseek 扩展
# 用法：
#   curl -fsSL https://.../install-openclaw.sh | bash
#   或下载到本地后: bash install-openclaw.sh [/安装目录]
set -e

TARGET_DIR="${1:-/opt/openclaw}"
OS=$(uname -s)

echo "========================================="
echo "OpenClaw 一键安装 (Linux)"
echo "  安装目录: $TARGET_DIR"
echo "  系统: $OS"
echo "========================================="

# ==================== 步骤 1: 环境检查与安装 ====================
echo ""
echo "[1/7] 检查并安装依赖..."

# 检测包管理器
if command -v apt-get &> /dev/null; then
    PKG_MGR="apt"
elif command -v yum &> /dev/null; then
    PKG_MGR="yum"
elif command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
elif command -v apk &> /dev/null; then
    PKG_MGR="apk"
else
    echo "  ✗ 未检测到包管理器 (apt/yum/dnf/apk)"
    exit 1
fi
echo "  包管理器: $PKG_MGR"

# 安装 git
if ! command -v git &> /dev/null; then
    echo "  安装 git..."
    case $PKG_MGR in
        apt)  apt-get update && apt-get install -y git ;;
        yum)  yum install -y git ;;
        dnf)  dnf install -y git ;;
        apk)  apk add git ;;
    esac
fi
echo "  ✓ git: $(git --version)"

# 安装 Node.js (通过 NodeSource)
if ! command -v node &> /dev/null; then
    echo "  安装 Node.js 20..."
    case $PKG_MGR in
        apt)
            apt-get update && apt-get install -y curl
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            apt-get install -y nodejs
            ;;
        yum|dnf)
            curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
            $PKG_MGR install -y nodejs
            ;;
        apk)
            apk add nodejs npm
            ;;
    esac
fi
echo "  ✓ Node.js: $(node --version)"

# 安装 pnpm
if ! command -v pnpm &> /dev/null; then
    echo "  安装 pnpm..."
    npm install -g pnpm
fi
echo "  ✓ pnpm: $(pnpm --version)"

# ==================== 步骤 2: 下载原版 openclaw v2026.4.10 ====================
echo ""
echo "[2/7] 下载 openclaw v2026.4.10..."

if [ -d "$TARGET_DIR" ]; then
    echo "  目录已存在，跳过下载"
    echo "  如需重新下载: rm -rf $TARGET_DIR && 重新运行脚本"
else
    echo "  从 GitHub 克隆 v2026.4.10..."
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone --depth=1 --branch v2026.4.10 https://github.com/openclaw/openclaw.git "$TARGET_DIR"
    echo "  ✓ 源码已下载"
fi

cd "$TARGET_DIR"

# ==================== 步骤 2.5: 应用补丁 ====================
echo ""
echo "[2.5/7] 应用 session key 补丁..."

# 检查补丁文件是否存在（本地运行时有，远程管道运行时没有）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/patches/sessionkey.patch"

if [ -f "$PATCH_FILE" ]; then
    echo "  使用本地 patch 文件..."
    cp "$PATCH_FILE" "$TARGET_DIR/patches/"
    cp "$SCRIPT_DIR/apply-sessionkey-patch.sh" "$TARGET_DIR/" 2>/dev/null || true
    
    # 复制扩展
    for ext in deepseek opencode-go; do
        if [ -d "$SCRIPT_DIR/extensions/$ext" ]; then
            mkdir -p "$TARGET_DIR/extensions/$ext"
            cp -r "$SCRIPT_DIR/extensions/$ext/"* "$TARGET_DIR/extensions/$ext/"
            echo "  ✓ $ext 扩展已复制"
        fi
    done
    
    # 复制 plugin-sdk 补丁
    if [ -d "$SCRIPT_DIR/src/plugin-sdk" ]; then
        mkdir -p "$TARGET_DIR/src/plugin-sdk"
        cp "$SCRIPT_DIR/src/plugin-sdk/"* "$TARGET_DIR/src/plugin-sdk/" 2>/dev/null || true
    fi
    
    chmod +x "$TARGET_DIR/apply-sessionkey-patch.sh" 2>/dev/null || true
    cd "$TARGET_DIR"
    bash apply-sessionkey-patch.sh --method auto
else
    echo "  未找到本地补丁文件，尝试直接修改源码..."
    
    # 直接应用补丁修改（适用于管道安装场景）
    FILE1="src/agents/pi-bundle-mcp-materialize.ts"
    FILE2="src/agents/pi-embedded-runner/compact.ts"
    FILE3="src/routing/resolve-route.ts"
    FILE4="src/agents/pi-embedded-runner/run/attempt.ts"
    
    # FILE1: 添加 sessionKey 参数
    if ! grep -q "sessionKey?: string;" "$FILE1" 2>/dev/null; then
        echo "  修改 $FILE1..."
        sed -i 's/reservedToolNames?: Iterable<string>;/reservedToolNames?: Iterable<string>;\n  sessionKey?: string;/' "$FILE1"
        sed -i 's/sessionId: `bundle-mcp:${crypto.randomUUID()}`,/sessionId: `bundle-mcp:${crypto.randomUUID()}`,\n    sessionKey: params.sessionKey,/' "$FILE1"
        sed -i 's/reservedToolNames: params.reservedToolNames,/reservedToolNames: params.reservedToolNames,\n    sessionKey: params.sessionKey,/' "$FILE1"
        
        # 注入 _meta.sessionKey
        if ! grep -q '_meta.*sessionKey' "$FILE1"; then
            sed -i '/execute: async (_toolCallId: string, input: unknown) => {/a\
        // 注入 sessionKey 到 _meta\
        if (params.sessionKey) {\
          const inputObj = (typeof input === '\''object'\'' \&\& input !== null ? input : {}) as Record<string, unknown>;\
          if (!inputObj._meta) inputObj._meta = {};\
          (inputObj._meta as Record<string, unknown>).sessionKey = params.sessionKey;\
          input = inputObj;\
        }' "$FILE1"
        fi
        echo "    ✓ $FILE1 已修改"
    fi
    
    # FILE2: 传递 sessionKey
    if ! grep -A1 "reservedToolNames: tools.map" "$FILE2" 2>/dev/null | grep -q "sessionKey"; then
        echo "  修改 $FILE2..."
        sed -i 's/reservedToolNames: tools.map((tool) => tool.name),/reservedToolNames: tools.map((tool) => tool.name),\n          sessionKey: params.sessionKey,/' "$FILE2"
        echo "    ✓ $FILE2 已修改"
    fi
    
    # FILE3: normalizeId 小写
    if ! grep -q 'value.trim().toLowerCase()' "$FILE3" 2>/dev/null; then
        echo "  修改 $FILE3..."
        sed -i 's/return value\.trim();/return value.trim().toLowerCase();/' "$FILE3"
        sed -i 's/return String(value)\.trim();/return String(value).trim().toLowerCase();/' "$FILE3"
        echo "    ✓ $FILE3 已修改"
    fi
    
    # FILE4: 传递 sessionKey
    if ! grep -q 'sessionKey: params.sessionKey,' "$FILE4" 2>/dev/null; then
        echo "  修改 $FILE4..."
        sed -i 's/\.\.\.(clientTools?.map((tool) => tool\.function\.name) ?? \[\]),/\.\.\.(clientTools?.map((tool) => tool.function.name) ?? []),\n          sessionKey: params.sessionKey,/' "$FILE4"
        echo "    ✓ $FILE4 已修改"
    fi
    
    echo "  ✓ 补丁已应用"
fi

# ==================== 步骤 3: 安装依赖 ====================
echo ""
echo "[3/7] 安装依赖..."

pnpm install

# ==================== 步骤 4: 编译 ====================
echo ""
echo "[4/7] 编译..."

pnpm run build

# ==================== 步骤 5: 全局安装 ====================
echo ""
echo "[5/7] 全局安装..."

sudo npm i -g .

echo "  ✓ openclaw 已安装: $(openclaw --version 2>/dev/null || echo 'ok')"

# ==================== 步骤 6: 安装扩展 ====================
echo ""
echo "[6/7] 安装扩展..."

# Linux 上 npm 全局安装路径
DEST=$(npm root -g)/openclaw

if [ -d "$DEST" ]; then
    echo "  安装目录: $DEST"
    
    for ext in deepseek opencode-go; do
        if [ -d "$TARGET_DIR/extensions/$ext" ]; then
            mkdir -p "$DEST/extensions/$ext"
            cp -r "$TARGET_DIR/extensions/$ext/"* "$DEST/extensions/$ext/"
            echo "  ✓ $ext 扩展已安装"
        fi
    done
else
    echo "  ⚠️  未找到 openclaw 安装目录: $DEST"
fi

# ==================== 步骤 7: 配置 ====================
echo ""
echo "[7/7] 初始化配置..."

if [ ! -d "$HOME/.openclaw" ]; then
    echo "  创建配置目录..."
    mkdir -p "$HOME/.openclaw"
fi

echo "  ✓ 配置目录: $HOME/.openclaw"

# ==================== 完成 ====================
echo ""
echo "========================================="
echo "安装完成！"
echo "========================================="
echo ""
echo "下一步："
echo "  1. 初始化:    openclaw onboard --install-daemon"
echo "  2. 启动:      openclaw gateway start"
echo "  3. 验证模型:  openclaw models list"
echo ""
echo "管理命令："
echo "  查看状态:  openclaw gateway status"
echo "  查看日志:  openclaw gateway logs"
echo "  重启:      openclaw gateway restart"
echo "  停止:      openclaw gateway stop"
echo ""
