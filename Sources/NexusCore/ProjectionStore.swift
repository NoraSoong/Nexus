import Foundation

public final class ProjectionStore: @unchecked Sendable {
    private let databaseURL: URL
    private let isoFormatter = ISO8601DateFormatter()
    private let databaseAccessGate = DatabaseAccessGate()
    private var migrationCompleted = false
    internal private(set) var schemaMigrationCount = 0

    public init(databaseURL: URL = NexusPaths.databaseURL) {
        self.databaseURL = databaseURL
    }

    public func bootstrap() throws {
        try ensureDatabaseDirectory()
        _ = try openDatabase()
        let tasks = try listTasks()
        if try activeTask() == nil, let first = tasks.first {
            try switchTask(taskID: first.id)
        }
        try ensureWorkspaceBindings()
    }

    @discardableResult
    public func createTask(title: String, goal: String) throws -> TaskRecord {
        try ensureDatabaseDirectory()
        let db = try openDatabase()
        let now = now()
        let id = UUID().uuidString.lowercased()
        try db.execute(
            """
            INSERT INTO tasks (id, title, goal, status, created_at, updated_at)
            VALUES (?, ?, ?, 'active', ?, ?);
            """,
            bindings: [id, title, goal, now, now]
        )
        return TaskRecord(id: id, title: title, goal: goal, status: "active", createdAt: now, updatedAt: now)
    }

    @discardableResult
    public func createTask(title: String, goal: String, workspacePath: String) throws -> TaskRecord {
        try ensureDatabaseDirectory()
        let db = try openDatabase()
        guard let workspace = GitRepositoryReader.workspaceInfo(at: workspacePath) else {
            throw SQLiteError.executeFailed("not a Git workspace: \(workspacePath)")
        }

        let timestamp = now()
        let task = TaskRecord(
            id: UUID().uuidString.lowercased(),
            title: title,
            goal: goal,
            status: "active",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let repository = TaskRepositoryRecord(
            taskID: task.id,
            path: workspace.path,
            branch: workspace.branch,
            anchorHeadSHA: GitRepositoryReader.headSHA(at: workspace.path),
            anchorBranch: workspace.branch,
            anchorCapturedAt: timestamp,
            updatedAt: timestamp
        )
        let context = ProjectionContext(
            checkpoint: nil,
            notes: [],
            visibleFiles: [],
            hiddenFiles: [],
            repository: repository,
            supplement: nil
        )
        let gitActivity = repositoryAnchorActivity(repository, capturedAt: timestamp)
        let payloads = try makePayloads(
            task: task,
            context: context,
            pack: nil,
            gitActivity: gitActivity,
            now: timestamp
        )

        try db.execute("BEGIN IMMEDIATE;")
        do {
            guard
                try db.queryOne(
                    """
                    SELECT id FROM context_bindings
                    WHERE scope_type = 'workspace' AND scope_key = ?
                    LIMIT 1;
                    """,
                    bindings: [workspace.path]
                ) == nil
            else {
                throw SQLiteError.executeFailed("workspace already bound: \(workspace.path)")
            }
            try db.execute(
                """
                INSERT INTO tasks (id, title, goal, status, created_at, updated_at)
                VALUES (?, ?, ?, 'active', ?, ?);
                """,
                bindings: [task.id, task.title, task.goal, timestamp, timestamp]
            )
            try db.execute(
                """
                INSERT INTO task_repositories (
                    task_id, path, branch, anchor_head_sha, anchor_branch, anchor_captured_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    task.id, repository.path, repository.branch, repository.anchorHeadSHA,
                    repository.anchorBranch, repository.anchorCapturedAt, repository.updatedAt,
                ]
            )
            try db.execute("INSERT INTO revision_counter DEFAULT VALUES;")
            let revision = db.lastInsertRowID
            try writeProjectionRows(
                db: db,
                task: task,
                context: context,
                payloads: payloads,
                pack: nil,
                revision: revision,
                now: timestamp
            )
            try upsertBinding(
                db: db,
                scopeType: "workspace",
                scopeKey: workspace.path,
                taskID: task.id,
                revision: revision,
                now: timestamp
            )
            try db.execute("COMMIT;")
            return task
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    public func listTasks() throws -> [TaskRecord] {
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT id, title, goal, status, created_at, updated_at
            FROM tasks
            WHERE archived_at IS NULL
            ORDER BY updated_at DESC, created_at DESC;
            """
        ).map(ProjectionRowMapper.task)
    }

    public func listArchivedTasks() throws -> [TaskRecord] {
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT id, title, goal, status, created_at, updated_at
            FROM tasks
            WHERE archived_at IS NOT NULL
            ORDER BY updated_at DESC, created_at DESC;
            """
        ).map(ProjectionRowMapper.task)
    }

    public func updateTask(id: String, title: String, goal: String) throws {
        let db = try openDatabase()
        try db.execute(
            "UPDATE tasks SET title = ?, goal = ?, updated_at = ? WHERE id = ?;",
            bindings: [title, goal, now(), id]
        )
        try refreshTaskIfBound(taskID: id)
    }

    public func deleteTask(id: String) throws {
        let db = try openDatabase()
        let wasActive = try activeTask()?.taskID == id
        try db.execute("BEGIN IMMEDIATE;")
        do {
            try db.execute("DELETE FROM task_context_state WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM context_drafts WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM context_pack_git_baselines WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM context_packs WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM mcp_note_exports WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM mcp_file_exports WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM mcp_context_projections WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM context_bindings WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM task_notes WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM checkpoints WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM task_files WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM task_repositories WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM task_supplements WHERE task_id = ?;", bindings: [id])
            try db.execute("DELETE FROM tasks WHERE id = ?;", bindings: [id])
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
        if wasActive, let next = try listTasks().first {
            try switchTask(taskID: next.id)
        }
    }

    public func archiveTask(id: String) throws {
        let db = try openDatabase()
        let wasActive = try activeTask()?.taskID == id
        let timestamp = now()
        try db.execute("BEGIN IMMEDIATE;")
        do {
            try db.execute(
                "UPDATE tasks SET status = 'archived', archived_at = ?, updated_at = ? WHERE id = ?;",
                bindings: [timestamp, timestamp, id]
            )
            try db.execute(
                "DELETE FROM context_bindings WHERE task_id = ?;",
                bindings: [id]
            )
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
        if wasActive {
            if let next = try listTasks().first {
                try switchTask(taskID: next.id)
            }
        }
    }

    public func restoreTask(id: String) throws {
        let db = try openDatabase()
        try db.execute(
            "UPDATE tasks SET status = 'active', archived_at = NULL, updated_at = ? WHERE id = ?;",
            bindings: [now(), id]
        )
        guard let task = try findTask(id: id, db: db),
            let repository = try repository(taskID: id),
            GitRepositoryReader.workspaceInfo(at: repository.path) != nil,
            try workspaceBinding(path: repository.path) == nil
        else {
            return
        }
        try writeProjections(task: task, db: db, workspacePath: repository.path)
    }

    public func switchTask(taskID: String) throws {
        try ensureDatabaseDirectory()
        let db = try openDatabase()
        guard let task = try findTask(id: taskID, db: db) else {
            throw SQLiteError.executeFailed("task not found: \(taskID)")
        }
        try writeProjections(task: task, db: db, setGlobal: true)
    }

    public func switchTask(taskID: String, title: String) throws {
        let tasks = try listTasks()
        if tasks.contains(where: { $0.id == taskID }) {
            try switchTask(taskID: taskID)
        } else {
            let task = try createTask(title: title, goal: "Verify Nexus MCP switching.")
            try switchTask(taskID: task.id)
        }
    }

    public func refreshActiveContextFreshness() throws {
        let db = try openDatabase()
        let taskIDs = try db.queryAll(
            "SELECT DISTINCT task_id FROM context_bindings WHERE task_id IS NOT NULL;"
        ).compactMap { $0["task_id"] }
        for taskID in taskIDs {
            guard let task = try findTask(id: taskID, db: db),
                let existingPack = try currentContextPack(taskID: task.id, db: db)
            else {
                continue
            }
            let context = try loadProjectionContext(taskID: task.id)
            guard let verifiedPack = try resolvedContextPack(task: task, context: context).persistedPack else {
                continue
            }
            guard
                verifiedPack.freshness != existingPack.freshness
                    || verifiedPack.staleReason != existingPack.staleReason
            else {
                continue
            }
            try writeProjections(task: task, db: db)
        }
    }

    @discardableResult
    public func addNote(taskID: String, title: String, body: String, exposed: Bool) throws -> TaskNoteRecord {
        let db = try openDatabase()
        let now = now()
        let id = UUID().uuidString.lowercased()
        try db.execute(
            """
            INSERT INTO task_notes (id, task_id, title, body, is_exposed_to_mcp, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [id, taskID, title, body, exposed ? "1" : "0", now, now]
        )
        try refreshTaskIfBound(taskID: taskID)
        return TaskNoteRecord(
            id: id, taskID: taskID, title: title, body: body, isExposedToMCP: exposed, createdAt: now, updatedAt: now)
    }

    public func listNotes(taskID: String) throws -> [TaskNoteRecord] {
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT id, task_id, title, body, is_exposed_to_mcp, created_at, updated_at
            FROM task_notes
            WHERE task_id = ?
            ORDER BY updated_at DESC, created_at DESC;
            """,
            bindings: [taskID]
        ).map(ProjectionRowMapper.note)
    }

    public func updateNote(id: String, taskID: String, title: String, body: String, exposed: Bool) throws {
        let db = try openDatabase()
        try db.execute(
            """
            UPDATE task_notes
            SET title = ?, body = ?, is_exposed_to_mcp = ?, updated_at = ?
            WHERE id = ? AND task_id = ?;
            """,
            bindings: [title, body, exposed ? "1" : "0", now(), id, taskID]
        )
        try refreshTaskIfBound(taskID: taskID)
    }

    public func removeNote(id: String, taskID: String) throws {
        let db = try openDatabase()
        try db.execute("DELETE FROM task_notes WHERE id = ? AND task_id = ?;", bindings: [id, taskID])
        try refreshTaskIfBound(taskID: taskID)
    }

    @discardableResult
    public func addFile(taskID: String, fileURL: URL, visibleToAgent: Bool = true) throws -> TaskFileRecord {
        let db = try openDatabase()
        let values = try TaskFileFactory.make(
            taskID: taskID, fileURL: fileURL, visibleToAgent: visibleToAgent, now: now(), isoFormatter: isoFormatter)
        if let existing = try fileRecordByPath(taskID: taskID, path: values.path, db: db) {
            try db.execute(
                """
                UPDATE task_files
                SET display_name = ?, file_type = ?, modified_at = ?, updated_at = ?
                WHERE id = ? AND task_id = ?;
                """,
                bindings: [
                    values.displayName, values.fileType, values.modifiedAt, values.updatedAt, existing.id, taskID,
                ]
            )
            try refreshTaskIfBound(taskID: taskID)
            return try fileRecordByPath(taskID: taskID, path: values.path, db: db) ?? existing
        }
        try db.execute(
            """
            INSERT INTO task_files (
                id, task_id, display_name, path, file_type, modified_at, is_visible_to_agent, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                values.id, values.taskID, values.displayName, values.path, values.fileType,
                values.modifiedAt, values.isVisibleToAgent ? "1" : "0", values.createdAt, values.updatedAt,
            ]
        )
        try refreshTaskIfBound(taskID: taskID)
        return values
    }

    public func listFiles(taskID: String) throws -> [TaskFileRecord] {
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT id, task_id, display_name, path, file_type, modified_at, is_visible_to_agent, created_at, updated_at
            FROM task_files
            WHERE task_id = ?
            ORDER BY updated_at DESC, created_at DESC;
            """,
            bindings: [taskID]
        ).map(ProjectionRowMapper.file)
    }

    public func updateFile(id: String, taskID: String, displayName: String, visibleToAgent: Bool) throws {
        let db = try openDatabase()
        try db.execute(
            "UPDATE task_files SET display_name = ?, is_visible_to_agent = ?, updated_at = ? WHERE id = ? AND task_id = ?;",
            bindings: [displayName, visibleToAgent ? "1" : "0", now(), id, taskID]
        )
        try refreshTaskIfBound(taskID: taskID)
    }

    public func removeFileReference(id: String, taskID: String) throws {
        let db = try openDatabase()
        try db.execute("DELETE FROM task_files WHERE id = ? AND task_id = ?;", bindings: [id, taskID])
        try refreshTaskIfBound(taskID: taskID)
    }

    public func setRepository(taskID: String, path: String) throws {
        let db = try openDatabase()
        guard let workspace = GitRepositoryReader.workspaceInfo(at: path) else {
            throw SQLiteError.executeFailed("not a Git workspace: \(path)")
        }
        let normalizedPath = workspace.path
        let timestamp = now()
        guard let task = try findTask(id: taskID, db: db) else {
            throw SQLiteError.executeFailed("task not found: \(taskID)")
        }
        let repository = TaskRepositoryRecord(
            taskID: taskID,
            path: normalizedPath,
            branch: workspace.branch,
            anchorHeadSHA: GitRepositoryReader.headSHA(at: normalizedPath),
            anchorBranch: workspace.branch,
            anchorCapturedAt: timestamp,
            updatedAt: timestamp
        )
        let existingContext = try loadProjectionContext(taskID: taskID)
        let context = ProjectionContext(
            checkpoint: existingContext.checkpoint,
            notes: existingContext.notes,
            visibleFiles: existingContext.visibleFiles,
            hiddenFiles: existingContext.hiddenFiles,
            repository: repository,
            supplement: existingContext.supplement
        )
        let packResolution = try resolvedContextPack(task: task, context: context)
        let gitActivity = repositoryAnchorActivity(repository, capturedAt: timestamp)
        let payloads = try makePayloads(
            task: task,
            context: context,
            pack: packResolution.projectionPack,
            gitActivity: gitActivity,
            now: timestamp
        )

        try db.execute("BEGIN IMMEDIATE;")
        do {
            if let binding = try db.queryOne(
                """
                SELECT task_id FROM context_bindings
                WHERE scope_type = 'workspace' AND scope_key = ?
                LIMIT 1;
                """,
                bindings: [normalizedPath]
            ), binding["task_id"] != taskID {
                throw SQLiteError.executeFailed("workspace already bound: \(normalizedPath)")
            }
            if try db.queryOne(
                """
                SELECT task_id FROM task_repositories
                WHERE path = ? AND task_id != ?
                LIMIT 1;
                """,
                bindings: [normalizedPath, taskID]
            ) != nil {
                throw SQLiteError.executeFailed("workspace already linked: \(normalizedPath)")
            }
            let previousPath = try db.queryOne(
                "SELECT path FROM task_repositories WHERE task_id = ?;",
                bindings: [taskID]
            )?["path"]

            try db.execute(
                """
                INSERT INTO task_repositories (
                    task_id, path, branch, anchor_head_sha, anchor_branch, anchor_captured_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                    path = excluded.path,
                    branch = excluded.branch,
                    anchor_head_sha = excluded.anchor_head_sha,
                    anchor_branch = excluded.anchor_branch,
                    anchor_captured_at = excluded.anchor_captured_at,
                    updated_at = excluded.updated_at;
                """,
                bindings: [
                    taskID, repository.path, repository.branch, repository.anchorHeadSHA,
                    repository.anchorBranch, repository.anchorCapturedAt, repository.updatedAt,
                ]
            )
            if let previousPath, WorkspacePath.normalize(previousPath) != normalizedPath {
                try db.execute(
                    """
                    DELETE FROM context_bindings
                    WHERE scope_type = 'workspace' AND scope_key = ? AND task_id = ?;
                    """,
                    bindings: [WorkspacePath.normalize(previousPath), taskID]
                )
            }
            try db.execute("INSERT INTO revision_counter DEFAULT VALUES;")
            let revision = db.lastInsertRowID
            if let persistedPack = packResolution.persistedPack {
                try db.execute(
                    "UPDATE context_packs SET freshness = ?, stale_reason = ? WHERE id = ?;",
                    bindings: [persistedPack.freshness, persistedPack.staleReason, persistedPack.id]
                )
            }
            try writeProjectionRows(
                db: db,
                task: task,
                context: context,
                payloads: payloads,
                pack: packResolution.projectionPack,
                revision: revision,
                now: timestamp
            )
            try advanceBindings(db: db, taskID: taskID, revision: revision, now: timestamp)
            try upsertBinding(
                db: db,
                scopeType: "workspace",
                scopeKey: normalizedPath,
                taskID: taskID,
                revision: revision,
                now: timestamp
            )
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    public func repository(taskID: String) throws -> TaskRepositoryRecord? {
        let db = try openDatabase()
        return try db.queryOne(
            """
            SELECT task_id, path, branch, anchor_head_sha, anchor_branch, anchor_captured_at, updated_at
            FROM task_repositories
            WHERE task_id = ?;
            """,
            bindings: [taskID]
        ).map(ProjectionRowMapper.repository)
    }

    public func listRepositories() throws -> [TaskRepositoryRecord] {
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT r.task_id, r.path, r.branch, r.anchor_head_sha, r.anchor_branch,
                   r.anchor_captured_at, r.updated_at
            FROM task_repositories r
            JOIN tasks t ON t.id = r.task_id
            WHERE t.archived_at IS NULL
            ORDER BY r.updated_at DESC;
            """
        ).map(ProjectionRowMapper.repository)
    }

    public func workspaceBinding(taskID: String) throws -> ContextBindingRecord? {
        let db = try openDatabase()
        return try db.queryOne(
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

    public func workspaceBinding(path: String) throws -> ContextBindingRecord? {
        let db = try openDatabase()
        return try db.queryOne(
            """
            SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
            FROM context_bindings
            WHERE scope_type = 'workspace' AND scope_key = ?;
            """,
            bindings: [WorkspacePath.normalize(path)]
        ).map(ProjectionRowMapper.binding)
    }

    public func listWorkspaceBindings() throws -> [ContextBindingRecord] {
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT id, scope_type, scope_key, mode, task_id, active_revision, updated_at
            FROM context_bindings
            WHERE scope_type = 'workspace'
            ORDER BY updated_at DESC;
            """
        ).map(ProjectionRowMapper.binding)
    }

    public func currentGitBranch(at path: String) -> String {
        GitRepositoryReader.branch(at: path)
    }

    public func gitDirtyState(at path: String) -> GitWorkingTreeState {
        GitRepositoryReader.dirtyState(at: path)
    }

    public func gitWorkspaceInfo(at path: String) -> GitWorkspaceInfo? {
        GitRepositoryReader.workspaceInfo(at: path)
    }

    public func gitWorktrees(at path: String) -> [GitWorkspaceInfo] {
        GitRepositoryReader.worktrees(at: path)
    }

    public func gitBaseline(taskID: String) throws -> GitContextBaseline? {
        let db = try openDatabase()
        if let row = try db.queryOne(
            """
            SELECT b.context_pack_id, b.task_id, b.workspace_path, b.branch, b.head_sha, b.captured_at
            FROM task_context_state s
            JOIN context_pack_git_baselines b ON b.context_pack_id = s.current_pack_id
            WHERE s.task_id = ?;
            """,
            bindings: [taskID]
        ) {
            return gitBaseline(from: row)
        }
        guard let repository = try repository(taskID: taskID),
            let headSHA = repository.anchorHeadSHA,
            let branch = repository.anchorBranch,
            let capturedAt = repository.anchorCapturedAt
        else {
            return nil
        }
        return GitContextBaseline(
            contextPackID: nil,
            taskID: taskID,
            workspacePath: repository.path,
            branch: branch,
            headSHA: headSHA,
            capturedAt: capturedAt
        )
    }

    public func gitActivity(
        taskID: String,
        includeCommittedDiff: Bool = false,
        includeUncommittedDiff: Bool = false
    ) throws -> GitActivitySnapshot? {
        guard let repository = try repository(taskID: taskID) else { return nil }
        return GitRepositoryReader.activity(
            repository: repository,
            baseline: try gitBaseline(taskID: taskID),
            includeCommittedDiff: includeCommittedDiff,
            includeUncommittedDiff: includeUncommittedDiff,
            capturedAt: now()
        )
    }

    public static func gitPathStates(at paths: [String]) -> [GitPathState] {
        paths.map(GitRepositoryReader.pathState)
    }

    @discardableResult
    public func refreshWorkspaceActivity(taskIDs: [String]) throws -> [String] {
        var refreshedTaskIDs: [String] = []
        for taskID in Set(taskIDs).sorted() {
            if try refreshTaskIfBound(taskID: taskID) {
                refreshedTaskIDs.append(taskID)
            }
        }
        return refreshedTaskIDs
    }

    private func gitBaseline(from row: [String: String]) -> GitContextBaseline {
        GitContextBaseline(
            contextPackID: row["context_pack_id"],
            taskID: row["task_id"] ?? "",
            workspacePath: row["workspace_path"] ?? "",
            branch: row["branch"] ?? "",
            headSHA: row["head_sha"] ?? "",
            capturedAt: row["captured_at"] ?? ""
        )
    }

    public func updateSupplement(taskID: String, body: String) throws {
        let db = try openDatabase()
        let now = now()
        try db.execute(
            """
            INSERT INTO task_supplements (task_id, body, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
                body = excluded.body,
                updated_at = excluded.updated_at;
            """,
            bindings: [taskID, body, now]
        )
        try refreshTaskIfBound(taskID: taskID)
    }

    public func supplement(taskID: String) throws -> TaskSupplementRecord? {
        let db = try openDatabase()
        return try db.queryOne(
            "SELECT task_id, body, updated_at FROM task_supplements WHERE task_id = ?;",
            bindings: [taskID]
        ).map(ProjectionRowMapper.supplement)
    }

    @discardableResult
    public func saveCheckpoint(taskID: String, currentState: String, nextStep: String, blockers: String) throws
        -> CheckpointRecord
    {
        let db = try openDatabase()
        let now = now()
        let id = UUID().uuidString.lowercased()
        try db.execute(
            """
            INSERT INTO checkpoints (id, task_id, current_state, next_step, blockers, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            bindings: [id, taskID, currentState, nextStep, blockers, now]
        )
        try refreshTaskIfBound(taskID: taskID)
        return CheckpointRecord(
            id: id, taskID: taskID, currentState: currentState, nextStep: nextStep, blockers: blockers, createdAt: now)
    }

    public func latestCheckpoint(taskID: String) throws -> CheckpointRecord? {
        let db = try openDatabase()
        return try db.queryOne(
            """
            SELECT id, task_id, current_state, next_step, blockers, created_at
            FROM checkpoints
            WHERE task_id = ?
            ORDER BY created_at DESC
            LIMIT 1;
            """,
            bindings: [taskID]
        ).map(ProjectionRowMapper.checkpoint)
    }

    public func recentCheckpoints(taskID: String, limit: Int = 8) throws -> [CheckpointRecord] {
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT id, task_id, current_state, next_step, blockers, created_at
            FROM checkpoints
            WHERE task_id = ?
            ORDER BY created_at DESC
            LIMIT ?;
            """,
            bindings: [taskID, String(max(1, limit))]
        ).map(ProjectionRowMapper.checkpoint)
    }

    public func activeTask() throws -> ActiveTaskProjection? {
        let db = try openDatabase()
        guard
            let binding = try db.queryOne(
                "SELECT task_id, active_revision FROM context_bindings WHERE scope_type = 'global' AND scope_key = 'default';"
            ), let taskID = binding["task_id"], let revision = binding["active_revision"]
        else {
            return nil
        }

        guard
            let projection = try db.queryOne(
                """
                SELECT payload_json, freshness_at_generation
                FROM mcp_context_projections
                WHERE task_id = ? AND revision = ? AND projection_type = 'active_task';
                """,
                bindings: [taskID, revision]
            )
        else {
            return nil
        }

        let title = (try findTask(id: taskID, db: db))?.title ?? taskID
        return ActiveTaskProjection(
            taskID: taskID,
            title: title,
            revision: Int64(revision) ?? 0,
            freshness: projection["freshness_at_generation"] ?? "possibly_stale",
            payloadJSON: projection["payload_json"] ?? "{}"
        )
    }

    public func projectionSnapshot(taskID: String) throws -> ProjectionSnapshot? {
        let db = try openDatabase()
        guard
            let binding = try db.queryOne(
                """
                SELECT active_revision
                FROM context_bindings
                WHERE task_id = ?
                ORDER BY CASE WHEN scope_type = 'global' THEN 0 ELSE 1 END, updated_at DESC
                LIMIT 1;
                """,
                bindings: [taskID]
            ), let revision = binding["active_revision"]
        else {
            return nil
        }
        let rows = try db.queryAll(
            """
            SELECT projection_type, payload_json
            FROM mcp_context_projections
            WHERE task_id = ? AND revision = ? AND projection_type IN ('active_task', 'manifest', 'resume_brief');
            """,
            bindings: [taskID, revision]
        )
        let byType = Dictionary(
            uniqueKeysWithValues: rows.compactMap { row -> (String, String)? in
                guard let type = row["projection_type"], let payload = row["payload_json"] else { return nil }
                return (type, payload)
            })
        guard let active = byType["active_task"], let manifest = byType["manifest"], let brief = byType["resume_brief"]
        else {
            return nil
        }
        return ProjectionSnapshot(activeTaskJSON: active, manifestJSON: manifest, resumeBriefJSON: brief)
    }

    public func latestProjectionRevision(taskID: String) throws -> Int64 {
        let db = try openDatabase()
        return try latestProjectionRevision(taskID: taskID, db: db)
    }

    private func latestProjectionRevision(taskID: String, db: SQLiteDatabase) throws -> Int64 {
        let row = try db.queryOne(
            "SELECT MAX(revision) AS revision FROM mcp_context_projections WHERE task_id = ?;",
            bindings: [taskID]
        )
        return Int64(row?["revision"] ?? "0") ?? 0
    }

    @discardableResult
    public func saveContextDraft(
        taskID: String,
        baseRevision: Int64,
        provider: String,
        model: String,
        content: ContextPackContent,
        sourceManifest: [ContextSourceRef],
        answers: [String: String]
    ) throws -> ContextDraft {
        let db = try openDatabase()
        let timestamp = now()
        let draft = ContextDraft(
            id: UUID().uuidString.lowercased(),
            taskID: taskID,
            baseRevision: baseRevision,
            provider: provider,
            model: model,
            content: content,
            sourceManifest: sourceManifest,
            answers: answers,
            status: "pending",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try db.execute(
            """
            INSERT INTO context_drafts (
                id, task_id, base_revision, provider, model, payload_json,
                source_manifest_json, answers_json, status, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                draft.id, draft.taskID, String(draft.baseRevision), draft.provider, draft.model,
                try encodeJSON(draft.content), try encodeJSON(draft.sourceManifest), try encodeJSON(draft.answers),
                draft.status, draft.createdAt, draft.updatedAt,
            ]
        )
        return draft
    }

    public func latestContextDraft(taskID: String) throws -> ContextDraft? {
        let db = try openDatabase()
        return try db.queryOne(
            """
            SELECT id, task_id, base_revision, provider, model, payload_json,
                   source_manifest_json, answers_json, status, created_at, updated_at
            FROM context_drafts
            WHERE task_id = ? AND status = 'pending'
            ORDER BY updated_at DESC
            LIMIT 1;
            """,
            bindings: [taskID]
        ).map(decodeContextDraft)
    }

    public func updateContextDraft(id: String, content: ContextPackContent, answers: [String: String]) throws {
        let db = try openDatabase()
        try db.execute(
            """
            UPDATE context_drafts
            SET payload_json = ?, answers_json = ?, updated_at = ?
            WHERE id = ? AND status = 'pending';
            """,
            bindings: [try encodeJSON(content), try encodeJSON(answers), now(), id]
        )
    }

    public func currentContextPack(taskID: String) throws -> ContextPack? {
        let db = try openDatabase()
        return try currentContextPack(taskID: taskID, db: db)
    }

    public func contextPackHistory(taskID: String, limit: Int = 20) throws -> [ContextPack] {
        guard limit > 0 else { return [] }
        let db = try openDatabase()
        return try db.queryAll(
            """
            SELECT id, task_id, revision, payload_json, source_manifest_json,
                   freshness, stale_reason, created_at
            FROM context_packs
            WHERE task_id = ?
            ORDER BY revision DESC
            LIMIT ?;
            """,
            bindings: [taskID, String(limit)]
        ).map(decodeContextPack)
    }

    public func previousContextPack(taskID: String, beforeRevision: Int64) throws -> ContextPack? {
        let db = try openDatabase()
        return try db.queryOne(
            """
            SELECT id, task_id, revision, payload_json, source_manifest_json,
                   freshness, stale_reason, created_at
            FROM context_packs
            WHERE task_id = ? AND revision < ?
            ORDER BY revision DESC
            LIMIT 1;
            """,
            bindings: [taskID, String(beforeRevision)]
        ).map(decodeContextPack)
    }

    public func currentContextSourceChanges(taskID: String) throws -> [ContextSourceDelta] {
        let db = try openDatabase()
        guard let task = try findTask(id: taskID, db: db),
            let pack = try currentContextPack(taskID: taskID, db: db)
        else {
            return []
        }
        let context = try loadProjectionContext(taskID: taskID)
        let currentSources = try currentSourceReferences(task: task, context: context, pack: pack)
        return ContextReviewService.sourceChanges(
            baseline: pack.sourceManifest.filter(ContextSourceFreshnessPolicy.participatesInFreshness),
            candidate: currentSources.filter(ContextSourceFreshnessPolicy.participatesInFreshness)
        )
    }

    @discardableResult
    public func approveContextDraft(id: String, currentInput: ContextPreparationInput) throws -> ContextPack {
        let db = try openDatabase()
        guard
            let preliminaryDraftRow = try db.queryOne(
                """
                SELECT id, task_id, base_revision, provider, model, payload_json,
                       source_manifest_json, answers_json, status, created_at, updated_at
                FROM context_drafts WHERE id = ? AND status = 'pending';
                """,
                bindings: [id]
            )
        else {
            throw ContextPreparationError.draftNotFound
        }
        let preliminaryDraft = try decodeContextDraft(preliminaryDraftRow)
        let projectionContext = try loadProjectionContext(taskID: preliminaryDraft.taskID)
        let gitBaselineCandidate = projectionContext.repository.flatMap { repository -> GitContextBaseline? in
            let currentBranch = GitRepositoryReader.branch(at: repository.path)
            guard currentBranch == repository.branch,
                let headSHA = GitRepositoryReader.headSHA(at: repository.path)
            else {
                return nil
            }
            return GitContextBaseline(
                contextPackID: nil,
                taskID: preliminaryDraft.taskID,
                workspacePath: WorkspacePath.normalize(repository.path),
                branch: currentBranch,
                headSHA: headSHA,
                capturedAt: now()
            )
        }

        try db.execute("BEGIN IMMEDIATE;")
        do {
            guard
                let draftRow = try db.queryOne(
                    """
                    SELECT id, task_id, base_revision, provider, model, payload_json,
                           source_manifest_json, answers_json, status, created_at, updated_at
                    FROM context_drafts WHERE id = ? AND status = 'pending';
                    """,
                    bindings: [id]
                )
            else {
                throw ContextPreparationError.draftNotFound
            }
            let draft = try decodeContextDraft(draftRow)
            let currentManifest = currentInput.sources.map(\.reference)
            guard draft.taskID == currentInput.taskID,
                ContextMaterialExtractor.manifestFingerprint(draft.sourceManifest)
                    == ContextMaterialExtractor.manifestFingerprint(currentManifest)
            else {
                throw ContextPreparationError.staleDraft
            }
            let baseContextPackID = try contextPackID(
                taskID: draft.taskID,
                atOrBeforeRevision: draft.baseRevision,
                db: db
            )
            let currentContextPackID = try currentContextPack(taskID: draft.taskID, db: db)?.id
            guard baseContextPackID == currentContextPackID else {
                throw ContextPreparationError.staleDraft
            }
            guard let task = try findTask(id: draft.taskID, db: db) else {
                throw SQLiteError.executeFailed("task not found: \(draft.taskID)")
            }
            let timestamp = now()
            let packID = UUID().uuidString.lowercased()

            try db.execute("INSERT INTO revision_counter DEFAULT VALUES;")
            let revision = db.lastInsertRowID
            let pack = ContextPack(
                id: packID,
                taskID: task.id,
                revision: revision,
                content: draft.content,
                sourceManifest: draft.sourceManifest,
                freshness: "fresh",
                staleReason: nil,
                createdAt: timestamp
            )
            try db.execute(
                """
                INSERT INTO context_packs (
                    id, task_id, revision, payload_json, source_manifest_json,
                    freshness, stale_reason, created_at
                ) VALUES (?, ?, ?, ?, ?, 'fresh', NULL, ?);
                """,
                bindings: [
                    pack.id, pack.taskID, String(pack.revision), try encodeJSON(pack.content),
                    try encodeJSON(pack.sourceManifest), pack.createdAt,
                ]
            )
            try db.execute(
                """
                INSERT INTO task_context_state (task_id, current_pack_id, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                    current_pack_id = excluded.current_pack_id,
                    updated_at = excluded.updated_at;
                """,
                bindings: [pack.taskID, pack.id, timestamp]
            )
            if let gitBaselineCandidate {
                try db.execute(
                    """
                    INSERT INTO context_pack_git_baselines (
                        context_pack_id, task_id, workspace_path, branch, head_sha, captured_at
                    ) VALUES (?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        pack.id, pack.taskID, gitBaselineCandidate.workspacePath, gitBaselineCandidate.branch,
                        gitBaselineCandidate.headSHA, timestamp,
                    ]
                )
            }
            try db.execute(
                "UPDATE context_drafts SET status = 'applied', updated_at = ? WHERE id = ?;",
                bindings: [timestamp, draft.id]
            )
            let gitActivity = projectionContext.repository.map { repository in
                GitRepositoryReader.activity(
                    repository: repository,
                    baseline: gitBaselineCandidate,
                    includeCommittedDiff: false,
                    includeUncommittedDiff: false,
                    capturedAt: timestamp
                )
            }
            let payloads = try makePayloads(
                task: task,
                context: projectionContext,
                pack: pack,
                gitActivity: gitActivity,
                now: timestamp
            )
            try writeProjectionRows(
                db: db,
                task: task,
                context: projectionContext,
                payloads: payloads,
                pack: pack,
                revision: revision,
                now: timestamp
            )
            try advanceBindings(
                db: db,
                taskID: task.id,
                revision: revision,
                now: timestamp
            )
            try db.execute("COMMIT;")
            return pack
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    public func discardContextDraft(id: String) throws {
        let db = try openDatabase()
        try db.execute(
            "UPDATE context_drafts SET status = 'discarded', updated_at = ? WHERE id = ?;",
            bindings: [now(), id]
        )
    }

    private struct ProjectionContext {
        let checkpoint: CheckpointRecord?
        let notes: [TaskNoteRecord]
        let visibleFiles: [TaskFileRecord]
        let hiddenFiles: [TaskFileRecord]
        let repository: TaskRepositoryRecord?
        let supplement: TaskSupplementRecord?
    }

    private func writeProjections(
        task: TaskRecord,
        db: SQLiteDatabase,
        setGlobal: Bool = false,
        workspacePath: String? = nil
    ) throws {
        let now = now()
        let context = try loadProjectionContext(taskID: task.id)
        let packResolution = try resolvedContextPack(task: task, context: context)
        let gitActivity = try gitActivity(taskID: task.id)
        let payloads = try makePayloads(
            task: task,
            context: context,
            pack: packResolution.projectionPack,
            gitActivity: gitActivity,
            now: now
        )

        try db.execute("BEGIN IMMEDIATE;")
        do {
            try db.execute("INSERT INTO revision_counter DEFAULT VALUES;")
            let revision = db.lastInsertRowID
            if let persisted = packResolution.persistedPack {
                try db.execute(
                    "UPDATE context_packs SET freshness = ?, stale_reason = ? WHERE id = ?;",
                    bindings: [persisted.freshness, persisted.staleReason, persisted.id]
                )
            }
            try writeProjectionRows(
                db: db,
                task: task,
                context: context,
                payloads: payloads,
                pack: packResolution.projectionPack,
                revision: revision,
                now: now
            )
            try advanceBindings(db: db, taskID: task.id, revision: revision, now: now)
            if setGlobal {
                try upsertBinding(
                    db: db,
                    scopeType: "global",
                    scopeKey: "default",
                    taskID: task.id,
                    revision: revision,
                    now: now
                )
            }
            if let workspacePath {
                try upsertBinding(
                    db: db,
                    scopeType: "workspace",
                    scopeKey: WorkspacePath.normalize(workspacePath),
                    taskID: task.id,
                    revision: revision,
                    now: now
                )
            }
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    private func loadProjectionContext(taskID: String) throws -> ProjectionContext {
        let checkpoint = try latestCheckpoint(taskID: taskID)
        let notes = try listNotes(taskID: taskID).filter(\.isExposedToMCP)
        let files = try listFiles(taskID: taskID)
        return ProjectionContext(
            checkpoint: checkpoint,
            notes: notes,
            visibleFiles: files.filter(\.isVisibleToAgent),
            hiddenFiles: files.filter { !$0.isVisibleToAgent },
            repository: try repository(taskID: taskID),
            supplement: try supplement(taskID: taskID)
        )
    }

    private func makePayloads(
        task: TaskRecord,
        context: ProjectionContext,
        pack: ContextPack?,
        gitActivity: GitActivitySnapshot? = nil,
        now: String
    ) throws
        -> ProjectionPayloads
    {
        try ProjectionPayloadBuilder.build(
            task: task,
            checkpoint: context.checkpoint,
            notes: context.notes,
            visibleFiles: context.visibleFiles,
            hiddenFiles: context.hiddenFiles,
            repository: context.repository,
            supplement: context.supplement,
            contextPack: pack,
            gitActivity: gitActivity,
            now: now
        )
    }

    private func repositoryAnchorActivity(
        _ repository: TaskRepositoryRecord,
        capturedAt: String
    ) -> GitActivitySnapshot {
        let baseline: GitContextBaseline? = {
            guard let headSHA = repository.anchorHeadSHA,
                let branch = repository.anchorBranch,
                let anchorCapturedAt = repository.anchorCapturedAt
            else {
                return nil
            }
            return GitContextBaseline(
                contextPackID: nil,
                taskID: repository.taskID,
                workspacePath: repository.path,
                branch: branch,
                headSHA: headSHA,
                capturedAt: anchorCapturedAt
            )
        }()
        return GitRepositoryReader.activity(
            repository: repository,
            baseline: baseline,
            includeCommittedDiff: false,
            includeUncommittedDiff: false,
            capturedAt: capturedAt
        )
    }

    private func writeProjectionRows(
        db: SQLiteDatabase,
        task: TaskRecord,
        context: ProjectionContext,
        payloads: ProjectionPayloads,
        pack: ContextPack?,
        revision: Int64,
        now: String
    ) throws {
        try insertProjection(
            db, taskID: task.id, type: "active_task", payload: payloads.activePayload, revision: revision, now: now,
            pack: pack)
        try insertProjection(
            db, taskID: task.id, type: "manifest", payload: payloads.manifestPayload, revision: revision, now: now,
            pack: pack)
        try insertProjection(
            db, taskID: task.id, type: "resume_brief", payload: payloads.briefPayload, revision: revision, now: now,
            pack: pack)
        try db.execute("DELETE FROM mcp_note_exports WHERE task_id = ?;", bindings: [task.id])
        for note in context.notes {
            try db.execute(
                """
                INSERT INTO mcp_note_exports (
                    projection_schema_version, task_id, note_id, revision, title, body, generated_at
                ) VALUES (2, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [task.id, note.id, String(revision), note.title, note.body, now]
            )
        }
        try db.execute("DELETE FROM mcp_file_exports WHERE task_id = ?;", bindings: [task.id])
        for file in context.visibleFiles {
            try db.execute(
                """
                INSERT INTO mcp_file_exports (
                    projection_schema_version, task_id, file_id, revision, display_name, path, file_type, generated_at
                ) VALUES (2, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [task.id, file.id, String(revision), file.displayName, file.path, file.fileType, now]
            )
        }
    }

    private func advanceBindings(
        db: SQLiteDatabase,
        taskID: String,
        revision: Int64,
        now: String
    ) throws {
        try db.execute(
            """
            UPDATE context_bindings
            SET active_revision = ?, updated_at = ?
            WHERE task_id = ?;
            """,
            bindings: [String(revision), now, taskID]
        )
    }

    private func upsertBinding(
        db: SQLiteDatabase,
        scopeType: String,
        scopeKey: String,
        taskID: String,
        revision: Int64,
        now: String
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
            bindings: [scopeType, scopeKey, taskID, String(revision), now]
        )
    }

    private func resolvedContextPack(task: TaskRecord, context: ProjectionContext) throws -> (
        projectionPack: ContextPack?, persistedPack: ContextPack?
    ) {
        guard let pack = try currentContextPack(taskID: task.id) else { return (nil, nil) }
        let currentSources = try currentSourceReferences(task: task, context: context, pack: pack)
        let currentByID = Dictionary(uniqueKeysWithValues: currentSources.map { ($0.id, $0) })
        let freshnessSources = pack.sourceManifest.filter(ContextSourceFreshnessPolicy.participatesInFreshness)
        let missing = freshnessSources.contains { currentByID[$0.id] == nil }
        if missing {
            let stale = replacingFreshness(pack, freshness: "stale", reason: "source_hidden_missing_or_removed")
            return (nil, stale)
        }
        let changed = freshnessSources.contains { source in
            guard let current = currentByID[source.id] else { return true }
            return ContextSourceFreshnessPolicy.hasChanged(baseline: source, current: current)
        }
        if changed {
            let stale = replacingFreshness(pack, freshness: "possibly_stale", reason: "source_changed")
            return (stale, stale)
        }
        let fresh = replacingFreshness(pack, freshness: "fresh", reason: nil)
        return (fresh, fresh)
    }

    private func currentSourceReferences(
        task: TaskRecord,
        context: ProjectionContext,
        pack: ContextPack
    ) throws -> [ContextSourceRef] {
        let sourceIDs = Set(pack.sourceManifest.map(\.id))
        let packNotes = try listNotes(taskID: task.id).filter { sourceIDs.contains("note:\($0.id)") }
        let packFiles = (context.visibleFiles + context.hiddenFiles).filter { sourceIDs.contains("file:\($0.id)") }
        let input = try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: pack.revision,
            supplement: sourceIDs.contains("handoff:\(task.id)") ? context.supplement : nil,
            notes: packNotes,
            files: packFiles,
            repository: sourceIDs.contains("repository:\(task.id)") ? context.repository : nil
        )
        let immutableConfirmations = pack.sourceManifest.filter {
            $0.kind == ContextPreparationService.clarificationAnswerKind
        }
        return input.sources.map(\.reference) + immutableConfirmations
    }

    private func replacingFreshness(_ pack: ContextPack, freshness: String, reason: String?) -> ContextPack {
        ContextPack(
            id: pack.id,
            taskID: pack.taskID,
            revision: pack.revision,
            content: pack.content,
            sourceManifest: pack.sourceManifest,
            freshness: freshness,
            staleReason: reason,
            createdAt: pack.createdAt
        )
    }

    private func currentContextPack(taskID: String, db: SQLiteDatabase) throws -> ContextPack? {
        try db.queryOne(
            """
            SELECT p.id, p.task_id, p.revision, p.payload_json, p.source_manifest_json,
                   p.freshness, p.stale_reason, p.created_at
            FROM task_context_state s
            JOIN context_packs p ON p.id = s.current_pack_id
            WHERE s.task_id = ?;
            """,
            bindings: [taskID]
        ).map(decodeContextPack)
    }

    private func contextPackID(
        taskID: String,
        atOrBeforeRevision revision: Int64,
        db: SQLiteDatabase
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

    private func decodeContextDraft(_ row: [String: String]) throws -> ContextDraft {
        ContextDraft(
            id: row["id"] ?? "",
            taskID: row["task_id"] ?? "",
            baseRevision: Int64(row["base_revision"] ?? "0") ?? 0,
            provider: row["provider"] ?? "",
            model: row["model"] ?? "",
            content: try decodeJSON(ContextPackContent.self, row["payload_json"] ?? "{}"),
            sourceManifest: try decodeJSON([ContextSourceRef].self, row["source_manifest_json"] ?? "[]"),
            answers: try decodeJSON([String: String].self, row["answers_json"] ?? "{}"),
            status: row["status"] ?? "pending",
            createdAt: row["created_at"] ?? "",
            updatedAt: row["updated_at"] ?? ""
        )
    }

    private func decodeContextPack(_ row: [String: String]) throws -> ContextPack {
        ContextPack(
            id: row["id"] ?? "",
            taskID: row["task_id"] ?? "",
            revision: Int64(row["revision"] ?? "0") ?? 0,
            content: try decodeJSON(ContextPackContent.self, row["payload_json"] ?? "{}"),
            sourceManifest: try decodeJSON([ContextSourceRef].self, row["source_manifest_json"] ?? "[]"),
            freshness: row["freshness"] ?? "possibly_stale",
            staleReason: row["stale_reason"],
            createdAt: row["created_at"] ?? ""
        )
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func openDatabase() throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(url: databaseURL, accessGate: databaseAccessGate)
        if !migrationCompleted {
            try ProjectionSchemaMigrator.migrate(db)
            migrationCompleted = true
            schemaMigrationCount += 1
        }
        return db
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, _ value: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }

    private func insertProjection(
        _ db: SQLiteDatabase,
        taskID: String,
        type: String,
        payload: String,
        revision: Int64,
        now: String,
        pack: ContextPack?
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
                taskID, taskID, type, payload, String(revision), pack?.freshness ?? "fresh", now,
                pack?.staleReason, now, NexusVersion.current, NexusVersion.current,
            ]
        )
    }

    @discardableResult
    private func refreshTaskIfBound(taskID: String) throws -> Bool {
        let db = try openDatabase()
        guard
            try db.queryOne(
                "SELECT id FROM context_bindings WHERE task_id = ? LIMIT 1;",
                bindings: [taskID]
            ) != nil, let task = try findTask(id: taskID, db: db)
        else {
            return false
        }
        try writeProjections(task: task, db: db)
        return true
    }

    private func ensureWorkspaceBindings() throws {
        let repositories = try listRepositories()
        guard !repositories.isEmpty else { return }
        let activeTaskID = try activeTask()?.taskID
        let grouped = Dictionary(grouping: repositories) {
            WorkspacePath.normalize($0.path)
        }
        for (path, candidates) in grouped {
            if try workspaceBinding(path: path) != nil {
                continue
            }
            let selected = candidates.first(where: { $0.taskID == activeTaskID }) ?? candidates[0]
            let db = try openDatabase()
            guard let task = try findTask(id: selected.taskID, db: db) else { continue }
            try writeProjections(task: task, db: db, workspacePath: path)
        }
    }

    private func findTask(id: String, db: SQLiteDatabase) throws -> TaskRecord? {
        try db.queryOne(
            """
            SELECT id, title, goal, status, created_at, updated_at
            FROM tasks
            WHERE id = ? AND archived_at IS NULL;
            """,
            bindings: [id]
        ).map(ProjectionRowMapper.task)
    }

    private func fileRecordByPath(taskID: String, path: String, db: SQLiteDatabase) throws -> TaskFileRecord? {
        try db.queryOne(
            """
            SELECT id, task_id, display_name, path, file_type, modified_at, is_visible_to_agent, created_at, updated_at
            FROM task_files
            WHERE task_id = ? AND path = ?
            LIMIT 1;
            """,
            bindings: [taskID, path]
        ).map(ProjectionRowMapper.file)
    }

    private func now() -> String {
        isoFormatter.string(from: Date())
    }

    private func ensureDatabaseDirectory() throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
