#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${NEXUS_PREVIEW_OUTPUT:-$ROOT/dist/preview}"
CACHE_DIR="${NEXUS_RUNTIME_CACHE:-${HOME}/Library/Caches/Nexus}"
APP_NAME="Nexus.app"
APP_VERSION="0.1.0-preview.1"
NODE_VERSION="v26.5.0"
NODE_ARCHIVE="node-${NODE_VERSION}-darwin-arm64.tar.gz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_ARCHIVE}"
NODE_CHECKSUM="$(awk '{print $1}' "$ROOT/packaging/node-runtime.sha256")"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This preview build supports Apple Silicon (arm64) only." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"
rm -rf "$OUTPUT_DIR/$APP_NAME" "$OUTPUT_DIR/dmg-staging"
rm -f "$OUTPUT_DIR"/Nexus-*.dmg "$OUTPUT_DIR"/SHA256SUMS

RUNTIME_ARCHIVE="$CACHE_DIR/$NODE_ARCHIVE"
if [[ ! -f "$RUNTIME_ARCHIVE" ]]; then
  echo "Downloading official Node ${NODE_VERSION} arm64 runtime..."
  curl --fail --location --silent --show-error "$NODE_URL" --output "$RUNTIME_ARCHIVE"
fi

EXPECTED="${NODE_CHECKSUM}  ${RUNTIME_ARCHIVE}"
printf '%s\n' "$EXPECTED" | shasum -a 256 -c -

SWIFT_SCRATCH="$ROOT/.build/preview-swiftpm"
swift build -c release --product NexusMac --scratch-path "$SWIFT_SCRATCH"
SWIFT_BIN_DIR="$(swift build -c release --product NexusMac --scratch-path "$SWIFT_SCRATCH" --show-bin-path)"

HELPER_BUILD_DIR="$ROOT/.build/preview-helper"
rm -rf "$HELPER_BUILD_DIR"
mkdir -p "$HELPER_BUILD_DIR"
cp "$ROOT/adapters/mcp/package.json" "$ROOT/adapters/mcp/package-lock.json" "$ROOT/adapters/mcp/tsconfig.json" "$HELPER_BUILD_DIR/"
cp -R "$ROOT/adapters/mcp/src" "$HELPER_BUILD_DIR/src"
pushd "$HELPER_BUILD_DIR" >/dev/null
npm ci
npm run build
npm prune --omit=dev
popd >/dev/null

APP_DIR="$OUTPUT_DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
HELPER_DIR="$RESOURCES_DIR/MCPHelper"
ICONSET_DIR="$ROOT/.build/preview-appicon.iconset"
ICON_PATH="$ROOT/.build/preview-Nexus.icns"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  double_size=$((size * 2))
  sips -z "$size" "$size" "$ROOT/packaging/AppIcon-master.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z "$double_size" "$double_size" "$ROOT/packaging/AppIcon-master.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
mkdir -p "$MACOS_DIR" "$HELPER_DIR/dist" "$HELPER_DIR/node_modules"

cp "$SWIFT_BIN_DIR/NexusMac" "$MACOS_DIR/NexusMac"
cp "$ROOT/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_PATH" "$RESOURCES_DIR/Nexus.icns"
cp -R "$HELPER_BUILD_DIR/dist/." "$HELPER_DIR/dist/"
cp -R "$HELPER_BUILD_DIR/node_modules/." "$HELPER_DIR/node_modules/"
cp "$HELPER_BUILD_DIR/package.json" "$HELPER_DIR/package.json"
cp "$HELPER_BUILD_DIR/package-lock.json" "$HELPER_DIR/package-lock.json"
node "$ROOT/scripts/generate-helper-notices.mjs" \
  "$HELPER_BUILD_DIR/package-lock.json" \
  "$HELPER_DIR/THIRD_PARTY_NOTICES.txt"
cp "$ROOT/packaging/helper-manifest.json.in" "$HELPER_DIR/manifest.json"
chmod +x "$MACOS_DIR/NexusMac"

RUNTIME_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nexus-node.XXXXXX")"
trap 'rm -rf "$RUNTIME_TMP"' EXIT
tar -xzf "$RUNTIME_ARCHIVE" -C "$RUNTIME_TMP"
cp "$RUNTIME_TMP/node-${NODE_VERSION}-darwin-arm64/bin/node" "$HELPER_DIR/node"
cp "$RUNTIME_TMP/node-${NODE_VERSION}-darwin-arm64/LICENSE" "$HELPER_DIR/node-LICENSE"
chmod +x "$HELPER_DIR/node"

"$HELPER_DIR/node" --version
"$HELPER_DIR/node" -e "import('node:sqlite').then(() => console.log('node:sqlite OK'))"

STAGING_DIR="$OUTPUT_DIR/dmg-staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$OUTPUT_DIR/Nexus-${APP_VERSION}-arm64.dmg"
hdiutil create -volname "Nexus ${APP_VERSION}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR"

shasum -a 256 "$DMG_PATH" | sed "s#${OUTPUT_DIR}/##" > "$OUTPUT_DIR/SHA256SUMS"
echo "$DMG_PATH"
