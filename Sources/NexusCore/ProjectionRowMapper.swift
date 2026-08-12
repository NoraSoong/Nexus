import Foundation

enum ProjectionRowMapper {
    static func task(_ row: [String: String]) -> TaskRecord {
        TaskRecord(
            id: row["id"] ?? "",
            title: row["title"] ?? "",
            goal: row["goal"] ?? "",
            status: row["status"] ?? "active",
            createdAt: row["created_at"] ?? "",
            updatedAt: row["updated_at"] ?? ""
        )
    }

    static func note(_ row: [String: String]) -> TaskNoteRecord {
        TaskNoteRecord(
            id: row["id"] ?? "",
            taskID: row["task_id"] ?? "",
            title: row["title"] ?? "",
            body: row["body"] ?? "",
            isExposedToMCP: row["is_exposed_to_mcp"] == "1",
            createdAt: row["created_at"] ?? "",
            updatedAt: row["updated_at"] ?? ""
        )
    }

    static func file(_ row: [String: String]) -> TaskFileRecord {
        TaskFileRecord(
            id: row["id"] ?? "",
            taskID: row["task_id"] ?? "",
            displayName: row["display_name"] ?? "",
            path: row["path"] ?? "",
            fileType: row["file_type"] ?? "",
            modifiedAt: row["modified_at"] ?? "",
            isVisibleToAgent: row["is_visible_to_agent"] == "1",
            createdAt: row["created_at"] ?? "",
            updatedAt: row["updated_at"] ?? ""
        )
    }

    static func repository(_ row: [String: String]) -> TaskRepositoryRecord {
        TaskRepositoryRecord(
            taskID: row["task_id"] ?? "",
            path: row["path"] ?? "",
            branch: row["branch"] ?? "",
            workspaceOrigin: WorkspaceOrigin(rawValue: row["workspace_origin"] ?? "external") ?? .external,
            baseRef: row["base_ref"],
            createdHeadSHA: row["created_head_sha"],
            anchorHeadSHA: row["anchor_head_sha"],
            anchorBranch: row["anchor_branch"],
            anchorCapturedAt: row["anchor_captured_at"],
            updatedAt: row["updated_at"] ?? ""
        )
    }

    static func binding(_ row: [String: String]) -> ContextBindingRecord {
        ContextBindingRecord(
            id: Int64(row["id"] ?? "0") ?? 0,
            scopeType: row["scope_type"] ?? "",
            scopeKey: row["scope_key"] ?? "",
            mode: row["mode"] ?? "",
            taskID: row["task_id"] ?? "",
            activeRevision: Int64(row["active_revision"] ?? "0") ?? 0,
            updatedAt: row["updated_at"] ?? ""
        )
    }

    static func supplement(_ row: [String: String]) -> TaskSupplementRecord {
        TaskSupplementRecord(
            taskID: row["task_id"] ?? "",
            body: row["body"] ?? "",
            updatedAt: row["updated_at"] ?? ""
        )
    }

    static func checkpoint(_ row: [String: String]) -> CheckpointRecord {
        CheckpointRecord(
            id: row["id"] ?? "",
            taskID: row["task_id"] ?? "",
            currentState: row["current_state"] ?? "",
            nextStep: row["next_step"] ?? "",
            blockers: row["blockers"] ?? "",
            createdAt: row["created_at"] ?? ""
        )
    }
}
