#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_NEXUS_HOME="${HOME}/Library/Application Support/Nexus"
NEXUS_HOME="${NEXUS_HOME:-$DEFAULT_NEXUS_HOME}"
HELPER_VERSION="0.1.0"
NODE_VERSION="v26.5.0"
NODE_BIN="${NODE_BIN:-}"
if [[ -z "$NODE_BIN" ]]; then
  NODE_BIN="$(command -v node || true)"
fi

if [[ -z "$NODE_BIN" ]]; then
  echo "node not found; provide NODE_BIN=/path/to/node" >&2
  exit 1
fi

ACTUAL_NODE_VERSION="$("$NODE_BIN" --version)"
if [[ "$ACTUAL_NODE_VERSION" != "$NODE_VERSION" ]]; then
  echo "expected Node $NODE_VERSION but found $ACTUAL_NODE_VERSION at $NODE_BIN" >&2
  exit 1
fi

cd "$ROOT/adapters/mcp"
"$NODE_BIN" node_modules/typescript/bin/tsc -p tsconfig.json

HELPER_DIR="$NEXUS_HOME/helpers/$HELPER_VERSION"
BIN_DIR="$NEXUS_HOME/bin"
mkdir -p "$HELPER_DIR" "$BIN_DIR"

printf -v QUOTED_NEXUS_HOME '%q' "$NEXUS_HOME"
printf -v QUOTED_NODE_BIN '%q' "$NODE_BIN"
printf -v QUOTED_HELPER_ENTRYPOINT '%q' "$HELPER_DIR/dist/index.js"

rm -rf "$HELPER_DIR/dist"
cp -R "$ROOT/adapters/mcp/dist" "$HELPER_DIR/dist"
rm -rf "$HELPER_DIR/node_modules"
cp -R "$ROOT/adapters/mcp/node_modules" "$HELPER_DIR/node_modules"
cp "$ROOT/adapters/mcp/package.json" "$HELPER_DIR/package.json"
cat > "$HELPER_DIR/package-metadata.json" <<JSON
{
  "helperVersion": "$HELPER_VERSION",
  "nodeVersion": "$NODE_VERSION",
  "projectionSchemaVersion": 2,
  "runtimeMode": "external-node-dev",
  "nodePath": "$NODE_BIN"
}
JSON

cat > "$BIN_DIR/nexus-mcp" <<SH
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "\${NEXUS_HOME:-}" ]]; then
  NEXUS_HOME=$QUOTED_NEXUS_HOME
fi
export NEXUS_HOME
exec $QUOTED_NODE_BIN $QUOTED_HELPER_ENTRYPOINT "\$@"
SH
chmod +x "$BIN_DIR/nexus-mcp"

echo "$BIN_DIR/nexus-mcp"
