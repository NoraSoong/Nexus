import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readSupportedTextFile } from "../dist/textFilePolicy.js";

const root = mkdtempSync(join(tmpdir(), "nexus-text-policy-"));

try {
  const utf8Path = join(root, "context.md");
  writeFileSync(utf8Path, "Nexus context\n中文内容", "utf8");
  if (readSupportedTextFile(utf8Path) !== "Nexus context\n中文内容") {
    throw new Error("UTF-8 context file was not decoded correctly");
  }

  const utf16Path = join(root, "context.txt");
  const utf16Body = Buffer.from("Nexus UTF-16", "utf16le");
  writeFileSync(utf16Path, Buffer.concat([Buffer.from([0xff, 0xfe]), utf16Body]));
  if (readSupportedTextFile(utf16Path) !== "Nexus UTF-16") {
    throw new Error("UTF-16 context file was not decoded correctly");
  }

  const binaryPath = join(root, "binary.log");
  writeFileSync(binaryPath, Buffer.from([0x41, 0x00, 0x42, 0x01]));
  assertRejected(binaryPath, "binary");

  const unsupportedPath = join(root, "document.pdf");
  writeFileSync(unsupportedPath, "%PDF-1.7", "utf8");
  assertRejected(unsupportedPath, "Unsupported context file type");

  console.log(JSON.stringify({ ok: true, cases: 4 }, null, 2));
} finally {
  rmSync(root, { recursive: true, force: true });
}

function assertRejected(path, expectedMessage) {
  try {
    readSupportedTextFile(path);
  } catch (error) {
    if (String(error?.message ?? error).includes(expectedMessage)) {
      return;
    }
    throw error;
  }
  throw new Error(`Expected '${path}' to be rejected`);
}
