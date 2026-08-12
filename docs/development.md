# Development Guide

This document captures the local development workflow for Nexus.

Run the commands below from the repository root unless a command changes directory explicitly.

## Prerequisites

- macOS with Xcode and Swift Package Manager.
- Node.js with `node:sqlite` support.
- npm.
- Git.

A DeepSeek or OpenAI API key is optional for normal app use and required only for the user-triggered `Prepare Current Work` flow. Connect it through the app's preparation service settings; the implementation stores it in the provider-specific macOS Keychain account. Do not add it to environment files, SQLite, fixtures, or source control. The main preparation sheet should only expose connection status and a settings entry, not Keychain terminology.

Model prompts use short, request-local source citations such as `S1` and `S2`. These aliases are model-only metadata and must not appear in natural-language context. Nexus resolves them back to the real source IDs locally and cleans legacy text before projection; exact legacy IDs remain accepted for compatibility, while titles, paths, filenames, and unknown citations are rejected. DeepSeek Flash/Pro selection is persisted locally; OpenAI currently uses one fixed model.

Workspace association is intentionally one-to-one by normalized workspace path. A repository may have multiple worktrees, and each worktree may be associated with a different Work. Association failures must preserve existing bindings and surface a typed `WorkspaceAssociationError` to the UI. `WorkspaceProvisioningService` runs standard `git worktree add` only after explicit confirmation; it does not merge, push, or delete code.

The MCP helper is pinned through `adapters/mcp/package-lock.json`. Do not use floating dependency versions for the helper.

The Apple Silicon Developer Preview is built with `scripts/build-preview.sh`. It embeds the pinned official Node Runtime and Helper resources in a real `Nexus.app`; `scripts/verify-preview.sh` checks the Bundle, Runtime, `node:sqlite`, DMG, and checksum. The preview is not signed or notarized.

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

Build the preview package without changing the source checkout's installed dependencies:

```bash
scripts/build-preview.sh
scripts/verify-preview.sh
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
- UTF-8 and UTF-16 pagination preserves character boundaries;
- binary, unsupported, invalidly encoded, and oversized files are rejected instead of returned as garbled text;
- source reads are capped at 64 MiB and do not load a complete file into memory.

The regression sets `NEXUS_MCP_ALLOW_HEADLESS=1` because it runs without the Mac app. Product MCP clients must not set this variable; without it, the helper only returns context while the Nexus Mac app heartbeat is fresh and assistant access is enabled.

GitHub Actions runs the same Swift formatting, build, test, helper build, and MCP
contract checks for changes to `main` and pull requests. Keep local verification aligned
with that workflow rather than adding one-off checks only in CI.

## Product Guardrails

- Nexus provides context; it does not replace the conversation between user and assistant.
- Normal autosave should be quiet. Only failures should interrupt the user.
- Assistant-visible materials are opt-in per item.
- Hidden materials must remain unreadable through MCP.
- MCP must not return the last stored context when the Mac app is not running or assistant access is paused.
- Git branch awareness may show mismatch and offer an explicit isolated-directory creation flow. Only that confirmed flow creates a new worktree; Nexus never switches, stashes, commits, or deletes code automatically.
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
