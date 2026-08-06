import type { CurrentDevelopmentContext } from "./sqlite/ProjectionDatabase.js";

export const currentContextCharacterBudget = 24_000;

export type JsonRecord = Record<string, unknown>;

export type ContextWarning = {
  code: string;
  severity: "info" | "warning";
  message: string;
};

export function objectArray(value: unknown): JsonRecord[] {
  return Array.isArray(value)
    ? value.filter((item): item is JsonRecord => isRecord(item))
    : [];
}

export function stringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function buildCurrentContextPayload(
  context: CurrentDevelopmentContext,
  warnings: ContextWarning[]
): JsonRecord {
  const manifest = context.manifest;
  const brief = context.resume_brief;
  const task = isRecord(manifest.task) ? manifest.task : context.current_task;
  const contextPack = isRecord(manifest.context_pack) ? manifest.context_pack : undefined;
  const contextPackId = nullableString(
    brief.context_pack_id ?? context.current_task.context_pack_id ?? contextPack?.id
  );
  const contextRevision = numberValue(
    brief.context_revision ?? context.current_task.context_revision ?? contextPack?.revision
  );
  const sourceIndex = objectArray(manifest.source_index ?? brief.source_index);
  const repository = compactRepository(
    isRecord(brief.repository) ? brief.repository : manifest.repository
  );
  const files = objectArray(manifest.files).map(normalizeFileMaterial);
  const notes = objectArray(manifest.notes).map(normalizeNoteMaterial);
  const hiddenCount = objectArray(manifest.hidden_files).length;
  const workspaceActivity = compactWorkspaceActivity(manifest.workspace_activity, 10, 20);

  const payload: JsonRecord = {
    schema_version: "2.1",
    work_id: context.task_id,
    revision: context.active_revision,
    binding: compactBinding(context.binding),
    workspace: context.workspace,
    context_pack_id: contextPackId,
    context_revision: contextRevision,
    work: {
      id: stringValue(task.id) || context.task_id,
      title: stringValue(task.title),
      goal: stringValue(task.goal),
      status: stringValue(task.status)
    },
    confirmed_context: contextPack
      ? confirmedContext(contextPack, sourceIndex)
      : fallbackContext(brief),
    source_freshness: {
      state: context.effective_freshness,
      stale_reason: nullableString(
        context.stale_reason ?? brief.stale_reason ?? contextPack?.stale_reason
      ),
      last_verified_at: nullableString(
        context.last_verified_at ?? context.current_task.last_verified_at
      ),
      basis: contextPack ? "confirmed_context_sources" : "live_fallback_sources"
    },
    workspace_activity: workspaceActivity,
    repository,
    materials: {
      read_tool: "read_context_material",
      readable: [...notes, ...files],
      hidden_count: hiddenCount
    },
    warnings
  };

  return fitPayloadToBudget(payload);
}

export function serializedContextPayload(payload: JsonRecord): string {
  return JSON.stringify(payload, null, 2);
}

function confirmedContext(contextPack: JsonRecord, sourceIndex: JsonRecord[]): JsonRecord {
  const content = { ...contextPack };
  delete content.id;
  delete content.revision;
  delete content.effective_freshness;
  delete content.stale_reason;
  return {
    kind: "confirmed_pack",
    ...content,
    sources: sourceIndex
  };
}

function fallbackContext(brief: JsonRecord): JsonRecord {
  return {
    kind: "fallback",
    brief: stringValue(brief.brief),
    handoff_note: stringValue(brief.supplement),
    checkpoint: isRecord(brief.checkpoint) ? brief.checkpoint : null,
    sources: []
  };
}

function normalizeFileMaterial(file: JsonRecord): JsonRecord {
  return {
    id: stringValue(file.id),
    kind: "file",
    title: stringValue(file.display_name),
    file_type: stringValue(file.file_type),
    path: nullableString(file.path),
    updated_at: nullableString(file.modified_at)
  };
}

function normalizeNoteMaterial(note: JsonRecord): JsonRecord {
  return {
    id: stringValue(note.id),
    kind: "note",
    title: stringValue(note.title),
    updated_at: nullableString(note.updated_at)
  };
}

function compactBinding(binding: CurrentDevelopmentContext["binding"]): JsonRecord {
  return {
    id: binding.binding_id,
    scope_type: binding.scope_type,
    scope_key: binding.scope_key,
    resolution: binding.resolution,
    state: binding.state
  };
}

function fitPayloadToBudget(payload: JsonRecord): JsonRecord {
  const normalized = normalizeRecord(payload);
  if (serializedContextPayload(normalized).length <= currentContextCharacterBudget) {
    return normalized;
  }

  const context = isRecord(normalized.confirmed_context) ? normalized.confirmed_context : {};
  const materials = isRecord(normalized.materials) ? normalized.materials : {};
  const reduced: JsonRecord = {
    ...normalized,
    confirmed_context: {
      kind: context.kind,
      brief: clampString(context.brief, 4_000),
      objective: clampString(context.objective, 1_500),
      scope_in: limitedArray(context.scope_in, 8),
      scope_out: limitedArray(context.scope_out, 8),
      confirmed_facts: limitedArray(context.confirmed_facts, 12),
      constraints: limitedArray(context.constraints, 10),
      acceptance_criteria: limitedArray(context.acceptance_criteria, 10),
      assumptions: limitedArray(context.assumptions, 6),
      questions: limitedArray(context.questions, 5),
      sources: limitedArray(context.sources, 20)
    },
    materials: {
      read_tool: "read_context_material",
      readable: limitedArray(materials.readable, 20),
      hidden_count: materials.hidden_count,
      total_readable_count: Array.isArray(materials.readable) ? materials.readable.length : 0
    },
    workspace_activity: compactWorkspaceActivity(normalized.workspace_activity, 10, 16),
    output_truncated: true
  };

  if (serializedContextPayload(reduced).length <= currentContextCharacterBudget) {
    return reduced;
  }

  const work = isRecord(normalized.work) ? normalized.work : {};
  const finalPayload: JsonRecord = {
    schema_version: normalized.schema_version,
    work_id: normalized.work_id,
    revision: normalized.revision,
    binding: normalized.binding,
    workspace: normalized.workspace,
    context_pack_id: normalized.context_pack_id,
    context_revision: normalized.context_revision,
    work: {
      id: clampString(work.id, 200),
      title: clampString(work.title, 300),
      goal: clampString(work.goal, 1_000),
      status: clampString(work.status, 100)
    },
    confirmed_context: {
      kind: isRecord(reduced.confirmed_context) ? reduced.confirmed_context.kind : "fallback",
      brief: clampString(context.brief, 2_500),
      objective: clampString(context.objective, 600),
      scope_in: compactClaims(context.scope_in, 4),
      scope_out: compactClaims(context.scope_out, 4),
      confirmed_facts: compactClaims(context.confirmed_facts, 8),
      constraints: compactClaims(context.constraints, 4),
      acceptance_criteria: compactClaims(context.acceptance_criteria, 4),
      assumptions: compactClaims(context.assumptions, 3),
      questions: compactQuestions(context.questions, 5),
      sources: compactSources(context.sources, 6)
    },
    source_freshness: normalized.source_freshness,
    workspace_activity: compactWorkspaceActivity(normalized.workspace_activity, 6, 10),
    repository: compactRepository(normalized.repository),
    materials: {
      read_tool: "read_context_material",
      readable: compactMaterials(materials.readable, 8),
      hidden_count: materials.hidden_count,
      total_readable_count: Array.isArray(materials.readable) ? materials.readable.length : 0
    },
    warnings: limitedArray(normalized.warnings, 8),
    output_truncated: true
  };

  if (serializedContextPayload(finalPayload).length <= currentContextCharacterBudget) {
    return finalPayload;
  }

  return {
    ...finalPayload,
    confirmed_context: {
      kind: isRecord(finalPayload.confirmed_context)
        ? finalPayload.confirmed_context.kind
        : "fallback",
      brief: clampString(context.brief, 2_000),
      confirmed_facts: compactClaims(context.confirmed_facts, 3),
      constraints: compactClaims(context.constraints, 2),
      questions: compactQuestions(context.questions, 3),
      sources: compactSources(context.sources, 4)
    },
    workspace_activity: compactWorkspaceActivity(normalized.workspace_activity, 4, 6),
    materials: {
      read_tool: "read_context_material",
      readable: compactMaterials(materials.readable, 4),
      hidden_count: materials.hidden_count,
      total_readable_count: Array.isArray(materials.readable) ? materials.readable.length : 0
    }
  };
}

function normalizeRecord(value: JsonRecord): JsonRecord {
  return normalizePayload(value) as JsonRecord;
}

function normalizePayload(value: unknown, depth = 0): unknown {
  if (typeof value === "string") {
    return clampString(value, depth <= 2 ? 4_000 : 1_200);
  }
  if (Array.isArray(value)) {
    return value.slice(0, 50).map((item) => normalizePayload(item, depth + 1));
  }
  if (isRecord(value)) {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, normalizePayload(item, depth + 1)])
    );
  }
  return value;
}

function limitedArray(value: unknown, limit: number): unknown[] {
  return Array.isArray(value)
    ? value.slice(0, limit).map((item) => normalizePayload(item, 3))
    : [];
}

function compactClaims(value: unknown, limit: number): JsonRecord[] {
  return objectArray(value).slice(0, limit).map((claim) => ({
    text: clampString(claim.text, 500),
    source_ids: stringArray(claim.source_ids, 6)
  }));
}

function compactQuestions(value: unknown, limit: number): JsonRecord[] {
  return objectArray(value).slice(0, limit).map((question) => ({
    id: clampString(question.id, 120),
    question: clampString(question.question, 500),
    why_it_matters: clampString(question.why_it_matters, 250),
    source_ids: stringArray(question.source_ids, 6)
  }));
}

function compactSources(value: unknown, limit: number): JsonRecord[] {
  return objectArray(value).slice(0, limit).map((source) => ({
    id: clampString(source.id, 160),
    kind: clampString(source.kind, 60),
    title: clampString(source.title, 240),
    path: source.path === null ? null : clampString(source.path, 500),
    truncated: source.truncated === true
  }));
}

function compactMaterials(value: unknown, limit: number): JsonRecord[] {
  return objectArray(value).slice(0, limit).map((material) => ({
    id: clampString(material.id, 160),
    kind: clampString(material.kind, 60),
    title: clampString(material.title, 240),
    file_type: clampString(material.file_type, 80),
    path: material.path === null ? null : clampString(material.path, 500)
  }));
}

function compactRepository(value: unknown): JsonRecord | null {
  if (!isRecord(value)) {
    return null;
  }
  return {
    path: clampString(value.path, 800),
    branch: clampString(value.branch, 240)
  };
}

function compactWorkspaceActivity(
  value: unknown,
  commitLimit: number,
  pathLimit: number
): JsonRecord | null {
  if (!isRecord(value)) {
    return null;
  }
  return {
    state: clampString(value.state, 80),
    workspace: nullableClampedString(value.workspace, 800),
    linked_branch: nullableClampedString(value.linked_branch, 240),
    current_branch: nullableClampedString(value.current_branch, 240),
    baseline_head: nullableClampedString(value.baseline_head, 80),
    current_head: nullableClampedString(value.current_head, 80),
    commit_count: numberValue(value.commit_count) ?? objectArray(value.commits).length,
    changed_path_count:
      numberValue(value.changed_path_count) ?? objectArray(value.committed_paths).length,
    dirty_path_count:
      numberValue(value.dirty_path_count) ?? objectArray(value.uncommitted_paths).length,
    commits: objectArray(value.commits).slice(0, commitLimit).map((commit) => ({
      sha: clampString(commit.sha, 80),
      subject: clampString(commit.subject, 300),
      committed_at: nullableClampedString(commit.committed_at, 80)
    })),
    committed_paths: objectArray(value.committed_paths)
      .slice(0, pathLimit)
      .map(compactChangedPath),
    uncommitted_paths: objectArray(value.uncommitted_paths)
      .slice(0, pathLimit)
      .map(compactChangedPath),
    provenance: stringValue(value.provenance) || "derived_from_git",
    captured_at: nullableClampedString(value.captured_at, 80)
  };
}

function compactChangedPath(value: JsonRecord): JsonRecord {
  return {
    status: clampString(value.status, 20),
    path: clampString(value.path, 600),
    previous_path: nullableClampedString(value.previous_path, 600),
    additions: numberValue(value.additions),
    deletions: numberValue(value.deletions),
    is_binary: value.is_binary === true
  };
}

function stringArray(value: unknown, limit: number): string[] {
  return Array.isArray(value)
    ? value
      .filter((item): item is string => typeof item === "string")
      .slice(0, limit)
      .map((item) => clampString(item, 160))
    : [];
}

function clampString(value: unknown, limit: number): string {
  const text = typeof value === "string" ? value : "";
  if (text.length <= limit) {
    return text;
  }
  return `${text.slice(0, Math.max(0, limit - 24))}\n[… output shortened …]`;
}

function nullableString(value: unknown): string | null {
  const text = stringValue(value);
  return text.length > 0 ? text : null;
}

function nullableClampedString(value: unknown, limit: number): string | null {
  const text = nullableString(value);
  return text === null ? null : clampString(text, limit);
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
