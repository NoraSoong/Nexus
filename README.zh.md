# Nexus

[![Verify](https://github.com/NoraSoong/Nexus/actions/workflows/verify.yml/badge.svg)](https://github.com/NoraSoong/Nexus/actions/workflows/verify.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.3-orange.svg)]()
[![macOS](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)]()

[English README](README.md)

Nexus 是 Mac 上面向编码助手的本地优先可信工作上下文层。

它把需求说明、接口样例、SQL、日志、代码文件和人的补充说明，整理成一份短小、可审核、带来源的 **Context Pack**，并把后续代码变化作为独立证据持续交接。确认后的上下文可通过 MCP 供 Codex、Claude 等编码助手按需读取，原始材料不会被默认全部塞进模型。

> 当前状态：pre-alpha 本地原型，可用于 dogfooding。正式 App Bundle、私有 Helper runtime、签名、公证和 DMG 尚未完成。

## 为什么使用 Nexus

多开一个助手对话可以保存对话历史，但不能可靠回答：

- 当前应该以哪份材料为准；
- 哪些内容是事实、假设或待确认问题；
- 哪些本地材料允许助手读取；
- 同一仓库的多个并行工作区分别对应哪项需求；
- 如何在材料越来越多时保持上下文简短、可追溯。

Nexus 不管理 Agent，也不接管 Git。它管理的是两者之间容易丢失、混淆或过期的工作上下文：

```mermaid
flowchart LR
    Materials["杂乱材料"] --> Draft["模型整理草稿"]
    Draft --> Review["用户审核"]
    Review --> Pack["已确认 Context Pack"]
    Pack --> MCP["受控 MCP 投影"]
    MCP --> Assistants["编码助手"]
    Assistants --> Git["工作区代码变化"]
    Git --> Draft
```

模型输出始终是草稿。只有用户明确采用后，Context Pack 才会成为该 Work 的当前上下文并进入 MCP。

## 当前能力

- 原生 SwiftUI Mac App、菜单栏入口和快速切换；
- Work 创建、编辑、归档、恢复与删除；
- 本地文件和粘贴文本材料，逐项控制助手可见性；
- 以流式方式提取 UTF-8 与 UTF-16 文本，遵守单项预算和 64 MiB 硬性安全上限；
- DeepSeek 与 OpenAI 上下文整理，API Key 分别保存在 macOS 钥匙串；DeepSeek 可在 Flash（日常整理）与 Pro（复杂材料）之间选择；
- 每次整理使用 `S1`、`S2` 等仅供模型使用的内部引用，Nexus 在保存前还原为稳定的真实来源 ID，不会把这些标记展示给用户或助手；
- 模型达到输出上限时自动进行一次压缩重试；
- 带来源的目标、范围、事实、约束、验收条件、假设和待确认问题；
- Context Pack 审核、差异查看、采用和材料变化后的过期提示；
- Git 仓库、分支和已有 worktree 关联，以及基于确认版本的提交与工作区变化摘要；
- 材料新鲜度与代码活动分离：普通编码不会把需求上下文错误标记为过期；
- workspace binding：同一仓库的不同 worktree 可固定到不同 Work；
- 工作区关联失败时明确说明目录、绑定冲突或路径问题，并引导选择其他 worktree；
- 只读 stdio MCP Helper，分层返回确认上下文、材料新鲜度、工作区活动和流式分页材料；
- App 未运行或助手读取被暂停时，不暴露 Nexus MCP tools。

Nexus 不运行编码 Agent，不替用户决定实现方案，也不自动切换、合并或删除代码。用户明确确认后，它可以创建标准 Git worktree，并把新目录绑定到当前 Work。

## 环境要求

当前开发基线：

- macOS 14 或更高版本；
- Xcode 26.5 / Swift 6.3.2；
- Node.js `v26.5.0`，由 [`.node-version`](.node-version) 固定；
- npm `11.17.0`。

MCP Helper 使用 `node:sqlite`，不依赖系统 SQLite CLI 或第三方 native addon。

## 构建与运行

构建并测试 Swift：

```bash
swift build
swift test
```

构建 MCP Helper：

```bash
cd adapters/mcp
npm ci
npm run build
```

启动开发版 Mac App：

```bash
.build/debug/NexusMac
```

Nexus 默认把数据保存到：

```text
~/Library/Application Support/Nexus
```

普通用户不需要配置数据库路径或环境变量。`NEXUS_HOME` 只用于开发中的隔离测试。

## 基本使用

1. 启动 Nexus，从菜单栏打开主窗口。
2. 新建 Work，填写标题和一句话目标。
3. 可选：选择已有代码目录，或让 Nexus 创建一个隔离代码目录。
4. 拖入相关文件，或添加一段文本材料。
5. 设置每份材料是否可供助手读取。
6. 需要时填写一段可选的“补充说明”。
7. 点击“整理当前工作”，检查本次发送、排除和截取的材料。
8. 审核模型草稿，回答关键问题或修正文案。
9. 明确采用后，主界面的“当前上下文”会立即更新，助手将读取这一版本。
10. 后续出现新提交或未提交改动时，Nexus 会把它们显示为代码活动；用户再次整理并采用后才更新确认上下文。

已有 Context Pack 时，完整内容、问题和来源可直接在主界面展开查看。补充说明只作为下一次整理的可选输入，不需要维护结构化进度表单。

## MCP Helper

安装开发用 helper shim：

```bash
scripts/install-helper.sh
```

默认安装位置：

```text
~/Library/Application Support/Nexus/bin/nexus-mcp
```

检查 Helper：

```bash
"$HOME/Library/Application Support/Nexus/bin/nexus-mcp" --version
"$HOME/Library/Application Support/Nexus/bin/nexus-mcp" --doctor
```

Codex 配置示例：

```bash
codex mcp add nexus \
  -- "$HOME/Library/Application Support/Nexus/bin/nexus-mcp"
```

固定到一个已有代码目录：

```bash
codex mcp add nexus-worktree \
  -- "$HOME/Library/Application Support/Nexus/bin/nexus-mcp" \
  --workspace /path/to/worktree
```

推荐主入口：

- `get_current_development_context`：返回唯一、紧凑的当前上下文对象，明确区分 `confirmed_context`、`source_freshness` 和 `workspace_activity`；
- `read_context_material`：按需读取当前 binding 中可见的文本材料。

旧的细粒度工具暂时保留兼容。当前对话已经有足够上下文时，助手不应默认调用 Nexus。建议规则见 [docs/agent-rules.zh.md](docs/agent-rules.zh.md)。

## 数据与安全

- 数据默认保存在本机；
- 只读取用户明确添加或关联的文件与仓库；
- MCP 当前只读；
- Hidden 材料不能通过 MCP 读取；
- 模型调用只由用户主动触发；
- 模型凭据通过 App 内的小型连接设置管理，仅保存在本机；
- API Key 不写入 SQLite，也不会通过 MCP 暴露；
- 草稿失败、取消或未采用时，不改变当前 Context Pack；
- 空文件、二进制、无效编码、不支持类型和超大文件会以不同原因排除；
- Git 集成只读取状态、提交摘要和受预算控制的变更证据。用户明确确认后，Nexus 可以执行一次标准 `git worktree add` 创建隔离代码目录，但不会 checkout、stash、reset、提交、合并或删除用户代码。

### 并行代码工作与开发工具

同一个 Git 仓库如果要并行处理多个 Work，需要多个独立代码目录。创建 Work 后，在代码区选择“创建隔离代码目录”，确认基准分支、新分支和目标路径即可。创建成功后，复制目录路径，在你常用的开发工具中分别打开不同目录，例如 IDEA、VS Code、Xcode、Cursor 或终端；Nexus 不安装编辑器插件，也不会自动切换分支。

归档或删除 Work 不会删除 Nexus 创建的目录或 Git 分支。解除 Nexus 关联只移除绑定，代码仍留在本机。

## 项目文档

- [架构说明](docs/architecture.zh.md)
- [开发指南](docs/development.zh.md)
- [参与贡献](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [助手规则示例](docs/agent-rules.zh.md)

## License

本项目使用 [Apache License 2.0](LICENSE)。
