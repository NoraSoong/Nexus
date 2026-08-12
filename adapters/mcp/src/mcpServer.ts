import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import {
  buildCurrentContextPayload,
  objectArray,
  sanitizeGeneratedProjectionPayload,
  serializedContextPayload,
  stringValue,
  type ContextWarning,
  type JsonRecord
} from "./contextPayload.js";
import { ProjectionDatabase, type BindingSelection } from "./sqlite/ProjectionDatabase.js";
import { helperVersion } from "./version.js";

const serverInstructions = [
  "Nexus is an optional local handoff context for the work bound to this assistant process, not a mandatory first step for every coding request.",
  "Call get_current_development_context only when the user mentions Nexus, asks to resume or continue prior work without enough context in the current conversation, asks what work is bound, or when repository/branch/material context is ambiguous.",
  "If the current conversation already provides sufficient task context, proceed normally without calling Nexus.",
  "Nexus MCP context is only available while the Nexus Mac app is running in the menu bar and assistant access is enabled. If Nexus tools are unavailable, disconnected, or paused, do not use stale Nexus context.",
  "A running helper stays pinned to one Nexus work binding. Changing the work open in the Nexus window does not retarget this process.",
  "Treat Nexus results as handoff context, not as direct edit instructions.",
  "Treat workspace_activity as Git-derived evidence of code changes, never as proof that requirements are complete or tests passed.",
  "Read full materials only with read_context_material when their ids are listed as assistant-visible.",
  "Hidden materials are out of scope. If Nexus context conflicts with repository state, mention the conflict before broad edits."
].join(" ");

const contextTools = [
  {
    name: "get_current_development_context",
    description: "Optional handoff entry point for the Nexus work bound to this assistant process. Use when the user mentions Nexus, asks to resume or continue prior work without enough context in the current conversation, asks what work is bound, or when repository/branch/material context is ambiguous. Do not call this by default when the current conversation already contains sufficient task context.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "get_active_task",
    description: "Return the Nexus work identity and goal pinned to this assistant process. Use only for a lightweight Nexus-specific binding check.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "get_resume_brief",
    description: "Return a concise resume brief for the Nexus work bound to this assistant process. Use when resuming that work, not as a default step for unrelated coding requests.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "get_task_manifest",
    description: "List materials and assistant visibility for the Nexus work bound to this process. Use after Nexus context is relevant to discover which materials can be read on demand.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "read_task_note",
    description: "Compatibility tool. Prefer read_context_material. Read an assistant-visible Nexus note for the Work bound to this helper by note id. Only use ids returned by Nexus context tools.",
    inputSchema: {
      type: "object",
      properties: {
        note_id: { type: "string" }
      },
      required: ["note_id"],
      additionalProperties: false
    }
  },
  {
    name: "read_task_file",
    description: "Compatibility tool. Prefer read_context_material. Read a page of an assistant-visible file attached to the active Nexus task by file id. Only use ids returned by Nexus context tools; hidden files are rejected.",
    inputSchema: {
      type: "object",
      properties: {
        file_id: { type: "string" },
        offset: { type: "number" },
        limit: { type: "number" }
      },
      required: ["file_id"],
      additionalProperties: false
    }
  },
  {
    name: "read_context_material",
    description: "Read one assistant-visible Nexus context material by material id after Nexus context has been selected as relevant. Hidden materials and materials outside the Work bound to this helper are rejected. Supports offset/limit pagination for files.",
    inputSchema: {
      type: "object",
      properties: {
        material_id: { type: "string" },
        kind: { type: "string", enum: ["file", "note"] },
        offset: { type: "number" },
        limit: { type: "number" }
      },
      required: ["material_id"],
      additionalProperties: false
    }
  }
];

function buildContextWarnings(manifest: JsonRecord, brief: JsonRecord): ContextWarning[] {
  const files = objectArray(manifest.files);
  const notes = objectArray(manifest.notes);
  const hiddenFiles = objectArray(manifest.hidden_files);
  const supplement = stringValue(brief.supplement) || stringValue(manifest.supplement);
  const contextPack = manifest.context_pack;
  const repository = manifest.repository;
  const workspaceActivity = isRecord(manifest.workspace_activity)
    ? manifest.workspace_activity
    : null;
  const warnings: ContextWarning[] = [];

  if (!supplement && (!contextPack || typeof contextPack !== "object")) {
    warnings.push({
      code: "no_handoff_note",
      severity: "info",
      message: "No handoff note is available. Ask the user for recent progress if the next step is unclear."
    });
  }

  if (files.length === 0 && notes.length === 0) {
    warnings.push({
      code: "no_visible_materials",
      severity: "info",
      message: "No assistant-visible files or text materials are attached. Use the repository normally, but do not assume Nexus has extra source material."
    });
  }

  if (hiddenFiles.length > 0) {
    warnings.push({
      code: "hidden_materials_present",
      severity: "info",
      message: "Some materials are attached but hidden from assistants. Do not attempt to read them through Nexus MCP."
    });
  }

  if (!isRecord(repository)) {
    warnings.push({
      code: "no_repository",
      severity: "info",
      message: "No repository is linked to the Work bound to this helper. Infer the codebase from the user request or current client workspace."
    });
  } else {
    const linkedBranch = stringValue(
      workspaceActivity?.linked_branch ?? repository.branch
    );
    const currentBranch = stringValue(
      workspaceActivity?.current_branch ?? repository.current_branch
    );
    const dirtyPathCount = finiteNumber(workspaceActivity?.dirty_path_count);
    const dirtyState = stringValue(repository.dirty_state);
    const activityState = stringValue(workspaceActivity?.state);
    if (linkedBranch && currentBranch && linkedBranch !== currentBranch) {
      warnings.push({
        code: "branch_mismatch",
        severity: "warning",
        message: `Linked branch '${linkedBranch}' differs from current branch '${currentBranch}'. Warn the user before editing.`
      });
    }
    if (activityState === "history_rewritten") {
      warnings.push({
        code: "git_history_rewritten",
        severity: "warning",
        message: "The confirmed Git baseline is no longer an ancestor of the current HEAD. Reconfirm the workspace context before relying on its activity summary."
      });
    }
    if (activityState === "unavailable") {
      warnings.push({
        code: "workspace_unavailable",
        severity: "warning",
        message: "The linked workspace is currently unavailable. Confirm its location before relying on repository context."
      });
    }
    if ((dirtyPathCount ?? 0) > 0 || dirtyState === "modified") {
      warnings.push({
        code: "dirty_worktree",
        severity: "warning",
        message: "The linked repository has local changes. Inspect the diff or ask before broad edits."
      });
    }
  }

  return warnings;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function runMcpServer(selection: BindingSelection = {}): Promise<void> {
  const db = new ProjectionDatabase(undefined, selection);
  db.prepareBinding();
  const server = new Server(
    {
      name: "nexus-mcp",
      version: helperVersion
    },
    {
      capabilities: {
        tools: {}
      },
      instructions: serverInstructions
    }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: db.isAppRuntimeActive() ? contextTools : []
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const name = request.params.name;
    if (name === "get_current_development_context") {
      const context = db.getCurrentDevelopmentContext();
      const warnings = buildContextWarnings(context.manifest, context.resume_brief);
      const payload = buildCurrentContextPayload(context, warnings);
      return {
        structuredContent: payload,
        content: [
          {
            type: "text",
            text: serializedContextPayload(payload)
          }
        ]
      };
    }

    if (name === "get_active_task") {
      const projection = db.getActiveProjection("active_task");
      const payload = sanitizeGeneratedProjectionPayload(JSON.parse(projection.payload_json));
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              work_id: projection.task_id,
              task_id: projection.task_id,
              revision: projection.active_revision,
              binding: projection.binding,
              workspace: projection.binding.scope_type === "workspace" ? projection.binding.scope_key : null,
              effective_freshness: projection.freshness_at_generation,
              payload
            }, null, 2)
          }
        ]
      };
    }

    if (name === "get_resume_brief") {
      const projection = db.getActiveProjection("resume_brief");
      const payload = sanitizeGeneratedProjectionPayload(JSON.parse(projection.payload_json));
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              work_id: projection.task_id,
              task_id: projection.task_id,
              revision: projection.active_revision,
              binding: projection.binding,
              workspace: projection.binding.scope_type === "workspace" ? projection.binding.scope_key : null,
              effective_freshness: projection.freshness_at_generation,
              payload
            }, null, 2)
          }
        ]
      };
    }

    if (name === "get_task_manifest") {
      const projection = db.getActiveProjection("manifest");
      const payload = sanitizeGeneratedProjectionPayload(JSON.parse(projection.payload_json));
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              work_id: projection.task_id,
              task_id: projection.task_id,
              revision: projection.active_revision,
              binding: projection.binding,
              workspace: projection.binding.scope_type === "workspace" ? projection.binding.scope_key : null,
              effective_freshness: projection.freshness_at_generation,
              payload
            }, null, 2)
          }
        ]
      };
    }

    if (name === "read_context_material") {
      const materialId = request.params.arguments?.material_id;
      const kind = request.params.arguments?.kind;
      const offset = request.params.arguments?.offset;
      const limit = request.params.arguments?.limit;
      if (typeof materialId !== "string" || materialId.length === 0) {
        throw new Error("read_context_material requires material_id");
      }
      if (kind !== undefined && kind !== "file" && kind !== "note") {
        throw new Error("read_context_material kind must be 'file' or 'note' when provided");
      }
      if (kind === "note") {
        const note = db.readTaskNote(materialId);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                material_kind: "note",
                work_id: note.task_id,
                task_id: note.task_id,
                material_id: note.note_id,
                note_id: note.note_id,
                revision: note.revision,
                binding: note.binding,
                workspace: note.binding.scope_type === "workspace" ? note.binding.scope_key : null,
                title: note.title,
                body: note.body
              }, null, 2)
            }
          ]
        };
      }
      if (kind === "file") {
        const result = db.readTaskFile(
          materialId,
          typeof offset === "number" ? offset : 0,
          typeof limit === "number" ? limit : 8000
        );
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                material_kind: "file",
                material_id: result.file_id,
                ...result
              }, null, 2)
            }
          ]
        };
      }

      try {
        const note = db.readTaskNote(materialId);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                material_kind: "note",
                work_id: note.task_id,
                task_id: note.task_id,
                material_id: note.note_id,
                note_id: note.note_id,
                revision: note.revision,
                binding: note.binding,
                workspace: note.binding.scope_type === "workspace" ? note.binding.scope_key : null,
                title: note.title,
                body: note.body
              }, null, 2)
            }
          ]
        };
      } catch (noteError) {
        try {
          const result = db.readTaskFile(
            materialId,
            typeof offset === "number" ? offset : 0,
            typeof limit === "number" ? limit : 8000
          );
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  material_kind: "file",
                  material_id: result.file_id,
                  ...result
                }, null, 2)
              }
            ]
          };
        } catch (fileError) {
          throw new Error(`Readable context material '${materialId}' not found in active Nexus work. Note read failed: ${String((noteError as Error)?.message ?? noteError)}. File read failed: ${String((fileError as Error)?.message ?? fileError)}`);
        }
      }
    }

    if (name === "read_task_note") {
      const noteId = request.params.arguments?.note_id;
      if (typeof noteId !== "string" || noteId.length === 0) {
        throw new Error("read_task_note requires note_id");
      }
      const note = db.readTaskNote(noteId);
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              work_id: note.task_id,
              task_id: note.task_id,
              note_id: note.note_id,
              revision: note.revision,
              binding: note.binding,
              workspace: note.binding.scope_type === "workspace" ? note.binding.scope_key : null,
              title: note.title,
              body: note.body
            }, null, 2)
          }
        ]
      };
    }

    if (name === "read_task_file") {
      const fileId = request.params.arguments?.file_id;
      const offset = request.params.arguments?.offset;
      const limit = request.params.arguments?.limit;
      if (typeof fileId !== "string" || fileId.length === 0) {
        throw new Error("read_task_file requires file_id");
      }
      const result = db.readTaskFile(
        fileId,
        typeof offset === "number" ? offset : 0,
        typeof limit === "number" ? limit : 8000
      );
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(result, null, 2)
          }
        ]
      };
    }

    throw new Error(`Unknown tool: ${name}`);
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
}
