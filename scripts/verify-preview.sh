#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${NEXUS_PREVIEW_OUTPUT:-$ROOT/dist/preview}"
APP_DIR="$OUTPUT_DIR/Nexus.app"
HELPER_DIR="$APP_DIR/Contents/Resources/MCPHelper"

[[ -d "$APP_DIR" ]]
[[ -x "$APP_DIR/Contents/MacOS/NexusMac" ]]
[[ -f "$APP_DIR/Contents/Resources/AppIcon.icns" ]]
[[ -x "$HELPER_DIR/node" ]]
[[ -f "$HELPER_DIR/dist/index.js" ]]
[[ -f "$HELPER_DIR/manifest.json" ]]

plutil -lint "$APP_DIR/Contents/Info.plist"
[[ "$(file -b "$APP_DIR/Contents/MacOS/NexusMac")" == *arm64* ]]
[[ "$($HELPER_DIR/node --version)" == "v26.5.0" ]]
[[ "$($HELPER_DIR/node -e "import('node:sqlite').then(() => process.stdout.write('ok'))")" == "ok" ]]
"$HELPER_DIR/node" "$HELPER_DIR/dist/index.js" --version

DMG_PATH="$(find "$OUTPUT_DIR" -maxdepth 1 -name 'Nexus-*.dmg' -print -quit)"
[[ -n "$DMG_PATH" ]]
hdiutil imageinfo "$DMG_PATH" >/dev/null
(cd "$OUTPUT_DIR" && shasum -a 256 -c SHA256SUMS)
echo "Preview package verification passed."
