import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { DatabaseSync } from "node:sqlite";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../..");
const nexusHome = mkdtempSync(join(tmpdir(), "nexus-binding-"));
const debugBinary = process.env.NEXUS_DEBUG_BINARY ?? [
  resolve(repoRoot, ".build/swiftpm/debug/nexus-debug"),
  resolve(repoRoot, ".build/debug/nexus-debug")
].find(existsSync);
if (!debugBinary) {
  throw new Error("nexus-debug is not built; run swift build before the binding regression");
}
const helper = resolve(repoRoot, "adapters/mcp/dist/index.js");
const repository = resolve(nexusHome, "repository");
const workspaceA = resolve(nexusHome, "worktrees", "requirement-a");
const workspaceB = resolve(nexusHome, "worktrees", "requirement-b");

mkdirSync(repository, { recursive: true });

function git(args) {
  return execFileSync("/usr/bin/git", args, {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: "pipe"
  }).trim();
}

git(["-C", repository, "init", "-b", "main"]);
git(["-C", repository, "config", "user.name", "Nexus Test"]);
git(["-C", repository, "config", "user.email", "nexus-test@example.invalid"]);
writeFileSync(resolve(repository, "README.md"), "# Parallel binding fixture\n");
git(["-C", repository, "add", "README.md"]);
git(["-C", repository, "commit", "-m", "Initial fixture"]);
git(["-C", repository, "worktree", "add", "-b", "requirement-a", workspaceA]);
git(["-C", repository, "worktree", "add", "-b", "requirement-b", workspaceB]);

function debug(args) {
  return execFileSync(debugBinary, args, {
    cwd: repoRoot,
    env: { ...process.env, NEXUS_HOME: nexusHome },
    encoding: "utf8"
  }).trim();
}

function taskId(title) {
  const line = debug(["list-tasks"])
    .split("\n")
    .find((value) => value.split("\t")[1] === title);
  if (!line) {
    throw new Error(`Task '${title}' not found`);
  }
  return line.split("\t")[0];
}

function bindingForWorkspace(path) {
  const db = new DatabaseSync(resolve(nexusHome, "Nexus.sqlite"), { readOnly: true });
  try {
    return db.prepare(
      `SELECT id, task_id, active_revision
       FROM context_bindings
       WHERE scope_type = 'workspace' AND scope_key = ?;`
    ).get(path);
  } finally {
    db.close();
  }
}

async function connect(args, extraEnv = {}) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [helper, ...args],
    cwd: repoRoot,
    env: {
      ...process.env,
      ...extraEnv,
      NEXUS_HOME: nexusHome,
      NEXUS_MCP_ALLOW_HEADLESS: "1"
    }
  });
  const client = new Client(
    { name: "nexus-binding-test", version: "0.1.0" },
    { capabilities: {} }
  );
  await client.connect(transport);
  return client;
}

async function context(client) {
  const result = await client.callTool({
    name: "get_current_development_context",
    arguments: {}
  });
  const text = result.content?.[0]?.text;
  if (typeof text !== "string") {
    throw new Error("Nexus context did not return text");
  }
  return JSON.parse(text);
}

try {
  debug(["bootstrap"]);
  debug(["create-task", "Parallel A", "Implement requirement A"]);
  const taskA = taskId("Parallel A");
  debug(["create-task", "Parallel B", "Implement requirement B"]);
  const taskB = taskId("Parallel B");
  debug(["repo", taskA, workspaceA]);
  debug(["repo", taskB, workspaceB]);
  debug(["switch", taskA]);

  const bindingA = bindingForWorkspace(workspaceA);
  const bindingB = bindingForWorkspace(workspaceB);
  if (!bindingA || !bindingB) {
    throw new Error("Expected workspace bindings for both tasks");
  }

  const clientA = await connect(["--workspace", workspaceA]);
  const clientB = await connect(["--binding-id", String(bindingB.id)]);
  const globalClient = await connect([]);
  try {
    debug(["switch", taskB]);
    const pinnedBeforeFirstRead = await context(globalClient);
    if (pinnedBeforeFirstRead.work_id !== taskA) {
      throw new Error(
        `Helper did not pin the global binding when its stdio process started; expected ${taskA}, got ${String(pinnedBeforeFirstRead.work_id)}`
      );
    }

    const initialA = await context(clientA);
    const initialB = await context(clientB);
    if (initialA.work_id !== taskA || initialA.binding.resolution !== "workspace") {
      throw new Error("Workspace-resolved helper did not bind to requirement A");
    }
    if (initialB.work_id !== taskB || initialB.binding.resolution !== "explicit_binding") {
      throw new Error("Explicit helper did not bind to requirement B");
    }

    debug(["switch", taskB]);
    debug(["switch", taskA]);
    const afterGlobalSwitchA = await context(clientA);
    const afterGlobalSwitchB = await context(clientB);
    if (afterGlobalSwitchA.work_id !== taskA || afterGlobalSwitchB.work_id !== taskB) {
      throw new Error("Running helpers followed the global work switch");
    }

    const beforeARevision = afterGlobalSwitchA.revision;
    const beforeBRevision = afterGlobalSwitchB.revision;
    debug(["add-note", taskA, "A-only evidence", "Only requirement A should advance", "true"]);
    const updatedA = await context(clientA);
    const unchangedB = await context(clientB);
    if (updatedA.revision <= beforeARevision) {
      throw new Error("Requirement A binding did not advance after its context changed");
    }
    if (unchangedB.revision !== beforeBRevision) {
      throw new Error("Requirement B binding changed when only requirement A was updated");
    }

    debug(["switch", taskB]);
    debug(["archive-task", taskA]);
    let invalidated = false;
    try {
      await context(clientA);
    } catch (error) {
      invalidated = String(error).includes("no longer exists");
    }
    if (!invalidated) {
      throw new Error("Deleted workspace binding did not fail explicitly");
    }

    console.log(JSON.stringify({
      ok: true,
      taskA: {
        task_id: taskA,
        binding_id: bindingA.id,
        initial_revision: beforeARevision,
        updated_revision: updatedA.revision,
        invalidated_after_archive: true
      },
      taskB: {
        task_id: taskB,
        binding_id: bindingB.id,
        revision: unchangedB.revision
      },
      global_switch_isolated: true,
      global_launch_snapshot_isolated: true
    }, null, 2));
  } finally {
    await clientA.close();
    await clientB.close();
    await globalClient.close();
  }
} finally {
  rmSync(nexusHome, { recursive: true, force: true });
}
