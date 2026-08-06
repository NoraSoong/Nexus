#!/usr/bin/env node

import { ProjectionDatabase, type BindingSelection } from "./sqlite/ProjectionDatabase.js";
import { runMcpServer } from "./mcpServer.js";
import { helperVersion } from "./version.js";

const args = process.argv.slice(2);
const selection = bindingSelection(args);

if (args.includes("--version")) {
  console.log(`nexus-mcp ${helperVersion}`);
  console.log(`node ${process.version}`);
  process.exit(0);
}

if (args.includes("--doctor")) {
  const db = new ProjectionDatabase(undefined, selection);
  console.log(JSON.stringify(db.doctor(), null, 2));
  process.exit(0);
}

runMcpServer(selection).catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`nexus-mcp error: ${message}`);
  process.exit(1);
});

function bindingSelection(values: string[]): BindingSelection {
  const bindingIdValue = optionValue(values, "--binding-id");
  const workspacePath = optionValue(values, "--workspace");
  let bindingId: number | undefined;
  if (bindingIdValue !== undefined) {
    bindingId = Number(bindingIdValue);
    if (!Number.isSafeInteger(bindingId) || bindingId <= 0) {
      throw new Error(`--binding-id requires a positive integer, got '${bindingIdValue}'`);
    }
  }
  return { bindingId, workspacePath };
}

function optionValue(values: string[], option: string): string | undefined {
  const index = values.indexOf(option);
  if (index < 0) {
    return undefined;
  }
  const value = values[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${option} requires a value`);
  }
  return value;
}
