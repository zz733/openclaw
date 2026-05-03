#!/bin/bash
# 动态应用 SessionKey/normalizeId 补丁到 OpenClaw 源码
# 默认保留原有 sed 方式，并新增 git patch 方式。
# 用法：
#   ./apply-sessionkey-patch.sh
#   ./apply-sessionkey-patch.sh --method sed
#   ./apply-sessionkey-patch.sh --method git
#   ./apply-sessionkey-patch.sh --method auto
#   ./apply-sessionkey-patch.sh --check --method auto
#   ./apply-sessionkey-patch.sh --revert --method auto

set -e

OPENCLAW_DIR="/Users/liuguanghua/cascade/openclaw-erp/openclaw"
PATCH_FILE_DEFAULT="$OPENCLAW_DIR/patches/sessionkey.patch"

CHECK_MODE=false
REVERT_MODE=false
METHOD="sed"
PATCH_FILE="$PATCH_FILE_DEFAULT"

usage() {
  echo "用法: $0 [--check] [--revert] [--method <sed|git|auto>] [--patch-file <file>]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      CHECK_MODE=true
      shift
      ;;
    --revert)
      REVERT_MODE=true
      shift
      ;;
    --method)
      if [ -z "${2:-}" ]; then
        echo "错误: --method 需要参数"
        usage
        exit 1
      fi
      METHOD="$2"
      shift 2
      ;;
    --patch-file)
      if [ -z "${2:-}" ]; then
        echo "错误: --patch-file 需要参数"
        usage
        exit 1
      fi
      PATCH_FILE="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      usage
      exit 1
      ;;
  esac
done

if [ "$METHOD" != "sed" ] && [ "$METHOD" != "git" ] && [ "$METHOD" != "auto" ]; then
  echo "错误: --method 仅支持 sed 、 git 或 auto"
  exit 1
fi

echo "========================================="
echo "SessionKey 补丁应用脚本"
echo "  method: $METHOD"
if [ "$METHOD" = "git" ]; then
  echo "  patch : $PATCH_FILE"
fi
echo "========================================="

cd "$OPENCLAW_DIR"

FILE1="src/agents/pi-bundle-mcp-materialize.ts"
FILE2="src/agents/pi-embedded-runner/compact.ts"
FILE3="src/routing/resolve-route.ts"
FILE4="src/agents/pi-embedded-runner/run/attempt.ts"

check_with_sed() {
  local ok=0
  echo ""
  echo "[检查] sed 补丁状态"
  if grep -q "sessionKey?: string;" "$FILE1" && grep -q "sessionKey: params.sessionKey," "$FILE1"; then
    echo "  ✓ $FILE1 已应用"
  else
    echo "  ✗ $FILE1 未应用"
    ok=1
  fi

  if grep -A1 "reservedToolNames: tools.map((tool) => tool.name)," "$FILE2" | grep -q "sessionKey: params.sessionKey,"; then
    echo "  ✓ $FILE2 已应用"
  else
    echo "  ✗ $FILE2 未应用"
    ok=1
  fi

  if grep -q 'value.trim().toLowerCase()' "$FILE3"; then
    echo "  ✓ $FILE3 已应用"
  else
    echo "  ✗ $FILE3 未应用"
    ok=1
  fi

  if grep -q '_meta.*sessionKey' "$FILE1"; then
    echo "  ✓ $FILE1 _meta注入 已应用"
  else
    echo "  ✗ $FILE1 _meta注入 未应用"
    ok=1
  fi

  if grep -q 'sessionKey: params.sessionKey,' "$FILE4"; then
    echo "  ✓ $FILE4 已应用"
  else
    echo "  ✗ $FILE4 未应用"
    ok=1
  fi

  return "$ok"
}

apply_with_sed() {
  echo ""
  echo "[处理] $FILE1"
  if grep -q "sessionKey?: string;" "$FILE1"; then
    echo "  ⚠️  补丁可能已应用，跳过"
  else
    sed -i.bak 's/reservedToolNames?: Iterable<string>;/reservedToolNames?: Iterable<string>;\n  sessionKey?: string;/' "$FILE1"
    sed -i.bak 's/sessionId: `bundle-mcp:${crypto.randomUUID()}`,/sessionId: `bundle-mcp:${crypto.randomUUID()}`,\n    sessionKey: params.sessionKey,/' "$FILE1"
    rm -f "$FILE1.bak"
    echo "  ✓ 已应用"
  fi

  echo ""
  echo "[处理] $FILE1 _meta注入"
  if grep -q '_meta.*sessionKey' "$FILE1"; then
    echo "  ⚠️  _meta注入补丁可能已应用，跳过"
  else
    sed -i.bak '/execute: async (_toolCallId: string, input: unknown) => {/a\
        // 注入 sessionKey 到 _meta（myclaw 从 _meta.sessionKey 取身份信息）\
        if (params.sessionKey) {\
          const inputObj = (typeof input === '\''object'\'' \&\& input !== null ? input : {}) as Record<string, unknown>;\
          if (!inputObj._meta) inputObj._meta = {};\
          (inputObj._meta as Record<string, unknown>).sessionKey = params.sessionKey;\
          input = inputObj;\
        }' "$FILE1"
    rm -f "$FILE1.bak"
    echo "  ✓ 已应用"
  fi

  echo ""
  echo "[处理] $FILE1 createBundleMcpToolRuntime sessionKey传递"
  if grep -A1 "reservedToolNames: params.reservedToolNames," "$FILE1" | grep -q "sessionKey: params.sessionKey,"; then
    echo "  ⚠️  补丁可能已应用，跳过"
  else
    sed -i.bak 's/reservedToolNames: params.reservedToolNames,/reservedToolNames: params.reservedToolNames,\n    sessionKey: params.sessionKey,/' "$FILE1"
    rm -f "$FILE1.bak"
    echo "  ✓ 已应用"
  fi

  echo ""
  echo "[处理] $FILE2"
  if grep -A1 "reservedToolNames: tools.map((tool) => tool.name)," "$FILE2" | grep -q "sessionKey: params.sessionKey,"; then
    echo "  ⚠️  补丁可能已应用，跳过"
  else
    sed -i.bak 's/reservedToolNames: tools.map((tool) => tool.name),/reservedToolNames: tools.map((tool) => tool.name),\n          sessionKey: params.sessionKey,/' "$FILE2"
    rm -f "$FILE2.bak"
    echo "  ✓ 已应用"
  fi

  echo ""
  echo "[处理] $FILE3"
  if grep -q 'value.trim().toLowerCase()' "$FILE3"; then
    echo "  ⚠️  normalizeId 补丁可能已应用，跳过"
  else
    sed -i.bak 's/return value\.trim();/return value.trim().toLowerCase();/' "$FILE3"
    sed -i.bak 's/return String(value)\.trim();/return String(value).trim().toLowerCase();/' "$FILE3"
    rm -f "$FILE3.bak"
    echo "  ✓ 已应用"
  fi

  echo ""
  echo "[处理] $FILE4"
  if grep -q 'sessionKey: params.sessionKey,' "$FILE4"; then
    echo "  ⚠️  补丁可能已应用，跳过"
  else
    sed -i.bak '/reservedToolNames: \[/{
      /clientTools/!b
      n
      /\]/a\
          sessionKey: params.sessionKey,
    }' "$FILE4"
    # 如果上面的多行 sed 不生效，用简单替换兜底
    if ! grep -q 'sessionKey: params.sessionKey,' "$FILE4"; then
      sed -i.bak 's/\.\.\.(clientTools?.map((tool) => tool.function.name) ?? \[\]),/\.\.\.(clientTools?.map((tool) => tool.function.name) ?? []),\n          sessionKey: params.sessionKey,/' "$FILE4"
    fi
    rm -f "$FILE4.bak"
    echo "  ✓ 已应用"
  fi
}

revert_with_sed() {
  echo ""
  echo "[撤销] sed 补丁"
  sed -i.bak '/sessionKey?: string;/d' "$FILE1"
  sed -i.bak '/sessionKey: params.sessionKey,/d' "$FILE1"
  sed -i.bak '/注入 sessionKey 到 _meta/,/^        }/d' "$FILE1"
  sed -i.bak '/reservedToolNames: tools.map((tool) => tool.name),/{n;/sessionKey: params.sessionKey,/d;}' "$FILE2"
  sed -i.bak 's/\.trim()\.toLowerCase()/\.trim()/g' "$FILE3"
  sed -i.bak '/sessionKey: params.sessionKey,/d' "$FILE4"
  rm -f "$FILE1.bak" "$FILE2.bak" "$FILE3.bak" "$FILE4.bak"
  echo "  ✓ 撤销完成"
}

check_with_git_patch() {
  if [ ! -f "$PATCH_FILE" ]; then
    echo "✗ patch 文件不存在: $PATCH_FILE"
    return 1
  fi

  echo ""
  echo "[检查] git patch 状态"
  if git apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "  ✓ patch 已应用"
    return 0
  fi
  echo "  ✗ patch 未应用"
  return 1
}

apply_with_git_patch() {
  if [ ! -f "$PATCH_FILE" ]; then
    echo "✗ patch 文件不存在: $PATCH_FILE"
    exit 1
  fi

  echo ""
  echo "[处理] git apply"
  if git apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "  ⚠️  patch 已应用，跳过"
    return
  fi

  if git apply --3way "$PATCH_FILE"; then
    echo "  ✓ patch 应用成功"
  else
    echo "  ✗ patch 应用失败，请解决冲突后重试"
    exit 1
  fi
}

revert_with_git_patch() {
  if [ ! -f "$PATCH_FILE" ]; then
    echo "✗ patch 文件不存在: $PATCH_FILE"
    exit 1
  fi

  echo ""
  echo "[撤销] git apply -R"
  if git apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    git apply -R "$PATCH_FILE"
    echo "  ✓ patch 已撤销"
    return
  fi
  echo "  ⚠️  patch 未应用，跳过"
}

run_auto_apply() {
  echo ""
  echo "[处理] auto 模式：优先 git patch，失败则回退 sed"
  echo ""
  if git apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "  ⚠️  git patch 已应用，跳过"
    check_with_git_patch
    return $?
  fi

  if git apply --3way "$PATCH_FILE" >/dev/null 2>&1; then
    echo "  ✓ git patch 应用成功"
    check_with_git_patch
    return $?
  fi

  echo "  ⚠️  git patch 应用失败，自动回退到 sed 模式"
  echo "  注意：此回退意味着 patch 与当前源码不匹配，升级后可能隐藏不兼容变更！"
  echo ""
  apply_with_sed
  check_with_sed
  return $?
}

run_auto_check() {
  echo "[check] auto 模式（检查 git / sed 补丁状态）"
  check_with_git_patch || check_with_sed
  return $?
}

run_auto_revert() {
  echo "[撤销] auto 模式（尝试同时撤销 git 和 sed 补丁）"
  revert_with_git_patch || true
  echo ""
  echo "  [检查] sed 补丁状态"
  if grep -q "sessionKey?: string;" "$FILE1"; then
    echo "  发现 sed 补丁，撤销中..."
    revert_with_sed
  else
    echo "  sed 补丁未应用，跳过"
  fi
}

if [ "$CHECK_MODE" = true ]; then
  if [ "$METHOD" = "auto" ]; then
    run_auto_check
    exit $?
  fi
  if [ "$METHOD" = "git" ]; then
    check_with_git_patch
  else
    check_with_sed
  fi
  exit $?
fi

if [ "$REVERT_MODE" = true ]; then
  if [ "$METHOD" = "auto" ]; then
    run_auto_revert
  elif [ "$METHOD" = "git" ]; then
    revert_with_git_patch
  else
    revert_with_sed
  fi
  echo ""
  echo "========================================="
  echo "补丁撤销完成"
  echo "========================================="
  exit 0
fi

if [ "$METHOD" = "auto" ]; then
  run_auto_apply
  status=$?
elif [ "$METHOD" = "git" ]; then
  apply_with_git_patch
  check_with_git_patch
  status=$?
else
  apply_with_sed
  check_with_sed
  status=$?
fi

echo ""
echo "========================================="
if [ "$status" -eq 0 ]; then
  echo "补丁应用完成"
else
  echo "补丁应用后检查失败"
fi
echo "========================================="
echo ""
echo "验证修改："
echo "  git diff $FILE1 $FILE2 $FILE3 $FILE4"
echo ""
echo "编译："
echo "  bun run build"

exit "$status"
