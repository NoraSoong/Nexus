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
const temporaryNexusHome = process.env.NEXUS_HOME ? undefined : mkdtempSync(join(tmpdir(), "nexus-stdio-"));
const nexusHome = process.env.NEXUS_HOME ?? temporaryNexusHome;
const debugBinary = process.env.NEXUS_DEBUG_BINARY ?? [
  resolve(repoRoot, ".build/swiftpm/debug/nexus-debug"),
  resolve(repoRoot, ".build/debug/nexus-debug")
].find(existsSync);
if (!debugBinary) {
  throw new Error("nexus-debug is not built; run swift build before the stdio regression");
}
if (temporaryNexusHome) {
  process.on("exit", () => rmSync(temporaryNexusHome, { recursive: true, force: true }));
}
const helper = process.env.NEXUS_MCP_HELPER ?? resolve(repoRoot, "adapters/mcp/dist/index.js");
const helperArgs = process.env.NEXUS_MCP_HELPER ? [] : [helper];
const helperCommand = process.env.NEXUS_MCP_HELPER ? helper : process.execPath;
const runtimePath = resolve(nexusHome, "Nexus.runtime.json");

function switchTask(task) {
  execFileSync(debugBinary, ["switch", task], {
    cwd: repoRoot,
    env: { ...process.env, NEXUS_HOME: nexusHome, NEXUS_MCP_ALLOW_HEADLESS: "1" },
    stdio: "pipe"
  });
}

function createTask(title, goal) {
  const output = execFileSync(debugBinary, ["create-task", title, goal], {
    cwd: repoRoot,
    env: { ...process.env, NEXUS_HOME: nexusHome, NEXUS_MCP_ALLOW_HEADLESS: "1" },
    encoding: "utf8",
    stdio: "pipe"
  }).trim();
  const match = /^created\s+(\S+)\s+/.exec(output);
  if (!match) {
    throw new Error(`Could not parse created task id from '${output}'`);
  }
  return match[1];
}

async function readActiveTask(expectedContextSchema = "2.1") {
  const transport = new StdioClientTransport({
    command: helperCommand,
    args: helperArgs,
    env: { ...process.env, NEXUS_HOME: nexusHome, NEXUS_MCP_ALLOW_HEADLESS: "1" }
  });
  const client = new Client(
    { name: "nexus-stdio-test", version: "0.1.0" },
    { capabilities: {} }
  );

  await client.connect(transport);
  try {
    const instructions = client.getInstructions() ?? "";
    if (!instructions.includes("get_current_development_context")) {
      throw new Error("server instructions do not mention get_current_development_context");
    }
    if (!instructions.toLowerCase().includes("optional local handoff context")) {
      throw new Error("server instructions do not frame Nexus as optional handoff context");
    }
    const tools = await client.listTools();
    const currentContextTool = tools.tools.find((tool) => tool.name === "get_current_development_context");
    if (!currentContextTool) {
      throw new Error("get_current_development_context tool not listed");
    }
    if (!currentContextTool.description?.toLowerCase().includes("optional handoff entry point")) {
      throw new Error("get_current_development_context description does not mark it as optional handoff context");
    }
    if (!currentContextTool.description?.toLowerCase().includes("do not call this by default")) {
      throw new Error("get_current_development_context description does not discourage default reads");
    }
    if (!tools.tools.some((tool) => tool.name === "get_active_task")) {
      throw new Error("get_active_task tool not listed");
    }
    if (!tools.tools.some((tool) => tool.name === "get_task_manifest")) {
      throw new Error("get_task_manifest tool not listed");
    }
    if (!tools.tools.some((tool) => tool.name === "read_task_note")) {
      throw new Error("read_task_note tool not listed");
    }
    if (!tools.tools.some((tool) => tool.name === "read_task_file")) {
      throw new Error("read_task_file tool not listed");
    }
    if (!tools.tools.some((tool) => tool.name === "read_context_material")) {
      throw new Error("read_context_material tool not listed");
    }
    const materialTool = tools.tools.find((tool) => tool.name === "read_context_material");
    if (!materialTool?.description?.includes("assistant-visible")) {
      throw new Error("read_context_material description does not mention assistant-visible materials");
    }
    const result = await client.callTool({ name: "get_active_task", arguments: {} });
    const text = result.content?.[0]?.text;
    if (typeof text !== "string") {
      throw new Error("get_active_task did not return text content");
    }
    const contextResult = await client.callTool({ name: "get_current_development_context", arguments: {} });
    const contextText = contextResult.content?.[0]?.text;
    if (typeof contextText !== "string") {
      throw new Error("get_current_development_context did not return text content");
    }
    const context = JSON.parse(contextText);
    if (!context.work?.title) {
      throw new Error("get_current_development_context did not include work.title");
    }
    if (context.schema_version !== expectedContextSchema) {
      throw new Error(`Expected current context schema_version ${expectedContextSchema}, got ${context.schema_version ?? "missing"}`);
    }
    if (!JSON.stringify(context).includes("read_context_material")) {
      throw new Error("get_current_development_context did not guide clients to read_context_material");
    }
    if ("active_context" in context || "compatibility" in context) {
      throw new Error("get_current_development_context still contains duplicate legacy wrappers");
    }
    const expectedKeys = [
      "binding",
      "confirmed_context",
      "context_pack_id",
      "context_revision",
      "materials",
      "repository",
      "revision",
      "schema_version",
      "source_freshness",
      "warnings",
      "work",
      "work_id",
      "workspace",
      "workspace_activity"
    ];
    if (JSON.stringify(Object.keys(context).sort()) !== JSON.stringify(expectedKeys)) {
      throw new Error(`Unexpected compact context contract keys: ${Object.keys(context).sort().join(", ")}`);
    }
    if (contextText.length > 24_000) {
      throw new Error(`Current context exceeded the 24,000 character budget: ${contextText.length}`);
    }
    if (contextResult.structuredContent?.schema_version !== expectedContextSchema) {
      throw new Error(`get_current_development_context did not return structuredContent schema_version ${expectedContextSchema}`);
    }
    return { active: JSON.parse(text), context };
  } finally {
    await client.close();
  }
}

function injectV2ContextPack(taskId) {
  const db = new DatabaseSync(resolve(nexusHome, "Nexus.sqlite"));
  try {
    const binding = db.prepare(
      "SELECT active_revision FROM context_bindings WHERE scope_type = 'global' AND scope_key = 'default' AND task_id = ?;"
    ).get(taskId);
    if (!binding?.active_revision) {
      throw new Error("Cannot inject v2 context pack without active binding");
    }
    const revision = binding.active_revision;
    const rows = db.prepare(
      "SELECT projection_type, payload_json FROM mcp_context_projections WHERE task_id = ? AND revision = ?;"
    ).all(taskId, revision);
    const update = db.prepare(
      "UPDATE mcp_context_projections SET payload_json = ? WHERE task_id = ? AND revision = ? AND projection_type = ?;"
    );
    const packId = "stdio-v2-pack";
    for (const row of rows) {
      const payload = JSON.parse(row.payload_json);
      if (row.projection_type === "active_task") {
        payload.context_pack_id = packId;
        payload.context_revision = revision;
        payload.effective_freshness = "fresh";
      } else if (row.projection_type === "manifest") {
        payload.context_pack = {
          id: packId,
          revision,
          brief: "Approved stdio v2 context",
          objective: "Verify MCP projection v2",
          scope_in: [],
          scope_out: [],
          confirmed_facts: [],
          constraints: [],
          acceptance_criteria: [],
          assumptions: [],
          questions: [],
          recommended_source_ids: [],
          effective_freshness: "fresh"
        };
        payload.source_index = [];
      } else if (row.projection_type === "resume_brief") {
        payload.brief = "Approved stdio v2 context";
        payload.context_pack_id = packId;
        payload.context_revision = revision;
        payload.effective_freshness = "fresh";
        payload.source_index = [];
      }
      update.run(JSON.stringify(payload), taskId, revision, row.projection_type);
    }
    return { packId, revision };
  } finally {
    db.close();
  }
}

function writeRuntimeStatus(state, exposureEnabled) {
  mkdirSync(nexusHome, { recursive: true });
  writeFileSync(runtimePath, JSON.stringify({
    schema_version: 1,
    state,
    exposure_enabled: exposureEnabled,
    app_pid: process.pid,
    last_seen_at: new Date().toISOString()
  }));
}

async function listToolsWithoutHeadless() {
  const transport = new StdioClientTransport({
    command: helperCommand,
    args: helperArgs,
    env: { ...process.env, NEXUS_HOME: nexusHome }
  });
  const client = new Client(
    { name: "nexus-stdio-runtime-test", version: "0.1.0" },
    { capabilities: {} }
  );

  await client.connect(transport);
  try {
    return await client.listTools();
  } finally {
    await client.close();
  }
}

const taskAID = createTask("Task A", "Verify Nexus MCP switching.");
const taskBID = createTask("Task B", "Verify Nexus MCP switching.");

switchTask(taskAID);
const taskAResult = await readActiveTask();
const taskA = taskAResult.active;
if (taskA.payload?.title !== "Task A") {
  throw new Error(`Expected Task A, got ${taskA.payload?.title ?? taskA.task_id}`);
}

switchTask(taskBID);
const taskBResult = await readActiveTask();
const taskB = taskBResult.active;
if (taskB.payload?.title !== "Task B") {
  throw new Error(`Expected Task B, got ${taskB.payload?.title ?? taskB.task_id}`);
}
if (taskB.revision <= taskA.revision) {
  throw new Error(`Expected revision to increase, got ${taskA.revision} -> ${taskB.revision}`);
}

const v2Fixture = injectV2ContextPack(taskB.task_id);
const v2Result = await readActiveTask("2.1");
if (v2Result.context.context_pack_id !== v2Fixture.packId) {
  throw new Error("Expected MCP v2 result to include approved context_pack_id");
}
if (v2Result.context.confirmed_context?.brief !== "Approved stdio v2 context") {
  throw new Error("Expected MCP v2 result to prefer the approved Context Pack brief");
}
if (v2Result.context.confirmed_context?.kind !== "confirmed_pack") {
  throw new Error("Expected MCP v2 result to identify confirmed Context Pack content");
}

writeRuntimeStatus("running", true);
const runningTools = await listToolsWithoutHeadless();
if (!runningTools.tools.some((tool) => tool.name === "get_current_development_context")) {
  throw new Error("Expected Nexus tools while runtime is running and assistant access is enabled");
}

writeRuntimeStatus("paused", false);
const pausedTools = await listToolsWithoutHeadless();
if (pausedTools.tools.length !== 0) {
  throw new Error("Expected no Nexus tools while assistant access is paused");
}

console.log(JSON.stringify({
  ok: true,
  taskA: { task_id: taskA.task_id, title: taskA.payload.title, revision: taskA.revision },
  taskB: { task_id: taskB.task_id, title: taskB.payload.title, revision: taskB.revision },
  contextPackV2: { id: v2Fixture.packId, revision: v2Fixture.revision },
  runtimeAccess: { runningTools: runningTools.tools.length, pausedTools: pausedTools.tools.length }
}, null, 2));
