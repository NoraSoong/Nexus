# 开发指南

这份文档记录 Nexus 的本地开发、构建和验证流程。

除非命令显式切换目录，以下命令都应从仓库根目录运行。

## 环境要求

- 安装 Xcode 和 Swift Package Manager 的 macOS。
- 支持 `node:sqlite` 的 Node.js。
- npm。
- Git。

普通使用不需要模型 API Key；只有用户主动触发“整理当前工作”时才需要 DeepSeek 或 OpenAI Key。请通过 App 连接，使其进入对应提供商的 macOS 钥匙串 account；不要把 Key 写入环境文件、SQLite、测试数据或代码仓。

MCP Helper 的依赖通过 `adapters/mcp/package-lock.json` 固定。Helper 不应使用浮动依赖版本。

## 本地数据

默认情况下，Nexus 会把产品数据保存到：

```text
~/Library/Application Support/Nexus
```

Mac App 和 MCP Helper 在没有设置 `NEXUS_HOME` 时都会使用这个路径。正式打包后的 Nexus 应该把 helper 安装到这个 App 管理目录里，用户不需要配置数据库路径。

需要隔离运行 GUI 时，把 `NEXUS_HOME` 指向仓库外的临时目录：

```bash
NEXUS_HOME=/private/tmp/nexus-ui-data \
  .build/swiftpm/debug/NexusMac
```

自动化 MCP 回归会在系统临时目录中自行创建并删除数据。以下目录是已忽略的构建产物或本地依赖：

- `.build/`
- `.swiftpm/`
- `adapters/mcp/node_modules/`
- `adapters/mcp/dist/`

这些内容不应提交。

## 构建

构建 Swift Package：

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
  swift build --scratch-path "$PWD/.build/swiftpm"
```

构建 MCP Helper：

```bash
cd adapters/mcp
npm ci
npm run build
```

## 验证

运行 Core 与 App 测试：

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache" \
  swift test --scratch-path "$PWD/.build/swiftpm"
```

运行 stdio MCP 回归测试：

```bash
cd adapters/mcp
npm run verify:stdio
```

运行真实 Git worktree 的并行 binding 回归：

```bash
cd adapters/mcp
npm run verify:bindings
```

运行文本材料读取边界回归：

```bash
cd adapters/mcp
npm run verify:file-policy
```

运行主上下文结构和字符预算回归：

```bash
cd adapters/mcp
npm run verify:context-payload
```

查看当前绑定上下文输出：

```bash
cd adapters/mcp
NEXUS_HOME=/private/tmp/nexus-ui-data node tests/current-context-client.mjs
```

stdio 回归测试会检查：

- 显式创建的隔离 Work 切换能通过 MCP 观察到。
- 两个真实 worktree 的 Helper 在默认 Work 反复切换后仍保持各自绑定。
- 某个 Work 更新只推进自己的 revision；显式或 workspace binding 删除、改绑后旧 Helper 明确失败。
- `get_current_development_context` 存在，并被描述为可选交接上下文入口。
- server instructions 会提示 MCP 客户端：当前对话上下文已经足够时，不要默认调用 Nexus。
- 迁移期间 v1 fallback 和 v2 Context Pack projection 都能被读取。
- 主上下文不包含重复的 legacy wrapper，并保持在 24,000 字符预算内。
- 不支持或二进制文件不会以乱码形式返回。

回归测试会设置 `NEXUS_MCP_ALLOW_HEADLESS=1`，因为它不启动 Mac App。真实产品客户端不应设置这个变量；没有这个变量时，Helper 只有在 Nexus Mac App heartbeat 新鲜时才返回上下文。

GitHub Actions 会在 `main` 的更新和 Pull Request 中运行同一套 Swift 格式化、构建、
测试、Helper 构建和 MCP 契约校验。请让本地校验与该工作流保持一致，不要只在 CI 中
增加本地无法复现的单独检查。

## 产品边界

- Nexus 提供上下文，不替代用户和助手之间的对话。
- 正常自动保存应安静完成，只有失败才打扰用户。
- 材料是否对助手可见由用户逐项控制。
- Hidden materials 不能通过 MCP 读取原文。
- Mac App 没有运行时，MCP 不能返回上一次保存的旧上下文。
- Git 分支感知可以建议或创建 Work，但不能修改 worktree。
- Debug CLI 只用于测试和诊断，不是主要产品入口。
- 空的产品数据库应该保持空状态，直到用户创建 Work，或显式运行 debug seed 命令。
- 模型输出在用户明确采用前始终是草稿；失败或取消请求不能改变 MCP。
- 作为事实、约束、范围或验收条件展示的内容必须带来源引用。

## Git 习惯

提交前建议运行：

```bash
git status --short
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
  swift build --scratch-path "$PWD/.build/swiftpm"
cd adapters/mcp
npm run build
npm run verify:stdio
npm run verify:bindings
npm run verify:file-policy
npm run verify:context-payload
```

不要提交本地数据库、构建产物、依赖安装目录、生成的 helper bundle 或 Xcode 用户状态。

SwiftUI 放在 `Sources/NexusMac`，持久化规则和领域逻辑放在 `Sources/NexusCore`，协议适配放在 `adapters/mcp`。UI 不应复制 Core 规则；MCP 应读取 projection，而不是直接依赖领域表。
