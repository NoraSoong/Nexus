import { readFileSync } from "node:fs";
import { extname } from "node:path";

const supportedTextExtensions = new Set([
  "c", "cc", "conf", "cpp", "csv", "go", "h", "hpp", "ini", "java", "js", "json", "jsonl",
  "jsx", "kt", "kts", "log", "md", "markdown", "mjs", "mm", "py", "rb", "rs", "sh", "sql",
  "swift", "toml", "ts", "tsx", "txt", "xml", "yaml", "yml", "zsh"
]);

export function readSupportedTextFile(path: string): string {
  const extension = extname(path).slice(1).toLowerCase();
  if (!supportedTextExtensions.has(extension)) {
    throw new Error(
      `Unsupported context file type '${extension || "unknown"}'. Nexus only reads supported text files.`
    );
  }

  const data = readFileSync(path);
  if (data.length === 0) {
    return "";
  }

  if (data[0] === 0xff && data[1] === 0xfe) {
    return data.subarray(2).toString("utf16le");
  }
  if (data[0] === 0xfe && data[1] === 0xff) {
    const body = Buffer.from(data.subarray(2));
    body.swap16();
    return body.toString("utf16le");
  }

  const sample = data.subarray(0, Math.min(data.length, 8_192));
  if (sample.includes(0)) {
    throw new Error("Unsupported binary context file. Nexus only reads text materials.");
  }

  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(data);
  } catch {
    throw new Error("Context file is not valid UTF-8 or UTF-16 text.");
  }
}
