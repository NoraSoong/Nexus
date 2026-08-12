# Developer Preview Release

## Scope

The current preview targets Apple Silicon Macs running macOS 14 or later. The DMG contains the Nexus app, the MCP Helper, and the pinned private Node.js Runtime. Users do not need to install Node.js separately.

The preview is not Developer ID signed or notarized. It is intended for local evaluation and dogfooding, not unattended enterprise deployment.

## Published Preview

The current public release is
[`v0.1.0-preview.1`](https://github.com/NoraSoong/Nexus/releases/tag/v0.1.0-preview.1).
Download the Apple Silicon DMG from the release page and verify it with the
included `SHA256SUMS` asset before opening it.

## Install and Connect

1. Open the DMG and drag `Nexus.app` to `Applications`.
2. Launch Nexus once. The app installs its bundled Helper into the app-managed
   Application Support directory and creates the stable MCP command.
3. Open Assistant Connection in Nexus and use the displayed configuration for
   the MCP client you use.
4. Keep Nexus running in the menu bar while an assistant needs to read context;
   pausing assistant access or quitting the app intentionally stops context
   exposure.

The app can be removed from `Applications` without deleting local Work data.
Do not remove the Nexus Application Support directory unless you also intend
to remove local context data and installed Helper versions.

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
