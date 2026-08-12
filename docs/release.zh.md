# Developer Preview 发布说明

## 范围

当前预览版面向 Apple Silicon Mac，系统要求 macOS 14 或更高版本。DMG 包含 Nexus App、MCP Helper 和固定版本的私有 Node.js Runtime，普通用户不需要额外安装 Node.js。

预览版暂未进行 Developer ID 签名和公证，适合本地体验与 dogfooding，不适合作为无人值守的企业部署包。

## 本地构建

```bash
scripts/build-preview.sh
scripts/verify-preview.sh
```

构建过程从官方 Node.js 分发地址下载 `node-v26.5.0-darwin-arm64.tar.gz`，校验固定的 SHA-256 后再嵌入 Runtime。生成的 App 和 DMG 位于 Git 忽略的 `dist/` 目录。

## 首次启动

Nexus 会把 App 内的 Helper 复制到：

```text
~/Library/Application Support/Nexus/helpers/<helper-version>/
```

然后创建稳定 MCP 命令：

```text
~/Library/Application Support/Nexus/bin/nexus-mcp
```

Helper 更新时仍沿用这个稳定路径，已有 MCP 客户端配置不需要修改。

## 诊断

```bash
"$HOME/Library/Application Support/Nexus/bin/nexus-mcp" --version
"$HOME/Library/Application Support/Nexus/bin/nexus-mcp" --doctor
```

诊断结果包含 Runtime 和投影兼容性信息，可能包含本机路径。提交公开 Issue 前请先脱敏。
