# Development Guide

This document captures the local development workflow for Nexus.

Run the commands below from the repository root unless a command changes directory explicitly.

## Prerequisites

- macOS with Xcode and Swift Package Manager.
- Node.js with `node:sqlite` support.
- npm.
- Git.

A DeepSeek or OpenAI API key is optional for normal app use and required only for the user-triggered `Prepare Current Work` flow. Connect it through the app so it remains in the provider-specific macOS Keychain account; do not add it to environment files, SQLite, fixtures, or source control.

The MCP helper is pinned through `adapters/mcp/package-lock.json`. Do not use floating dependency versions for the helper.

## Local Data

By default, Nexus stores product data in:

```text
~/Library/Application Support/Nexus
```

The Mac app and MCP helper both use this path when `NEXUS_HOME` is omitted. A packaged Nexus app should install the helper into this app-managed directory and users should not need to configure database paths.

For an isolated GUI run, point `NEXUS_HOME` at a temporary directory outside the repository:

```bash
NEXUS_HOME=/private/tmp/nexus-ui-data \
  .build/swiftpm/debug/NexusMac
```

Automated MCP regressions create and remove their own directories under the system temporary directory. Ignored local directories:

- `.build/`
- `.swiftpm/`
- `adapters/mcp/node_modules/`
- `adapters/mcp/dist/`

These directories are build output or dependency installs. They should not be committed.

## Build

Build the Swift package:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
  swift build --scratch-path "$PWD/.build/swiftpm"
```

Build the MCP helper:

```bash
cd adapters/mcp
npm ci
npm run build
```

## Verify

Run Core and app tests:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache" \
  swift test --scratch-path "$PWD/.build/swiftpm"
```

Run the stdio MCP regression:

```bash
cd adapters/mcp
npm run verify:stdio
```

Run the parallel-binding regression with real Git worktrees:

```bash
cd adapters/mcp
npm run verify:bindings
```

Run the text-material boundary regression:

```bash
cd adapters/mcp
npm run verify:file-policy
```

Run the compact context contract and character-budget regression:

```bash
cd adapters/mcp
npm run verify:context-payload
```

Inspect the bound context result:

```bash
cd adapters/mcp
NEXUS_HOME=/private/tmp/nexus-ui-data node tests/current-context-client.mjs
```

The stdio regression checks that:

- Explicitly created isolated Work switching is visible through MCP.
- Two helpers attached to real worktrees keep separate bindings while Default Work changes.
- Updating one Work only advances its revision; deleting or reassigning an explicit/workspace binding makes the old helper fail explicitly.
- `get_current_development_context` is listed and marked as optional handoff context.
- server instructions tell MCP clients not to call Nexus by default when the current conversation already has enough context.
- v1 fallback and v2 Context Pack projections remain readable during migration.
- the main context has no duplicate legacy wrappers and stays within its 24,000-character budget.
- binary and unsupported files are rejected instead of returned as garbled text.

The regression sets `NEXUS_MCP_ALLOW_HEADLESS=1` because it runs without the Mac app. Product MCP clients must not set this variable; without it, the helper only returns context while the Nexus Mac app heartbeat is fresh and assistant access is enabled.

## Product Guardrails

- Nexus provides context; it does not replace the conversation between user and assistant.
- Normal autosave should be quiet. Only failures should interrupt the user.
- Assistant-visible materials are opt-in per item.
- Hidden materials must remain unreadable through MCP.
- MCP must not return the last stored context when the Mac app is not running or assistant access is paused.
- Git branch awareness may suggest or create work, but must not mutate the worktree.
- Debug CLI is for testing and diagnostics, not the primary product surface.
- Empty product databases should remain empty until the user creates work or a debug seed command is explicitly run.
- Model output remains a draft until explicit approval; failed or cancelled requests must not change MCP.
- Context claims presented as facts, constraints, scope, or acceptance criteria require source references.

## Git Hygiene

Before committing:

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

Do not commit local databases, build artifacts, installed dependencies, generated helper bundles, or user-specific Xcode state.

Keep SwiftUI in `Sources/NexusMac`, durable rules and storage in `Sources/NexusCore`, and protocol adaptation in `adapters/mcp`. UI changes should not duplicate Core behavior; MCP changes should consume projections rather than domain tables directly.
