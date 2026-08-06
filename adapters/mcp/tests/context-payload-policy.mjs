import {
  buildCurrentContextPayload,
  currentContextCharacterBudget,
  serializedContextPayload
} from "../dist/contextPayload.js";

const longText = "context ".repeat(900);
const claims = Array.from({ length: 80 }, (_, index) => ({
  text: `${index}: ${longText}`,
  source_ids: [`source-${index}`]
}));
const sources = Array.from({ length: 80 }, (_, index) => ({
  id: `source-${index}`,
  kind: "file",
  title: `Source ${index}`,
  path: `/tmp/source-${index}.md`,
  updated_at: "2026-07-30T00:00:00Z",
  content_hash: `${index}`.padStart(64, "0"),
  truncated: false
}));

const payload = buildCurrentContextPayload({
  task_id: "work-1",
  active_revision: 7,
  binding: {
    binding_id: 1,
    scope_type: "workspace",
    scope_key: "/tmp/worktree",
    mode: "follow",
    task_id: "work-1",
    active_revision: 7,
    state: "attached",
    resolution: "workspace"
  },
  workspace: "/tmp/worktree",
  effective_freshness: "fresh",
  current_task: {
    task_id: "work-1",
    title: "Large Context",
    goal: "Exercise the compact context budget.",
    status: "active",
    context_pack_id: "pack-1",
    context_revision: 7
  },
  resume_brief: {
    brief: longText,
    context_pack_id: "pack-1",
    context_revision: 7,
    source_index: sources
  },
  manifest: {
    task: {
      id: "work-1",
      title: "Large Context",
      goal: "Exercise the compact context budget.",
      status: "active"
    },
    context_pack: {
      id: "pack-1",
      revision: 7,
      brief: longText,
      objective: longText,
      scope_in: claims,
      scope_out: claims,
      confirmed_facts: claims,
      constraints: claims,
      acceptance_criteria: claims,
      assumptions: claims,
      questions: claims.map((claim, index) => ({
        id: `question-${index}`,
        question: claim.text,
        why_it_matters: longText,
        source_ids: claim.source_ids
      }))
    },
    workspace_activity: {
      state: "commits_available",
      workspace: "/tmp/worktree",
      linked_branch: "feature/context",
      current_branch: "feature/context",
      baseline_head: "base",
      current_head: "head",
      commit_count: 40,
      changed_path_count: 80,
      dirty_path_count: 30,
      commits: Array.from({ length: 40 }, (_, index) => ({
        sha: `sha-${index}`,
        subject: `${index}: ${longText}`,
        committed_at: "2026-07-30T00:00:00Z"
      })),
      committed_paths: Array.from({ length: 80 }, (_, index) => ({
        status: "M",
        path: `Sources/Committed${index}.swift`,
        additions: index,
        deletions: 0,
        is_binary: false
      })),
      uncommitted_paths: Array.from({ length: 30 }, (_, index) => ({
        status: "M",
        path: `Sources/Pending${index}.swift`,
        is_binary: false
      })),
      committed_diff: longText,
      uncommitted_diff: longText,
      provenance: "derived_from_git",
      captured_at: "2026-07-30T00:00:00Z"
    },
    source_index: sources,
    files: sources.map((source) => ({
      id: source.id,
      display_name: source.title,
      path: source.path,
      file_type: "Markdown",
      modified_at: source.updated_at
    })),
    hidden_files: [],
    notes: []
  }
}, []);

const serialized = serializedContextPayload(payload);
if (serialized.length > currentContextCharacterBudget) {
  throw new Error(
    `Compact context exceeded ${currentContextCharacterBudget} characters: ${serialized.length}`
  );
}
if (payload.output_truncated !== true) {
  throw new Error("Oversized context did not report output_truncated");
}
if ("active_context" in payload || "compatibility" in payload) {
  throw new Error("Compact context includes duplicate legacy wrappers");
}
if ("context" in payload || "effective_freshness" in payload) {
  throw new Error("Compact context includes superseded top-level context fields");
}
if (!Array.isArray(payload.confirmed_context?.confirmed_facts) || payload.confirmed_context.confirmed_facts.length === 0) {
  throw new Error("Budget reduction dropped every confirmed fact");
}
if (!Array.isArray(payload.confirmed_context?.constraints) || payload.confirmed_context.constraints.length === 0) {
  throw new Error("Budget reduction dropped every constraint");
}
if (payload.source_freshness?.state !== "fresh") {
  throw new Error("Compact context did not preserve source freshness");
}
if (!payload.workspace_activity || payload.workspace_activity.provenance !== "derived_from_git") {
  throw new Error("Compact context did not preserve workspace activity provenance");
}
if (payload.workspace_activity.commits.length > 10) {
  throw new Error("Workspace activity exceeded the commit limit");
}
if (payload.workspace_activity.committed_paths.length > 20) {
  throw new Error("Workspace activity exceeded the changed path limit");
}
if (JSON.stringify(payload.workspace_activity).includes("committed_diff")) {
  throw new Error("Workspace activity exposed diff bodies");
}

console.log(JSON.stringify({
  ok: true,
  characters: serialized.length,
  budget: currentContextCharacterBudget
}, null, 2));
