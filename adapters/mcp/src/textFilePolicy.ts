import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { extname } from "node:path";

const supportedTextExtensions = new Set([
  "c", "cc", "conf", "cpp", "csv", "go", "h", "hpp", "ini", "java", "js", "json", "jsonl",
  "jsx", "kt", "kts", "log", "md", "markdown", "mjs", "mm", "py", "rb", "rs", "sh", "sql",
  "swift", "toml", "ts", "tsx", "txt", "xml", "yaml", "yml", "zsh"
]);

export const maximumTextFileByteCount = 64 * 1024 * 1024;

const sampleByteCount = 8 * 1024;
const chunkByteCount = 64 * 1024;

type TextEncoding = "utf-8" | "utf-16le" | "utf-16be";

export type TextFilePage = {
  body: string;
  offset: number;
  nextOffset: number | null;
  encoding: TextEncoding;
  byteCount: number;
};

export function readSupportedTextFilePage(path: string, offset: number, limit: number): TextFilePage {
  assertSupportedExtension(path);
  const requestedOffset = Math.max(0, Math.floor(offset));
  const requestedLimit = Math.max(1, Math.floor(limit));
  const descriptor = openSync(path, "r");
  try {
    const before = fstatSync(descriptor);
    if (!before.isFile()) {
      throw new Error("Path is not a regular file.");
    }
    if (before.size === 0) {
      throw new Error("Context file is empty.");
    }
    if (before.size > maximumTextFileByteCount) {
      throw new Error("Context file is too large. Add a smaller excerpt instead.");
    }

    const sampleBuffer = Buffer.allocUnsafe(Math.min(sampleByteCount, before.size));
    const sampleLength = readSync(descriptor, sampleBuffer, 0, sampleBuffer.length, 0);
    const detected = detectEncoding(sampleBuffer.subarray(0, sampleLength));
    const decoder = new TextDecoder(detected.encoding, { fatal: true });
    const readBuffer = Buffer.allocUnsafe(chunkByteCount);
    let byteOffset = detected.bomByteCount;
    let decodedOffset = 0;
    let actualOffset = requestedOffset;
    let collected = "";
    let stoppedEarly = false;

    while (byteOffset < before.size) {
      const bytesRead = readSync(
        descriptor,
        readBuffer,
        0,
        Math.min(readBuffer.length, before.size - byteOffset),
        byteOffset
      );
      if (bytesRead === 0) {
        break;
      }
      byteOffset += bytesRead;
      const decoded = decoder.decode(readBuffer.subarray(0, bytesRead), { stream: true });
      const hadCollectedText = collected.length > 0;
      const consumed = collectPageText(decoded, requestedOffset, requestedLimit, decodedOffset, collected);
      decodedOffset += decoded.length;
      collected = consumed.collected;
      if (!hadCollectedText && collected.length > 0) {
        actualOffset = consumed.actualOffset;
      }
      if (collected.length > requestedLimit + 1) {
        stoppedEarly = true;
        break;
      }
    }

    if (!stoppedEarly) {
      const finalText = decoder.decode();
      const hadCollectedText = collected.length > 0;
      const consumed = collectPageText(finalText, requestedOffset, requestedLimit, decodedOffset, collected);
      decodedOffset += finalText.length;
      collected = consumed.collected;
      if (!hadCollectedText && collected.length > 0) {
        actualOffset = consumed.actualOffset;
      }
    }

    let outputLength = Math.min(requestedLimit, collected.length);
    if (
      outputLength > 0 &&
      outputLength < collected.length &&
      isHighSurrogate(collected.charCodeAt(outputLength - 1)) &&
      isLowSurrogate(collected.charCodeAt(outputLength))
    ) {
      outputLength += 1;
    }
    const body = collected.slice(0, outputLength);
    const hasMore = stoppedEarly || collected.length > outputLength || decodedOffset > actualOffset + body.length;

    const after = fstatSync(descriptor);
    if (before.size !== after.size || before.mtimeMs !== after.mtimeMs) {
      throw new Error("Context file changed while it was being read. Try again.");
    }
    return {
      body,
      offset: actualOffset,
      nextOffset: hasMore ? actualOffset + body.length : null,
      encoding: detected.encoding,
      byteCount: before.size
    };
  } catch (error) {
    if (error instanceof TypeError) {
      throw new Error("Context file is not valid UTF-8 or UTF-16 text.");
    }
    throw error;
  } finally {
    closeSync(descriptor);
  }
}

function assertSupportedExtension(path: string): void {
  const extension = extname(path).slice(1).toLowerCase();
  if (!supportedTextExtensions.has(extension)) {
    throw new Error(
      `Unsupported context file type '${extension || "unknown"}'. Nexus only reads supported text files.`
    );
  }
}

function collectPageText(
  value: string,
  requestedOffset: number,
  requestedLimit: number,
  decodedOffset: number,
  existing: string
): { collected: string; actualOffset: number } {
  if (value.length === 0 || decodedOffset + value.length <= requestedOffset) {
    return { collected: existing, actualOffset: requestedOffset };
  }
  let localStart = Math.max(0, requestedOffset - decodedOffset);
  let actualOffset = requestedOffset;
  if (existing.length === 0 && localStart < value.length && isLowSurrogate(value.charCodeAt(localStart))) {
    localStart += 1;
    actualOffset += 1;
  }
  const remaining = requestedLimit + 2 - existing.length;
  if (remaining <= 0) {
    return { collected: existing, actualOffset };
  }
  return {
    collected: existing + value.slice(localStart, localStart + remaining),
    actualOffset
  };
}

function detectEncoding(sample: Buffer): { encoding: TextEncoding; bomByteCount: number } {
  if (sample.length === 0) {
    throw new Error("Context file is empty.");
  }
  if (sample[0] === 0xef && sample[1] === 0xbb && sample[2] === 0xbf) {
    return { encoding: "utf-8", bomByteCount: 3 };
  }
  if (sample[0] === 0xff && sample[1] === 0xfe) {
    return { encoding: "utf-16le", bomByteCount: 2 };
  }
  if (sample[0] === 0xfe && sample[1] === 0xff) {
    return { encoding: "utf-16be", bomByteCount: 2 };
  }
  const inferred = inferUTF16Encoding(sample);
  if (inferred) {
    return { encoding: inferred, bomByteCount: 0 };
  }
  if (sample.includes(0)) {
    throw new Error("Unsupported binary context file. Nexus only reads text materials.");
  }
  try {
    new TextDecoder("utf-8", { fatal: true }).decode(sample, { stream: true });
    return { encoding: "utf-8", bomByteCount: 0 };
  } catch {
    throw new Error("Context file is not valid UTF-8 or UTF-16 text.");
  }
}

function inferUTF16Encoding(sample: Buffer): TextEncoding | null {
  const evenLength = sample.length - (sample.length % 2);
  if (evenLength < 8) {
    return null;
  }
  const prefix = sample.subarray(0, evenLength);
  let evenZeros = 0;
  let oddZeros = 0;
  for (let index = 0; index < evenLength; index += 2) {
    if (prefix[index] === 0) evenZeros += 1;
    if (prefix[index + 1] === 0) oddZeros += 1;
  }
  const pairCount = evenLength / 2;
  const threshold = Math.max(1, Math.floor(pairCount / 5));
  if (oddZeros >= threshold && evenZeros * 4 < oddZeros && decodedScore(prefix, "utf-16le") >= 0.85) {
    return "utf-16le";
  }
  if (evenZeros >= threshold && oddZeros * 4 < evenZeros && decodedScore(prefix, "utf-16be") >= 0.85) {
    return "utf-16be";
  }
  const littleScore = decodedScore(prefix, "utf-16le");
  const bigScore = decodedScore(prefix, "utf-16be");
  if (Math.max(littleScore, bigScore) < 0.85 || Math.abs(littleScore - bigScore) < 0.1) {
    return null;
  }
  return littleScore > bigScore ? "utf-16le" : "utf-16be";
}

function decodedScore(data: Buffer, encoding: TextEncoding): number {
  try {
    return printableScore(new TextDecoder(encoding, { fatal: true }).decode(data));
  } catch {
    return 0;
  }
}

function printableScore(value: string): number {
  const characters = Array.from(value);
  if (characters.length === 0) {
    return 0;
  }
  const printable = characters.filter((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return character === "\n" || character === "\r" || character === "\t" || codePoint >= 0x20;
  }).length;
  return printable / characters.length;
}

function isHighSurrogate(value: number): boolean {
  return value >= 0xd800 && value <= 0xdbff;
}

function isLowSurrogate(value: number): boolean {
  return value >= 0xdc00 && value <= 0xdfff;
}
