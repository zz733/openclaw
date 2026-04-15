# OpenClaw 升级 + SessionKey 补丁工作流

## 概述

当服务器上的 OpenClaw 升级后，需要重新应用 SessionKey 补丁。本工作流自动化整个过程。

## 文件说明

- `upgrade-and-patch.sh` - 主脚本：自动完成版本对齐、补丁应用、编译、部署
- `generate-patch.sh` - 补丁生成脚本：将本地修改导出为补丁文件
- `openclaw-patches/` - 补丁文件存放目录

## 完整工作流

### 场景 1：服务器已升级，需要重新打补丁

```bash
# 1. 服务器执行升级
ssh root@jxgy.52iptv.net
openclaw update
exit

# 2. 本地运行升级补丁脚本（自动完成所有步骤）
cd /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw
./upgrade-and-patch.sh
```

脚本会自动：
1. 检测服务器版本
2. 本地切换到对应版本的 git tag
3. 应用 sessionKey 补丁
4. 编译源码
5. 部署到服务器
6. 重启服务

### 场景 2：首次设置（生成补丁文件）

```bash
# 1. 修改本地 openclaw 源码，添加 sessionKey 支持
cd /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw
# ... 编辑代码 ...

# 2. 生成补丁文件
./generate-patch.sh --name session-key-v1

# 补丁会保存到：
# /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw-patches/session-key-v1.patch
```

### 场景 3：本地已对齐版本，只需部署

```bash
# 跳过版本同步步骤
./upgrade-and-patch.sh --skip-sync
```

### 场景 4：仅检查版本状态

```bash
# 不执行任何修改，仅对比版本
./upgrade-and-patch.sh --check-only
```

## 手动操作步骤

如果自动脚本失败，可以手动执行：

```bash
# 1. 检查服务器版本
ssh root@jxgy.52iptv.net "openclaw --version"
# 输出示例：2026.4.11

# 2. 本地切换到对应版本
cd /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw
git fetch --tags
git checkout v2026.4.11  # 替换为实际版本号
bun install

# 3. 应用补丁
git apply /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw-patches/session-key.patch

# 如果有冲突，使用 --reject 模式
git apply --reject /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw-patches/session-key.patch
# 然后手动解决 .rej 文件

# 4. 编译
bun run build

# 5. 部署
./deploy-patch.sh --skip-build
```

## 回滚操作

如果部署后出现问题：

```bash
# 服务器执行回滚
ssh root@jxgy.52iptv.net
cd /usr/lib/node_modules/openclaw
rm -rf dist
mv dist.bak.* dist  # 恢复到备份版本
pkill -f "openclaw gateway"
nohup openclaw gateway > /var/log/openclaw.log 2>&1 &
```

## 验证补丁

```bash
# 检查服务器是否包含 sessionKey 补丁
ssh root@jxgy.52iptv.net "grep -c 'sessionKey: params.sessionKey' /usr/lib/node_modules/openclaw/dist/pi-embedded-runner-*.js"

# 查看服务日志
ssh root@jxgy.52iptv.net "tail -50 /var/log/openclaw.log"

# 检查版本
ssh root@jxgy.52iptv.net "openclaw --version"
```

## 补丁管理

### 查看现有补丁

```bash
ls -la /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw-patches/
```

### 查看补丁内容

```bash
cat /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw-patches/session-key.patch
```

### 测试补丁（不应用）

```bash
cd /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw
git apply --check /path/to/patch.patch
```

### 撤销已应用的补丁

```bash
git apply -R /path/to/patch.patch
```

## 常见问题

### Q: 补丁应用失败，提示冲突？

A: 新版本可能修改了相同的代码行。解决方法：

```bash
# 1. 使用 --reject 模式应用
git apply --reject patch.patch

# 2. 查看冲突文件
find . -name "*.rej"

# 3. 手动编辑冲突文件，对比 .rej 文件中的修改

# 4. 清理 .rej 文件
find . -name "*.rej" -delete
```

### Q: 编译失败？

A: 检查 Node.js 和 bun 版本：

```bash
node --version  # 建议 >= 18
bun --version
bun install     # 重新安装依赖
```

### Q: 如何知道服务器版本对应的 git tag？

A: 

```bash
# 服务器版本格式通常是：2026.4.11
# 对应的 git tag 是：v2026.4.11

# 查看所有可用 tag
git tag | grep "2026.4"

# 如果 tag 不存在，可能需要使用 commit hash
git log --oneline | grep "2026.4.11"
```

## 自动化建议

可以将升级脚本添加到 cron 定时任务，或配置为 CI/CD 流程：

```bash
# 每天凌晨 2 点检查并应用补丁
0 2 * * * /Users/liuguanghua/CascadeProjects/openclaw-erp/openclaw/upgrade-and-patch.sh --check-only >> /var/log/openclaw-patch.log 2>&1
```
