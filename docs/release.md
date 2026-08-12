# Developer Preview Release

## Scope

The current preview targets Apple Silicon Macs running macOS 14 or later. The DMG contains the Nexus app, the MCP Helper, and the pinned private Node.js Runtime. Users do not need to install Node.js separately.

The preview is not Developer ID signed or notarized. It is intended for local evaluation and dogfooding, not unattended enterprise deployment.

## Build locally

```bash
scripts/build-preview.sh
scripts/verify-preview.sh
```

The build downloads `node-v26.5.0-darwin-arm64.tar.gz` from the official Node.js distribution and verifies the pinned SHA-256 before embedding the Runtime. Generated App and DMG files remain under `dist/`, which is ignored by Git.

## First launch

Nexus copies the bundled Helper into:

```text
~/Library/Application Support/Nexus/helpers/<helper-version>/
```

It then creates the stable MCP command:

```text
~/Library/Application Support/Nexus/bin/nexus-mcp
```

Existing MCP client configuration continues to use this stable path across Helper updates.

## Diagnostics

```bash
"$HOME/Library/Application Support/Nexus/bin/nexus-mcp" --version
"$HOME/Library/Application Support/Nexus/bin/nexus-mcp" --doctor
```

The diagnostic output includes runtime and projection compatibility information. It may include local paths; sanitize it before attaching to a public issue.
