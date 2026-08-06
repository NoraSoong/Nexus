import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { join, resolve, sep } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { readSupportedTextFile } from "../textFilePolicy.js";

const runtimeStaleMs = 15_000;
const supportedProjectionSchemaVersions = new Set(["1", "2"]);

export type ActiveProjection = {
  task_id: string;
  active_revision: number;
  binding: ResolvedContextBinding;
  payload_json: string;
  freshness_at_generation: string;
  last_verified_at: string | null;
  stale_reason: string | null;
};

export type NoteExport = {
  task_id: string;
  note_id: string;
  revision: number;
  title: string;
  body: string;
  binding: ResolvedContextBinding;
};

export type FileExport = {
  task_id: string;
  file_id: string;
  revision: number;
  display_name: string;
  path: string;
  file_type: string;
};

export type CurrentDevelopmentContext = {
  task_id: string;
  active_revision: number;
  binding: ResolvedContextBinding;
  workspace: string | null;
  effective_freshness: string;
  last_verified_at: string | null;
  stale_reason: string | null;
  current_task: Record<string, unknown>;
  resume_brief: Record<string, unknown>;
  manifest: Record<string, unknown>;
};

export type BindingSelection = {
  bindingId?: number;
  workspacePath?: string;
};

export type ResolvedContextBinding = {
  binding_id: number;
  scope_type: string;
  scope_key: string;
  mode: string;
  task_id: string;
  active_revision: number;
  state: "attached" | "pinned_snapshot";
  resolution: "explicit_binding" | "workspace" | "global_default";
};

type BindingRow = {
  id: number;
  scope_type: string;
  scope_key: string;
  mode: string;
  task_id?: string;
  active_revision?: number;
  updated_at?: string;
};

type PinnedBinding = {
  bindingId: number;
  taskId: string;
  scopeType: string;
  scopeKey: string;
  mode: string;
  activeRevision: number;
  resolution: ResolvedContextBinding["resolution"];
};

type AppRuntimeStatus = {
  active: boolean;
  required: boolean;
  runtimePath: string;
  reason?: string;
  state?: string;
  exposureEnabled?: boolean;
  appPid?: number;
  lastSeenAt?: string;
  ageMs?: number;
};

export class ProjectionDatabase {
  private readonly homePath: string;
  private readonly dbPath: string;
  private readonly runtimePath: string;
  private readonly allowHeadless: boolean;
  private readonly requestedBindingId: number | undefined;
  private readonly explicitWorkspacePath: string | undefined;
  private readonly workspaceCandidates: string[];
  private pinnedBinding: PinnedBinding | undefined;

  constructor(nexusHome = process.env.NEXUS_HOME, selection: BindingSelection = {}) {
    const home = nexusHome && nexusHome.length > 0
      ? nexusHome
      : join(process.env.HOME ?? "", "Library", "Application Support", "Nexus");
    this.homePath = home;
    this.dbPath = join(home, "Nexus.sqlite");
    this.runtimePath = join(home, "Nexus.runtime.json");
    this.allowHeadless = process.env.NEXUS_MCP_ALLOW_HEADLESS === "1";
    this.requestedBindingId = selection.bindingId ?? parseBindingId(process.env.NEXUS_CONTEXT_BINDING_ID);
    this.explicitWorkspacePath = normalizeOptionalPath(selection.workspacePath ?? process.env.NEXUS_WORKSPACE);
    this.workspaceCandidates = uniquePaths([
      this.explicitWorkspacePath,
      process.env.CLAUDE_PROJECT_DIR,
      process.env.CODEX_PROJECT_DIR,
      process.cwd()
    ]);
  }

  prepareBinding(): void {
    if (!existsSync(this.dbPath)) {
      return;
    }
    const db = new DatabaseSync(this.dbPath, { open: true, readOnly: true });
    try {
      db.exec("PRAGMA busy_timeout=2000;");
      this.currentBinding(db);
    } finally {
      db.close();
    }
  }

  doctor(): Record<string, unknown> {
    const appRuntime = this.appRuntimeStatus();
    const base: Record<string, unknown> = {
      homePath: this.homePath,
      dbPath: this.dbPath,
      runtimePath: this.runtimePath,
      dbExists: existsSync(this.dbPath),
      appRuntime,
      node: process.version,
      sqliteAdapter: "node:sqlite"
    };
    if (!existsSync(this.dbPath)) {
      return {
        ...base,
        currentContextReady: false,
        reason: "database_not_found"
      };
    }

    let db: DatabaseSync | undefined;
    try {
      db = new DatabaseSync(this.dbPath, { open: true, readOnly: true });
      db.exec("PRAGMA busy_timeout=2000;");
      const schema = db.prepare("SELECT value FROM metadata WHERE key = 'projection_schema_version';").get() as { value?: string } | undefined;
      let binding: ResolvedContextBinding | null = null;
      let bindingError: string | null = null;
      try {
        binding = this.currentBinding(db);
      } catch (error) {
        bindingError = error instanceof Error ? error.message : String(error);
      }
      let activeTitle: string | null = null;
      if (binding) {
        const projection = db.prepare(
          `SELECT payload_json
           FROM mcp_context_projections
           WHERE task_id = ? AND revision = ? AND projection_type = 'active_task';`
        ).get(binding.task_id, binding.active_revision) as { payload_json?: string } | undefined;
        if (projection?.payload_json) {
          const payload = JSON.parse(projection.payload_json) as { title?: unknown };
          activeTitle = typeof payload.title === "string" ? payload.title : null;
        }
      }
      return {
        ...base,
        projectionSchemaVersion: schema?.value ?? null,
        activeBinding: binding ?? null,
        bindingError,
        workspaceCandidates: this.workspaceCandidates,
        activeTitle,
        currentContextReady: appRuntime.active && supportedProjectionSchemaVersions.has(schema?.value ?? "") && binding !== null
      };
    } catch (error) {
      return {
        ...base,
        currentContextReady: false,
        reason: "doctor_failed",
        error: error instanceof Error ? error.message : String(error)
      };
    } finally {
      db?.close();
    }
  }

  isAppRuntimeActive(): boolean {
    return this.appRuntimeStatus().active;
  }

  appRuntimeStatus(): AppRuntimeStatus {
    return this.getAppRuntimeStatus();
  }

  getActiveProjection(type = "active_task"): ActiveProjection {
    this.assertAppRuntimeActive();
    if (!existsSync(this.dbPath)) {
      throw new Error(`Nexus database not found at ${this.dbPath}`);
    }

    const db = new DatabaseSync(this.dbPath, {
      open: true,
      readOnly: true
    });
    try {
      db.exec("PRAGMA busy_timeout=2000;");
      const version = db.prepare("SELECT value FROM metadata WHERE key = 'projection_schema_version';").get() as { value?: string } | undefined;
      if (!supportedProjectionSchemaVersions.has(version?.value ?? "")) {
        throw new Error(`Unsupported projection schema version: ${version?.value ?? "missing"}`);
      }

      const binding = this.currentBinding(db);

      const projection = db.prepare(
        `SELECT payload_json, freshness_at_generation, last_verified_at, stale_reason
         FROM mcp_context_projections
         WHERE task_id = ? AND revision = ? AND projection_type = ?;`
      ).get(binding.task_id, binding.active_revision, type) as Omit<ActiveProjection, "task_id" | "active_revision"> | undefined;

      if (!projection) {
        throw new Error(`Projection '${type}' not found for ${binding.task_id} revision ${binding.active_revision}`);
      }

      return {
        task_id: binding.task_id,
        active_revision: binding.active_revision,
        binding,
        payload_json: projection.payload_json,
        freshness_at_generation: projection.freshness_at_generation,
        last_verified_at: projection.last_verified_at,
        stale_reason: projection.stale_reason
      };
    } finally {
      db.close();
    }
  }

  getCurrentDevelopmentContext(): CurrentDevelopmentContext {
    this.assertAppRuntimeActive();
    if (!existsSync(this.dbPath)) {
      throw new Error(`Nexus database not found at ${this.dbPath}`);
    }

    const db = new DatabaseSync(this.dbPath, {
      open: true,
      readOnly: true
    });
    try {
      db.exec("PRAGMA busy_timeout=2000;");
      const version = db.prepare("SELECT value FROM metadata WHERE key = 'projection_schema_version';").get() as { value?: string } | undefined;
      if (!supportedProjectionSchemaVersions.has(version?.value ?? "")) {
        throw new Error(`Unsupported projection schema version: ${version?.value ?? "missing"}`);
      }

      const binding = this.currentBinding(db);

      const rows = db.prepare(
        `SELECT projection_type, payload_json, freshness_at_generation, last_verified_at, stale_reason
         FROM mcp_context_projections
         WHERE task_id = ? AND revision = ? AND projection_type IN ('active_task', 'manifest', 'resume_brief');`
      ).all(binding.task_id, binding.active_revision) as Array<{
        projection_type?: string;
        payload_json?: string;
        freshness_at_generation?: string;
        last_verified_at?: string | null;
        stale_reason?: string | null;
      }>;

      const byType = new Map<string, {
        payload_json: string;
        freshness_at_generation: string;
        last_verified_at: string | null;
        stale_reason: string | null;
      }>();
      for (const row of rows) {
        if (row.projection_type && row.payload_json) {
          byType.set(row.projection_type, {
            payload_json: row.payload_json,
            freshness_at_generation: row.freshness_at_generation ?? "possibly_stale",
            last_verified_at: row.last_verified_at ?? null,
            stale_reason: row.stale_reason ?? null
          });
        }
      }

      const active = byType.get("active_task");
      const manifest = byType.get("manifest");
      const brief = byType.get("resume_brief");
      if (!active || !manifest || !brief) {
        throw new Error(`Current development context is incomplete for ${binding.task_id} revision ${binding.active_revision}`);
      }

      return {
        task_id: binding.task_id,
        active_revision: binding.active_revision,
        binding,
        workspace: binding.scope_type === "workspace" ? binding.scope_key : null,
        effective_freshness: active.freshness_at_generation,
        last_verified_at: active.last_verified_at,
        stale_reason: active.stale_reason,
        current_task: JSON.parse(active.payload_json) as Record<string, unknown>,
        resume_brief: JSON.parse(brief.payload_json) as Record<string, unknown>,
        manifest: JSON.parse(manifest.payload_json) as Record<string, unknown>
      };
    } finally {
      db.close();
    }
  }

  readTaskNote(noteId: string): NoteExport {
    this.assertAppRuntimeActive();
    if (!existsSync(this.dbPath)) {
      throw new Error(`Nexus database not found at ${this.dbPath}`);
    }

    const db = new DatabaseSync(this.dbPath, { open: true, readOnly: true });
    try {
      db.exec("PRAGMA busy_timeout=2000;");
      const binding = this.currentBinding(db);

      const note = db.prepare(
        `SELECT task_id, note_id, revision, title, body
         FROM mcp_note_exports
         WHERE task_id = ? AND revision = ? AND note_id = ?;`
      ).get(binding.task_id, binding.active_revision, noteId) as Omit<NoteExport, "binding"> | undefined;

      if (!note) {
        throw new Error(`Readable note '${noteId}' not found for bound work ${binding.task_id}`);
      }
      return { ...note, binding };
    } finally {
      db.close();
    }
  }

  readTaskFile(fileId: string, offset = 0, limit = 8000): Record<string, unknown> {
    this.assertAppRuntimeActive();
    if (!existsSync(this.dbPath)) {
      throw new Error(`Nexus database not found at ${this.dbPath}`);
    }
    const clampedOffset = Math.max(0, Math.floor(offset));
    const clampedLimit = Math.max(1, Math.min(Math.floor(limit), 16000));
    const db = new DatabaseSync(this.dbPath, { open: true, readOnly: true });
    try {
      db.exec("PRAGMA busy_timeout=2000;");
      const binding = this.currentBinding(db);
      const file = db.prepare(
        `SELECT task_id, file_id, revision, display_name, path, file_type
         FROM mcp_file_exports
         WHERE task_id = ? AND revision = ? AND file_id = ?;`
      ).get(binding.task_id, binding.active_revision, fileId) as FileExport | undefined;
      if (!file) {
        throw new Error(`Readable file '${fileId}' not found for bound work ${binding.task_id}`);
      }
      if (!existsSync(file.path)) {
        throw new Error(`File no longer exists: ${file.path}`);
      }
      const stat = statSync(file.path);
      if (!stat.isFile()) {
        throw new Error(`Path is not a regular file: ${file.path}`);
      }
      const body = readSupportedTextFile(file.path);
      const chunk = body.slice(clampedOffset, clampedOffset + clampedLimit);
      const nextOffset = clampedOffset + chunk.length < body.length
        ? clampedOffset + chunk.length
        : null;
      return {
        work_id: file.task_id,
        task_id: file.task_id,
        file_id: file.file_id,
        revision: file.revision,
        display_name: file.display_name,
        path: file.path,
        file_type: file.file_type,
        binding,
        offset: clampedOffset,
        limit: clampedLimit,
        next_cursor: nextOffset === null ? null : {
          task_id: file.task_id,
          file_id: file.file_id,
          revision: file.revision,
          offset: nextOffset
        },
        body: chunk
      };
    } finally {
      db.close();
    }
  }

  private currentBinding(db: DatabaseSync): ResolvedContextBinding {
    if (!this.pinnedBinding) {
      this.pinnedBinding = this.resolveInitialBinding(db);
    }

    const row = db.prepare(
      `SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
       FROM context_bindings
       WHERE id = ?;`
    ).get(this.pinnedBinding.bindingId) as BindingRow | undefined;
    if (!row) {
      if (this.pinnedBinding.resolution === "global_default") {
        return this.detachedGlobalBinding(db);
      }
      throw new Error(
        `Nexus context binding ${this.pinnedBinding.bindingId} no longer exists. Reopen or reconfigure this assistant session instead of falling back to another work.`
      );
    }
    if (!row.task_id || row.active_revision === undefined) {
      throw new Error(`Nexus context binding ${row.id} is incomplete`);
    }
    if (row.task_id !== this.pinnedBinding.taskId) {
      if (this.pinnedBinding.resolution === "global_default") {
        return this.detachedGlobalBinding(db);
      }
      throw new Error(
        `Nexus context binding ${row.id} was reassigned from work ${this.pinnedBinding.taskId} to ${row.task_id}. Reopen or reconfigure this assistant session.`
      );
    }
    if (row.mode !== "pinned_task") {
      throw new Error(`Unsupported Nexus context binding mode '${row.mode}' for binding ${row.id}`);
    }
    return {
      binding_id: row.id,
      scope_type: row.scope_type,
      scope_key: row.scope_key,
      mode: row.mode,
      task_id: row.task_id,
      active_revision: row.active_revision,
      state: "attached",
      resolution: this.pinnedBinding.resolution
    };
  }

  private detachedGlobalBinding(db: DatabaseSync): ResolvedContextBinding {
    const task = db.prepare(
      "SELECT archived_at FROM tasks WHERE id = ?;"
    ).get(this.pinnedBinding!.taskId) as { archived_at?: string | null } | undefined;
    if (!task || task.archived_at) {
      throw new Error(
        `Nexus work ${this.pinnedBinding!.taskId} bound when this helper started is no longer available. Reopen the assistant session.`
      );
    }
    const currentTaskBinding = db.prepare(
      `SELECT active_revision
       FROM context_bindings
       WHERE task_id = ?
       ORDER BY CASE WHEN scope_type = 'workspace' THEN 0 ELSE 1 END, updated_at DESC
       LIMIT 1;`
    ).get(this.pinnedBinding!.taskId) as { active_revision?: number } | undefined;
    const revision = currentTaskBinding?.active_revision ?? this.pinnedBinding!.activeRevision;
    return {
      binding_id: this.pinnedBinding!.bindingId,
      scope_type: this.pinnedBinding!.scopeType,
      scope_key: this.pinnedBinding!.scopeKey,
      mode: this.pinnedBinding!.mode,
      task_id: this.pinnedBinding!.taskId,
      active_revision: revision,
      state: "pinned_snapshot",
      resolution: this.pinnedBinding!.resolution
    };
  }

  private resolveInitialBinding(db: DatabaseSync): PinnedBinding {
    if (this.requestedBindingId !== undefined) {
      const row = this.bindingById(db, this.requestedBindingId);
      if (!row) {
        throw new Error(`Requested Nexus context binding ${this.requestedBindingId} was not found`);
      }
      return this.pin(row, "explicit_binding");
    }

    const workspaceRows = db.prepare(
      `SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
       FROM context_bindings
       WHERE scope_type = 'workspace';`
    ).all() as BindingRow[];
    for (const candidate of this.workspaceCandidates) {
      const row = bestWorkspaceMatch(candidate, workspaceRows);
      if (row) {
        return this.pin(row, "workspace");
      }
      if (candidate === this.explicitWorkspacePath) {
        throw new Error(`No Nexus workspace binding matches ${candidate}`);
      }
    }

    const global = db.prepare(
      `SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
       FROM context_bindings
       WHERE scope_type = 'global' AND scope_key = 'default';`
    ).get() as BindingRow | undefined;
    if (!global) {
      throw new Error("No Nexus context binding matches this workspace and no global default is available");
    }
    return this.pin(global, "global_default");
  }

  private bindingById(db: DatabaseSync, bindingId: number): BindingRow | undefined {
    return db.prepare(
      `SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
       FROM context_bindings
       WHERE id = ?;`
    ).get(bindingId) as BindingRow | undefined;
  }

  private pin(row: BindingRow, resolution: ResolvedContextBinding["resolution"]): PinnedBinding {
    if (!row.task_id || row.active_revision === undefined) {
      throw new Error(`Nexus context binding ${row.id} is incomplete`);
    }
    if (row.mode !== "pinned_task") {
      throw new Error(`Unsupported Nexus context binding mode '${row.mode}' for binding ${row.id}`);
    }
    return {
      bindingId: row.id,
      taskId: row.task_id,
      scopeType: row.scope_type,
      scopeKey: row.scope_key,
      mode: row.mode,
      activeRevision: row.active_revision,
      resolution
    };
  }

  private assertAppRuntimeActive(): void {
    const status = this.getAppRuntimeStatus();
    if (status.active) {
      return;
    }
    throw new Error(`Nexus context is unavailable (${status.reason ?? "unknown"}). Open Nexus from the menu bar and enable assistant access before using Nexus MCP context.`);
  }

  private getAppRuntimeStatus(): AppRuntimeStatus {
    if (this.allowHeadless) {
      return {
        active: true,
        required: false,
        runtimePath: this.runtimePath,
        reason: "headless_allowed_for_tests"
      };
    }
    if (!existsSync(this.runtimePath)) {
      return {
        active: false,
        required: true,
        runtimePath: this.runtimePath,
        reason: "runtime_status_missing"
      };
    }
    try {
      const raw = readFileSync(this.runtimePath, "utf8");
      const payload = JSON.parse(raw) as {
        state?: unknown;
        exposure_enabled?: unknown;
        app_pid?: unknown;
        last_seen_at?: unknown;
      };
      const state = typeof payload.state === "string" ? payload.state : "unknown";
      const exposureEnabled = typeof payload.exposure_enabled === "boolean" ? payload.exposure_enabled : state === "running";
      const appPid = typeof payload.app_pid === "number" ? payload.app_pid : undefined;
      const lastSeenAt = typeof payload.last_seen_at === "string" ? payload.last_seen_at : undefined;
      const lastSeenMs = lastSeenAt ? Date.parse(lastSeenAt) : Number.NaN;
      const ageMs = Number.isFinite(lastSeenMs) ? Date.now() - lastSeenMs : undefined;
      if (state !== "running") {
        return {
          active: false,
          required: true,
          runtimePath: this.runtimePath,
          reason: state === "paused" ? "assistant_access_paused" : "app_not_running",
          state,
          exposureEnabled,
          appPid,
          lastSeenAt,
          ageMs
        };
      }
      if (ageMs === undefined || ageMs > runtimeStaleMs) {
        return {
          active: false,
          required: true,
          runtimePath: this.runtimePath,
          reason: "heartbeat_stale",
          state,
          exposureEnabled,
          appPid,
          lastSeenAt,
          ageMs
        };
      }
      if (!this.isProcessAlive(appPid)) {
        return {
          active: false,
          required: true,
          runtimePath: this.runtimePath,
          reason: "app_process_not_alive",
          state,
          exposureEnabled,
          appPid,
          lastSeenAt,
          ageMs
        };
      }
      return {
        active: true,
        required: true,
        runtimePath: this.runtimePath,
        state,
        exposureEnabled,
        appPid,
        lastSeenAt,
        ageMs
      };
    } catch (error) {
      return {
        active: false,
        required: true,
        runtimePath: this.runtimePath,
        reason: `runtime_status_unreadable: ${error instanceof Error ? error.message : String(error)}`
      };
    }
  }

  private isProcessAlive(pid: number | undefined): boolean {
    if (!pid || !Number.isInteger(pid) || pid <= 0) {
      return false;
    }
    try {
      process.kill(pid, 0);
      return true;
    } catch (error) {
      return (error as NodeJS.ErrnoException).code === "EPERM";
    }
  }
}

function parseBindingId(value: string | undefined): number | undefined {
  if (!value) {
    return undefined;
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`Invalid NEXUS_CONTEXT_BINDING_ID '${value}'`);
  }
  return parsed;
}

function normalizeOptionalPath(value: string | undefined): string | undefined {
  if (!value || value.trim().length === 0) {
    return undefined;
  }
  const absolute = resolve(value);
  try {
    return realpathSync.native(absolute);
  } catch {
    return absolute;
  }
}

function uniquePaths(values: Array<string | undefined>): string[] {
  return Array.from(new Set(values.map(normalizeOptionalPath).filter((value): value is string => Boolean(value))));
}

function bestWorkspaceMatch(candidate: string, rows: BindingRow[]): BindingRow | undefined {
  const normalizedCandidate = normalizeOptionalPath(candidate);
  if (!normalizedCandidate) {
    return undefined;
  }
  return rows
    .filter((row) => {
      const workspace = normalizeOptionalPath(row.scope_key);
      return workspace !== undefined
        && (normalizedCandidate === workspace || normalizedCandidate.startsWith(`${workspace}${sep}`));
    })
    .sort((lhs, rhs) => rhs.scope_key.length - lhs.scope_key.length)[0];
}
