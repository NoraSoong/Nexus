import { readFileSync } from "node:fs";

export const helperVersion = "0.1.0";

const packageMetadata = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8")
) as { dependencies?: Record<string, string> };

export const mcpSdkVersion = packageMetadata.dependencies?.["@modelcontextprotocol/sdk"] ?? "unknown";
