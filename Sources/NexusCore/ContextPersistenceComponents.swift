import Foundation

enum ContextJSONCodec {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }
}

enum ContextPackPersistence {
    static func insertDraft(_ draft: ContextDraft, into db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO context_drafts (
                id, task_id, base_revision, provider, model, payload_json,
                source_manifest_json, answers_json, status, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                draft.id, draft.taskID, String(draft.baseRevision), draft.provider, draft.model,
                try ContextJSONCodec.encode(draft.content),
                try ContextJSONCodec.encode(draft.sourceManifest),
                try ContextJSONCodec.encode(draft.answers), draft.status, draft.createdAt,
                draft.updatedAt,
            ]
        )
    }

    static func latestDraft(taskID: String, in db: SQLiteDatabase) throws -> ContextDraft? {
        try db.queryOne(
            """
            SELECT id, task_id, base_revision, provider, model, payload_json,
                   source_manifest_json, answers_json, status, created_at, updated_at
            FROM context_drafts
            WHERE task_id = ? AND status = 'pending'
            ORDER BY updated_at DESC
            LIMIT 1;
            """,
            bindings: [taskID]
        ).map(decodeDraft)
    }

    static func pendingDraft(id: String, in db: SQLiteDatabase) throws -> ContextDraft? {
        try db.queryOne(
            """
            SELECT id, task_id, base_revision, provider, model, payload_json,
                   source_manifest_json, answers_json, status, created_at, updated_at
            FROM context_drafts
            WHERE id = ? AND status = 'pending';
            """,
            bindings: [id]
        ).map(decodeDraft)
    }

    static func updateDraft(
        id: String,
        content: ContextPackContent,
        answers: [String: String],
        updatedAt: String,
        in db: SQLiteDatabase
    ) throws {
        try db.execute(
            """
            UPDATE context_drafts
            SET payload_json = ?, answers_json = ?, updated_at = ?
            WHERE id = ? AND status = 'pending';
            """,
            bindings: [
                try ContextJSONCodec.encode(content), try ContextJSONCodec.encode(answers), updatedAt,
                id,
            ]
        )
    }

    static func markDraft(id: String, status: String, updatedAt: String, in db: SQLiteDatabase) throws {
        try db.execute(
            "UPDATE context_drafts SET status = ?, updated_at = ? WHERE id = ?;",
            bindings: [status, updatedAt, id]
        )
    }

    static func currentPack(taskID: String, in db: SQLiteDatabase) throws -> ContextPack? {
        try db.queryOne(
            """
            SELECT p.id, p.task_id, p.revision, p.payload_json, p.source_manifest_json,
                   p.freshness, p.stale_reason, p.created_at
            FROM task_context_state s
            JOIN context_packs p ON p.id = s.current_pack_id
            WHERE s.task_id = ?;
            """,
            bindings: [taskID]
        ).map(decodePack)
    }

    static func history(taskID: String, limit: Int, in db: SQLiteDatabase) throws -> [ContextPack] {
        try db.queryAll(
            """
            SELECT id, task_id, revision, payload_json, source_manifest_json,
                   freshness, stale_reason, created_at
            FROM context_packs
            WHERE task_id = ?
            ORDER BY revision DESC
            LIMIT ?;
            """,
            bindings: [taskID, String(limit)]
        ).map(decodePack)
    }

    static func previousPack(
        taskID: String,
        beforeRevision: Int64,
        in db: SQLiteDatabase
    ) throws -> ContextPack? {
        try db.queryOne(
            """
            SELECT id, task_id, revision, payload_json, source_manifest_json,
                   freshness, stale_reason, created_at
            FROM context_packs
            WHERE task_id = ? AND revision < ?
            ORDER BY revision DESC
            LIMIT 1;
            """,
            bindings: [taskID, String(beforeRevision)]
        ).map(decodePack)
    }

    static func packID(
        taskID: String,
        atOrBeforeRevision revision: Int64,
        in db: SQLiteDatabase
    ) throws -> String? {
        try db.queryOne(
            """
            SELECT id
            FROM context_packs
            WHERE task_id = ? AND revision <= ?
            ORDER BY revision DESC
            LIMIT 1;
            """,
            bindings: [taskID, String(revision)]
        )?["id"]
    }

    static func insertPack(_ pack: ContextPack, into db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO context_packs (
                id, task_id, revision, payload_json, source_manifest_json,
                freshness, stale_reason, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                pack.id, pack.taskID, String(pack.revision),
                try ContextJSONCodec.encode(pack.content),
                try ContextJSONCodec.encode(pack.sourceManifest), pack.freshness,
                pack.staleReason, pack.createdAt,
            ]
        )
    }

    static func setCurrentPack(_ pack: ContextPack, updatedAt: String, in db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO task_context_state (task_id, current_pack_id, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
                current_pack_id = excluded.current_pack_id,
                updated_at = excluded.updated_at;
            """,
            bindings: [pack.taskID, pack.id, updatedAt]
        )
    }

    static func updateFreshness(_ pack: ContextPack, in db: SQLiteDatabase) throws {
        try db.execute(
            "UPDATE context_packs SET freshness = ?, stale_reason = ? WHERE id = ?;",
            bindings: [pack.freshness, pack.staleReason, pack.id]
        )
    }

    static func insertGitBaseline(
        _ baseline: GitContextBaseline,
        contextPackID: String,
        into db: SQLiteDatabase
    ) throws {
        try db.execute(
            """
            INSERT INTO context_pack_git_baselines (
                context_pack_id, task_id, workspace_path, branch, head_sha, captured_at
            ) VALUES (?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                contextPackID, baseline.taskID, baseline.workspacePath, baseline.branch,
                baseline.headSHA, baseline.capturedAt,
            ]
        )
    }

    private static func decodeDraft(_ row: [String: String]) throws -> ContextDraft {
        ContextDraft(
            id: row["id"] ?? "",
            taskID: row["task_id"] ?? "",
            baseRevision: Int64(row["base_revision"] ?? "0") ?? 0,
            provider: row["provider"] ?? "",
            model: row["model"] ?? "",
            content: try ContextJSONCodec.decode(
                ContextPackContent.self,
                from: row["payload_json"] ?? "{}"
            ),
            sourceManifest: try ContextJSONCodec.decode(
                [ContextSourceRef].self,
                from: row["source_manifest_json"] ?? "[]"
            ),
            answers: try ContextJSONCodec.decode(
                [String: String].self,
                from: row["answers_json"] ?? "{}"
            ),
            status: row["status"] ?? "pending",
            createdAt: row["created_at"] ?? "",
            updatedAt: row["updated_at"] ?? ""
        )
    }

    private static func decodePack(_ row: [String: String]) throws -> ContextPack {
        ContextPack(
            id: row["id"] ?? "",
            taskID: row["task_id"] ?? "",
            revision: Int64(row["revision"] ?? "0") ?? 0,
            content: try ContextJSONCodec.decode(
                ContextPackContent.self,
                from: row["payload_json"] ?? "{}"
            ),
            sourceManifest: try ContextJSONCodec.decode(
                [ContextSourceRef].self,
                from: row["source_manifest_json"] ?? "[]"
            ),
            freshness: row["freshness"] ?? "possibly_stale",
            staleReason: row["stale_reason"],
            createdAt: row["created_at"] ?? ""
        )
    }
}

enum ContextBindingPersistence {
    static func workspaceBinding(taskID: String, in db: SQLiteDatabase) throws -> ContextBindingRecord? {
        try db.queryOne(
            """
            SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
            FROM context_bindings
            WHERE scope_type = 'workspace' AND task_id = ?
            ORDER BY updated_at DESC
            LIMIT 1;
            """,
            bindings: [taskID]
        ).map(ProjectionRowMapper.binding)
    }

    static func workspaceBinding(path: String, in db: SQLiteDatabase) throws -> ContextBindingRecord? {
        try db.queryOne(
            """
            SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
            FROM context_bindings
            WHERE scope_type = 'workspace' AND scope_key = ?;
            """,
            bindings: [WorkspacePath.normalize(path)]
        ).map(ProjectionRowMapper.binding)
    }

    static func listWorkspaceBindings(in db: SQLiteDatabase) throws -> [ContextBindingRecord] {
        try db.queryAll(
            """
            SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
            FROM context_bindings
            WHERE scope_type = 'workspace'
            ORDER BY updated_at DESC;
            """
        ).map(ProjectionRowMapper.binding)
    }

    static func advance(taskID: String, revision: Int64, updatedAt: String, in db: SQLiteDatabase) throws {
        try db.execute(
            """
            UPDATE context_bindings
            SET active_revision = ?, updated_at = ?
            WHERE task_id = ?;
            """,
            bindings: [String(revision), updatedAt, taskID]
        )
    }

    static func upsert(
        scopeType: String,
        scopeKey: String,
        taskID: String,
        revision: Int64,
        updatedAt: String,
        in db: SQLiteDatabase
    ) throws {
        try db.execute(
            """
            INSERT INTO context_bindings (
                scope_type, scope_key, mode, task_id, active_revision, updated_at
            ) VALUES (?, ?, 'pinned_task', ?, ?, ?)
            ON CONFLICT(scope_type, scope_key) DO UPDATE SET
                mode = excluded.mode,
                task_id = excluded.task_id,
                active_revision = excluded.active_revision,
                updated_at = excluded.updated_at;
            """,
            bindings: [scopeType, scopeKey, taskID, String(revision), updatedAt]
        )
    }
}

enum ProjectionPublisher {
    static func publish(
        task: TaskRecord,
        notes: [TaskNoteRecord],
        visibleFiles: [TaskFileRecord],
        payloads: ProjectionPayloads,
        contextPack: ContextPack?,
        revision: Int64,
        generatedAt: String,
        in db: SQLiteDatabase
    ) throws {
        try insertProjection(
            taskID: task.id,
            type: "active_task",
            payload: payloads.activePayload,
            revision: revision,
            generatedAt: generatedAt,
            contextPack: contextPack,
            into: db
        )
        try insertProjection(
            taskID: task.id,
            type: "manifest",
            payload: payloads.manifestPayload,
            revision: revision,
            generatedAt: generatedAt,
            contextPack: contextPack,
            into: db
        )
        try insertProjection(
            taskID: task.id,
            type: "resume_brief",
            payload: payloads.briefPayload,
            revision: revision,
            generatedAt: generatedAt,
            contextPack: contextPack,
            into: db
        )

        try db.execute("DELETE FROM mcp_note_exports WHERE task_id = ?;", bindings: [task.id])
        for note in notes {
            try db.execute(
                """
                INSERT INTO mcp_note_exports (
                    projection_schema_version, task_id, note_id, revision, title, body, generated_at
                ) VALUES (2, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [task.id, note.id, String(revision), note.title, note.body, generatedAt]
            )
        }

        try db.execute("DELETE FROM mcp_file_exports WHERE task_id = ?;", bindings: [task.id])
        for file in visibleFiles {
            try db.execute(
                """
                INSERT INTO mcp_file_exports (
                    projection_schema_version, task_id, file_id, revision, display_name, path, file_type,
                    generated_at
                ) VALUES (2, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    task.id, file.id, String(revision), file.displayName, file.path, file.fileType,
                    generatedAt,
                ]
            )
        }
    }

    private static func insertProjection(
        taskID: String,
        type: String,
        payload: String,
        revision: Int64,
        generatedAt: String,
        contextPack: ContextPack?,
        into db: SQLiteDatabase
    ) throws {
        try db.execute(
            """
            INSERT INTO mcp_context_projections (
                projection_schema_version, task_id, scope_type, scope_key, projection_type,
                payload_json, revision, freshness_at_generation, last_verified_at,
                stale_reason, generated_at, producer_core_version, producer_app_build
            ) VALUES (
                2, ?, 'task', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            );
            """,
            bindings: [
                taskID, taskID, type, payload, String(revision),
                contextPack?.freshness ?? "fresh", generatedAt, contextPack?.staleReason,
                generatedAt, NexusVersion.current, NexusVersion.current,
            ]
        )
    }
}
