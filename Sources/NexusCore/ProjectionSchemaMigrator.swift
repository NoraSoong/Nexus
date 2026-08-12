import Foundation

enum ProjectionSchemaMigrator {
    static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS revision_counter (
                id INTEGER PRIMARY KEY AUTOINCREMENT
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                goal TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'active',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                archived_at TEXT
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS task_notes (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                is_exposed_to_mcp INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS task_files (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                path TEXT NOT NULL,
                file_type TEXT NOT NULL,
                modified_at TEXT NOT NULL,
                is_visible_to_agent INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try db.execute(
            """
            DELETE FROM task_files
            WHERE rowid NOT IN (
                SELECT MAX(rowid)
                FROM task_files
                GROUP BY task_id, path
            );
            """
        )
        try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_task_files_task_path ON task_files(task_id, path);")
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS task_repositories (
                task_id TEXT PRIMARY KEY,
                path TEXT NOT NULL,
                branch TEXT NOT NULL,
                workspace_origin TEXT NOT NULL DEFAULT 'external',
                base_ref TEXT,
                created_head_sha TEXT,
                anchor_head_sha TEXT,
                anchor_branch TEXT,
                anchor_captured_at TEXT,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try addColumnIfMissing(db, table: "task_repositories", column: "anchor_head_sha", definition: "TEXT")
        try addColumnIfMissing(db, table: "task_repositories", column: "anchor_branch", definition: "TEXT")
        try addColumnIfMissing(db, table: "task_repositories", column: "anchor_captured_at", definition: "TEXT")
        try addColumnIfMissing(
            db,
            table: "task_repositories",
            column: "workspace_origin",
            definition: "TEXT NOT NULL DEFAULT 'external'"
        )
        try addColumnIfMissing(db, table: "task_repositories", column: "base_ref", definition: "TEXT")
        try addColumnIfMissing(db, table: "task_repositories", column: "created_head_sha", definition: "TEXT")
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS task_supplements (
                task_id TEXT PRIMARY KEY,
                body TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS checkpoints (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                current_state TEXT NOT NULL,
                next_step TEXT NOT NULL,
                blockers TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS context_bindings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                scope_type TEXT NOT NULL,
                scope_key TEXT NOT NULL,
                mode TEXT NOT NULL,
                task_id TEXT,
                active_revision INTEGER,
                updated_at TEXT NOT NULL,
                UNIQUE(scope_type, scope_key)
            );
            """
        )
        try db.execute("CREATE INDEX IF NOT EXISTS idx_context_bindings_task ON context_bindings(task_id);")
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS mcp_context_projections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                projection_schema_version INTEGER NOT NULL,
                task_id TEXT NOT NULL,
                scope_type TEXT NOT NULL,
                scope_key TEXT,
                projection_type TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                revision INTEGER NOT NULL,
                freshness_at_generation TEXT NOT NULL,
                last_verified_at TEXT,
                stale_reason TEXT,
                generated_at TEXT NOT NULL,
                producer_core_version TEXT NOT NULL,
                producer_app_build TEXT NOT NULL,
                UNIQUE(task_id, scope_type, scope_key, projection_type, revision)
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS mcp_note_exports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                projection_schema_version INTEGER NOT NULL,
                task_id TEXT NOT NULL,
                note_id TEXT NOT NULL,
                revision INTEGER NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                generated_at TEXT NOT NULL
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS mcp_file_exports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                projection_schema_version INTEGER NOT NULL,
                task_id TEXT NOT NULL,
                file_id TEXT NOT NULL,
                revision INTEGER NOT NULL,
                display_name TEXT NOT NULL,
                path TEXT NOT NULL,
                file_type TEXT NOT NULL,
                generated_at TEXT NOT NULL
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS context_drafts (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                base_revision INTEGER NOT NULL,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                source_manifest_json TEXT NOT NULL,
                answers_json TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_context_drafts_task_updated ON context_drafts(task_id, updated_at DESC);")
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS context_packs (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                revision INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                source_manifest_json TEXT NOT NULL,
                freshness TEXT NOT NULL,
                stale_reason TEXT,
                created_at TEXT NOT NULL,
                UNIQUE(task_id, revision),
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS task_context_state (
                task_id TEXT PRIMARY KEY,
                current_pack_id TEXT,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id),
                FOREIGN KEY(current_pack_id) REFERENCES context_packs(id)
            );
            """
        )
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS context_pack_git_baselines (
                context_pack_id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                workspace_path TEXT NOT NULL,
                branch TEXT NOT NULL,
                head_sha TEXT NOT NULL,
                captured_at TEXT NOT NULL,
                FOREIGN KEY(context_pack_id) REFERENCES context_packs(id),
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            """
        )
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_context_pack_git_baselines_task ON context_pack_git_baselines(task_id);"
        )
        try db.execute("INSERT OR REPLACE INTO metadata(key, value) VALUES ('projection_schema_version', '2');")
        try db.execute(
            "INSERT OR REPLACE INTO metadata(key, value) VALUES ('core_version', ?);",
            bindings: [NexusVersion.current]
        )
        try db.execute("PRAGMA user_version = 4;")
    }

    private static func addColumnIfMissing(
        _ db: SQLiteDatabase,
        table: String,
        column: String,
        definition: String
    ) throws {
        let columns = try db.queryAll("PRAGMA table_info(\(table));")
        guard !columns.contains(where: { $0["name"] == column }) else { return }
        try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }
}
