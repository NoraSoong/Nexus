import { buildCurrentContextPayload } from "../dist/contextPayload.js";

const payload = buildCurrentContextPayload({
  task_id: "work-1",
  active_revision: 3,
  binding: {
    binding_id: 1,
    scope_type: "global",
    scope_key: "default",
    mode: "follow",
    task_id: "work-1",
    active_revision: 3,
    state: "attached",
    resolution: "global"
  },
  workspace: null,
  effective_freshness: "fresh",
  current_task: {
    task_id: "work-1",
    title: "服务站行李暂存",
    goal: "整理当前上下文",
    status: "active",
    context_pack_id: "pack-1",
    context_revision: 3
  },
  resume_brief: {
    brief: "旧摘要（S3）",
    context_pack_id: "pack-1",
    context_revision: 3
  },
  manifest: {
    task: {
      id: "work-1",
      title: "服务站行李暂存",
      goal: "整理当前上下文",
      status: "active"
    },
    context_pack: {
      id: "pack-1",
      revision: 3,
      brief: "本需求基于 PRD 文档（S3）。代码变更证据（S4）仅供参考。",
      objective: "使用 AWS S3 存储",
      scope_in: [{ text: "支持入库", source_ids: ["S3"] }],
      scope_out: [],
      confirmed_facts: [],
      constraints: [],
      acceptance_criteria: [],
      assumptions: [],
      questions: []
    },
    source_index: [],
    files: [],
    hidden_files: [],
    notes: []
  }
}, []);

const confirmed = payload.confirmed_context;
if (confirmed.brief !== "本需求基于 PRD 文档。代码变更证据仅供参考。") {
  throw new Error(`Generated brief was not sanitized: ${confirmed.brief}`);
}
if (confirmed.objective !== "使用 AWS S3 存储") {
  throw new Error(`Technical S3 name was damaged: ${confirmed.objective}`);
}
if (confirmed.scope_in?.[0]?.text !== "支持入库") {
  throw new Error(`Generated claim was not sanitized: ${confirmed.scope_in?.[0]?.text}`);
}

console.log(JSON.stringify({ ok: true }));
