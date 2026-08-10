import { closeSync, mkdtempSync, openSync, rmSync, truncateSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  maximumTextFileByteCount,
  readSupportedTextFilePage
} from "../dist/textFilePolicy.js";

const root = mkdtempSync(join(tmpdir(), "nexus-text-policy-"));

try {
  const utf8Path = join(root, "context.md");
  writeFileSync(utf8Path, "Nexus context\n中文内容🙂tail", "utf8");
  const utf8First = readSupportedTextFilePage(utf8Path, 0, 18);
  const utf8Second = readSupportedTextFilePage(
    utf8Path,
    utf8First.nextOffset ?? utf8First.body.length,
    18
  );
  if (utf8First.body + utf8Second.body !== "Nexus context\n中文内容🙂tail") {
    throw new Error("UTF-8 context file pagination was not decoded correctly");
  }
  const emojiBoundary = readSupportedTextFilePage(utf8Path, 0, 19);
  if (!emojiBoundary.body.endsWith("🙂") || emojiBoundary.nextOffset !== 20) {
    throw new Error("UTF-8 pagination split a surrogate pair");
  }
  const lowSurrogateOffset = readSupportedTextFilePage(utf8Path, 19, 10);
  if (lowSurrogateOffset.offset !== 20 || lowSurrogateOffset.body !== "tail") {
    throw new Error("UTF-8 pagination did not recover from a low-surrogate offset");
  }

  const utf16Path = join(root, "context.txt");
  const utf16Body = Buffer.from("Nexus UTF-16", "utf16le");
  writeFileSync(utf16Path, Buffer.concat([Buffer.from([0xff, 0xfe]), utf16Body]));
  if (readSupportedTextFilePage(utf16Path, 0, 100).body !== "Nexus UTF-16") {
    throw new Error("UTF-16 context file was not decoded correctly");
  }

  const utf16NoBOMPath = join(root, "context-no-bom.txt");
  writeFileSync(utf16NoBOMPath, Buffer.from("Nexus UTF-16 no BOM", "utf16le"));
  if (readSupportedTextFilePage(utf16NoBOMPath, 0, 100).body !== "Nexus UTF-16 no BOM") {
    throw new Error("UTF-16 context file without BOM was not decoded correctly");
  }

  const binaryPath = join(root, "binary.log");
  writeFileSync(binaryPath, Buffer.from([0x41, 0x00, 0x42, 0x01]));
  assertRejected(binaryPath, "binary");

  const emptyPath = join(root, "empty.txt");
  writeFileSync(emptyPath, "");
  assertRejected(emptyPath, "empty");

  const invalidPath = join(root, "invalid.txt");
  writeFileSync(invalidPath, Buffer.from([0xff, 0xff, 0xff]));
  assertRejected(invalidPath, "not valid");

  const oversizedPath = join(root, "oversized.log");
  const oversizedDescriptor = openSync(oversizedPath, "w");
  closeSync(oversizedDescriptor);
  truncateSync(oversizedPath, maximumTextFileByteCount + 1);
  assertRejected(oversizedPath, "too large");

  const unsupportedPath = join(root, "document.pdf");
  writeFileSync(unsupportedPath, "%PDF-1.7", "utf8");
  assertRejected(unsupportedPath, "Unsupported context file type");

  console.log(JSON.stringify({ ok: true, cases: 8 }, null, 2));
} finally {
  rmSync(root, { recursive: true, force: true });
}

function assertRejected(path, expectedMessage) {
  try {
    readSupportedTextFilePage(path, 0, 8000);
  } catch (error) {
    if (String(error?.message ?? error).includes(expectedMessage)) {
      return;
    }
    throw error;
  }
  throw new Error(`Expected '${path}' to be rejected`);
}
