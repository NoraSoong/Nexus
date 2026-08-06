# Contributing to Nexus

Nexus is a pre-alpha macOS developer tool. Small, focused contributions are easier to review and less likely to disturb the trust boundary around local context.

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Before Opening a Pull Request

1. Keep SwiftUI in `Sources/NexusMac`, domain and persistence logic in `Sources/NexusCore`, and MCP protocol adaptation in `adapters/mcp`.
2. Do not add user materials, local databases, API keys, generated bundles, or machine-specific settings to the repository.
3. Preserve the product boundary: Nexus prepares, reviews, routes, and exposes context. It does not execute coding agents or mutate a user's Git state.
4. Add focused tests for Core and MCP contract changes.
5. Run the checks in the [development guide](docs/development.md).

Issues and pull requests are welcome. For security-sensitive reports, use GitHub private reporting rather than a public issue.
