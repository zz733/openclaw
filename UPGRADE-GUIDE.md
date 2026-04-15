# OpenClaw 升级 + SessionKey 补丁工作流

## 场景说明

服务器上的 OpenClaw 通过 `openclaw update` 升级到新版本后，需要重新应用 sessionKey 补丁。

## 完整流程

### 一键升级（推荐）

```bash
# 1. 服务器升级
ssh root@jxgy.52iptv.net "openclaw update"

# 2. 本地一键完成所有操作
cd /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw
./upgrade-and-patch.sh
```

脚本自动完成：
1. ✅ 检测服务器版本
2. ✅ 从 https://github.com/openclaw/openclaw 下载对应版本的官方源码
3. ✅ 动态修改源码添加 sessionKey 支持
4. ✅ 编译源码
5. ✅ 部署到服务器
6. ✅ 重启服务

### 仅下载和打补丁（不部署）

```bash
./upgrade-and-patch.sh --skip-deploy
```

这会：
- 下载官方源码
- 应用 sessionKey 补丁
- 不编译、不部署

适合先验证补丁是否兼容新版本。

### 仅检查版本

```bash
./upgrade-and-patch.sh --check-only
```

## 手动操作

如果需要手动控制每一步：

```bash
# 1. 查看服务器版本
ssh root@jxgy.52iptv.net "openclaw --version"
# 输出：2026.4.11

# 2. 下载对应版本的官方源码
cd /Users/liuguanghua/CascadeProjects/openclaw-erp
mv openclaw openclaw.bak  # 备份旧版本
git clone --depth 1 --branch v2026.4.11 https://github.com/openclaw/openclaw.git openclaw
cd openclaw
bun install

# 3. 应用 sessionKey 补丁
./apply-sessionkey-patch.sh

# 4. 验证补丁
./apply-sessionkey-patch.sh --check

# 5. 编译
bun run build

# 6. 部署
./deploy-patch.sh --skip-build
```

## 补丁详情

SessionKey 补丁修改了 2 个文件：

### 1. src/agents/pi-bundle-mcp-materialize.ts

在 `createBundleMcpToolRuntime` 函数中添加 sessionKey 参数：

```typescript
export async function createBundleMcpToolRuntime(params: {
  workspaceDir: string;
  cfg?: OpenClawConfig;
  reservedToolNames?: Iterable<string>;
  sessionKey?: string;  // ← 新增
}): Promise<BundleMcpToolRuntime> {
  const runtime = createSessionMcpRuntime({
    sessionId: `bundle-mcp:${crypto.randomUUID()}`,
    sessionKey: params.sessionKey,  // ← 新增
    workspaceDir: params.workspaceDir,
    cfg: params.cfg,
  });
  // ...
}
```

### 2. src/agents/pi-embedded-runner/compact.ts

在调用 `createBundleMcpToolRuntime` 时传递 sessionKey：

```typescript
const bundleMcpRuntime = toolsEnabled
  ? await createBundleMcpToolRuntime({
      workspaceDir: effectiveWorkspace,
      cfg: params.config,
      reservedToolNames: tools.map((tool) => tool.name),
      sessionKey: params.sessionKey,  // ← 新增
    })
  : undefined;
```

## 回滚

如果部署后出现问题：

```bash
ssh root@jxgy.52iptv.net 'cd /usr/lib/node_modules/openclaw && rm -rf dist && mv dist.bak.* dist && pkill -f "openclaw gateway" && nohup openclaw gateway > /var/log/openclaw.log 2>&1 &'
```

## 验证

```bash
# 检查版本
ssh root@jxgy.52iptv.net "openclaw --version"

# 检查补丁是否生效
ssh root@jxgy.52iptv.net "grep -c 'sessionKey: params.sessionKey' /usr/lib/node_modules/openclaw/dist/pi-embedded-runner-*.js"

# 查看日志
ssh root@jxgy.52iptv.net "tail -50 /var/log/openclaw.log"
```

## 常见问题

### Q: 补丁应用失败？

A: 新版本可能修改了相同的代码行。检查：

```bash
# 查看官方源码是否有变化
cd openclaw
git log --oneline -10 -- src/agents/pi-bundle-mcp-materialize.ts src/agents/pi-embedded-runner/compact.ts
```

如果官方修改了这些文件，需要手动调整补丁脚本。

### Q: 如何知道服务器版本对应的 git tag？

A: 服务器版本格式通常是 `2026.4.11`，对应的 git tag 是 `v2026.4.11`。

查看所有可用 tag：
```bash
git ls-remote --tags https://github.com/openclaw/openclaw.git | grep "v2026"
```

### Q: 编译失败？

A: 检查 Node.js 和 bun 版本：

```bash
node --version  # 建议 >= 18
bun --version
bun install     # 重新安装依赖
```
