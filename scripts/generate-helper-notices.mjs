import { readFileSync, writeFileSync } from "node:fs";

const [, , lockPath, outputPath] = process.argv;
if (!lockPath || !outputPath) {
  throw new Error("usage: generate-helper-notices.mjs package-lock.json output.txt");
}

const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const entries = Object.entries(lock.packages ?? {})
  .filter(([path, metadata]) => path.startsWith("node_modules/") && metadata?.version)
  .map(([path, metadata]) => ({
    name: path.slice("node_modules/".length),
    version: metadata.version,
    license: metadata.license ?? "unspecified"
  }))
  .sort((a, b) => a.name.localeCompare(b.name));

const lines = [
  "Nexus MCP Helper third-party packages",
  "",
  ...entries.map((entry) => `${entry.name}@${entry.version} — ${entry.license}`),
  "",
  "Refer to each package's published license for the full license text."
];
writeFileSync(outputPath, `${lines.join("\n")}\n`, "utf8");
