# Changelog

All notable changes to Nexus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Native SwiftUI Mac app with menu-bar entry and quick switching
- Work creation, editing, archive, restore, and delete flows
- Local file and pasted text materials with per-material assistant visibility
- DeepSeek and OpenAI context model providers, API keys in macOS Keychain
- Source-backed objectives, scope, facts, constraints, acceptance criteria,
  assumptions, and questions in Context Pack
- Context Pack review, diff, approval, and material-freshness tracking
- Git repository, branch, and worktree association with commit and
  working-tree activity evidence
- Workspace bindings for pinning different worktrees to different Work items
- Read-only stdio MCP Helper with layered confirmed context, source
  freshness, workspace activity, and paginated material reads
- MCP access gating: no context returned while the Mac app is not running or
  assistant access is paused
- GitHub CI: Swift formatting, build, test, MCP helper build, and MCP
  contract verification on push to `main` and pull requests

### Changed
- Streamed UTF-8 and UTF-16 material extraction and MCP pagination with a
  64 MiB per-file safety limit
- One compact retry when a context model reaches its output limit
- Context Pack, binding, and projection persistence split behind the existing
  `ProjectionStore` compatibility facade
