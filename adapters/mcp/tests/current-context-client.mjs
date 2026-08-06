import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../..");
const helper = process.env.NEXUS_MCP_HELPER ?? resolve(repoRoot, "adapters/mcp/dist/index.js");
const helperArgs = process.env.NEXUS_MCP_HELPER ? [] : [helper];
const helperCommand = process.env.NEXUS_MCP_HELPER ? helper : process.execPath;
const fileId = process.argv[2];

async function callTool(client, name, args = {}) {
  return (await callRawTool(client, name, args)).json;
}

async function callRawTool(client, name, args = {}) {
  const result = await client.callTool({ name, arguments: args });
  const text = result.content?.[0]?.text;
  if (typeof text !== "string") {
    throw new Error(`${name} did not return text content`);
  }
  return {
    json: JSON.parse(text),
    structuredContent: result.structuredContent
  };
}

const transport = new StdioClientTransport({
  command: helperCommand,
  args: helperArgs,
  env: { ...process.env, NEXUS_MCP_ALLOW_HEADLESS: process.env.NEXUS_MCP_ALLOW_HEADLESS ?? "1" }
});
const client = new Client(
  { name: "nexus-current-context-test", version: "0.1.0" },
  { capabilities: {} }
);

await client.connect(transport);
try {
  const tools = await client.listTools();
  const currentResult = await callRawTool(client, "get_current_development_context");
  const current = currentResult.json;
  const active = await callTool(client, "get_active_task");
  const manifest = await callTool(client, "get_task_manifest");
  const brief = await callTool(client, "get_resume_brief");
  const output = {
    tools: tools.tools.map((tool) => tool.name),
    current_context: {
      schema_version: current.schema_version ?? "unknown",
      work_id: current.work_id,
      title: current.work?.title,
      revision: current.revision,
      structured_schema_version: currentResult.structuredContent?.schema_version ?? null,
      visible_file_count: current.materials?.readable?.filter((item) => item.kind === "file").length ?? 0,
      visible_note_count: current.materials?.readable?.filter((item) => item.kind === "note").length ?? 0,
      warning_count: current.warnings?.length ?? 0
    },
    active: {
      task_id: active.task_id,
      title: active.payload.title,
      revision: active.revision
    },
    manifest: {
      files: manifest.payload.files ?? [],
      notes: manifest.payload.notes ?? [],
      hidden_files: manifest.payload.hidden_files ?? [],
      supplement: manifest.payload.supplement ?? ""
    },
    brief: brief.payload.brief
  };
  const noteId = output.manifest.notes?.[0]?.id;
  if (noteId) {
    try {
      output.note_read = await callTool(client, "read_context_material", { material_id: noteId, kind: "note" });
    } catch (error) {
      output.note_read_error = String(error?.message ?? error);
    }
  }
  if (fileId) {
    try {
      output.file_read = await callTool(client, "read_context_material", { material_id: fileId, kind: "file", limit: 200 });
    } catch (error) {
      output.file_read_error = String(error?.message ?? error);
    }
  }
  console.log(JSON.stringify(output, null, 2));
} finally {
  await client.close();
}
