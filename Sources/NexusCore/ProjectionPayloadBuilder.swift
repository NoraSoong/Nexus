import Foundation

struct ProjectionPayloads {
    let activePayload: String
    let manifestPayload: String
    let briefPayload: String
}

enum ProjectionPayloadBuilder {
    static func build(
        task: TaskRecord,
        checkpoint: CheckpointRecord?,
        notes: [TaskNoteRecord],
        visibleFiles: [TaskFileRecord],
        hiddenFiles: [TaskFileRecord],
        repository: TaskRepositoryRecord?,
        supplement: TaskSupplementRecord?,
        contextPack: ContextPack?,
        gitActivity: GitActivitySnapshot? = nil,
        now: String
    ) throws -> ProjectionPayloads {
        let noteSummaries: [[String: Any]] = notes.map { note in
            [
                "id": note.id,
                "title": note.title,
                "updated_at": note.updatedAt,
                "read_tool": "read_context_material",
            ]
        }
        let fileSummaries: [[String: Any]] = visibleFiles.map { file in
            [
                "id": file.id,
                "display_name": file.displayName,
                "path": file.path,
                "file_type": file.fileType,
                "modified_at": file.modifiedAt,
                "visibility": "readable",
                "read_tool": "read_context_material",
            ]
        }
        let hiddenFileSummaries: [[String: Any]] = hiddenFiles.map { file in
            [
                "id": file.id,
                "display_name": file.displayName,
                "path": file.path,
                "file_type": file.fileType,
                "modified_at": file.modifiedAt,
                "visibility": "hidden",
                "read_tool": NSNull(),
            ]
        }

        let effectiveFreshness = contextPack?.freshness ?? "fresh"
        var activeObject: [String: Any] = [
            "task_id": task.id,
            "title": task.title,
            "goal": task.goal,
            "status": task.status,
            "effective_freshness": effectiveFreshness,
            "freshness_at_generation": effectiveFreshness,
            "last_verified_at": now,
        ]
        if let contextPack {
            activeObject["context_pack_id"] = contextPack.id
            activeObject["context_revision"] = contextPack.revision
        }
        let activePayload = try jsonString(activeObject)

        var manifestObject: [String: Any] = [
            "task": [
                "id": task.id,
                "title": task.title,
                "goal": task.goal,
                "status": task.status,
            ],
            "supplement": supplement?.body ?? "",
            "files": fileSummaries,
            "hidden_files": hiddenFileSummaries,
            "notes": noteSummaries,
            "available_tools": [
                "get_current_development_context", "read_context_material", "get_active_task", "get_task_manifest",
                "get_resume_brief", "read_task_note", "read_task_file",
            ],
        ]
        if let repository {
            manifestObject["repository"] = repoProjection(repository, activity: gitActivity)
        }
        if let gitActivity {
            manifestObject["workspace_activity"] = workspaceActivityProjection(gitActivity)
        }
        if let contextPack {
            manifestObject["context_pack"] = try contextPackObject(contextPack)
            manifestObject["source_index"] = sourceIndex(contextPack.sourceManifest)
        }
        let manifestPayload = try jsonString(manifestObject)

        let resolvedBrief =
            contextPack?.content.brief
            ?? resumeBrief(
                task: task,
                checkpoint: checkpoint,
                notes: notes,
                files: visibleFiles,
                repository: repository,
                supplement: supplement
            )
        var briefObject: [String: Any] = [
            "brief": resolvedBrief,
            "supplement": supplement?.body ?? "",
            "readable_files": fileSummaries,
            "readable_notes": noteSummaries,
        ]
        if let checkpoint {
            briefObject["checkpoint"] = [
                "current_state": checkpoint.currentState,
                "next_step": checkpoint.nextStep,
                "blockers": checkpoint.blockers,
                "created_at": checkpoint.createdAt,
            ]
        }
        if let repository {
            briefObject["repository"] = repoProjection(repository, activity: gitActivity)
        }
        if let contextPack {
            briefObject["context_pack_id"] = contextPack.id
            briefObject["context_revision"] = contextPack.revision
            briefObject["effective_freshness"] = contextPack.freshness
            briefObject["stale_reason"] = contextPack.staleReason ?? NSNull()
            briefObject["open_questions"] = contextPack.content.questions.map { question in
                [
                    "id": question.id,
                    "question": question.question,
                    "why_it_matters": question.whyItMatters,
                    "source_ids": question.sourceIDs,
                ] as [String: Any]
            }
            briefObject["source_index"] = sourceIndex(contextPack.sourceManifest)
        }
        let briefPayload = try jsonString(briefObject)

        return ProjectionPayloads(
            activePayload: activePayload,
            manifestPayload: manifestPayload,
            briefPayload: briefPayload
        )
    }

    private static func resumeBrief(
        task: TaskRecord,
        checkpoint: CheckpointRecord?,
        notes: [TaskNoteRecord],
        files: [TaskFileRecord],
        repository: TaskRepositoryRecord?,
        supplement: TaskSupplementRecord?
    ) -> String {
        var lines = ["Work: \(task.title)"]
        if !task.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Goal: \(task.goal)")
        }
        var includedDetails = Set<String>()

        func appendDetail(_ label: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let identity =
                trimmed
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .lowercased()
            guard includedDetails.insert(identity).inserted else { return }
            lines.append("\(label): \(trimmed)")
        }

        if let repository {
            lines.append("Repo: \(repository.path) [\(repository.branch)]")
        }
        if let supplement {
            appendDetail("Additional note", supplement.body)
        }
        if let checkpoint {
            appendDetail("Current", checkpoint.currentState)
            appendDetail("Next", checkpoint.nextStep)
            appendDetail("Blocked", checkpoint.blockers)
        }
        if !notes.isEmpty {
            lines.append("Readable notes: \(notes.map(\.title).joined(separator: ", "))")
        }
        if !files.isEmpty {
            lines.append("Readable files: \(files.map(\.displayName).joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private static func repoProjection(
        _ repo: TaskRepositoryRecord,
        activity: GitActivitySnapshot?
    ) -> [String: String] {
        [
            "path": repo.path,
            "branch": repo.branch,
            "current_branch": activity?.currentBranch ?? GitRepositoryReader.branch(at: repo.path),
            "dirty_state": activity.map { $0.dirtyPaths.isEmpty ? "clean" : "modified" }
                ?? GitRepositoryReader.dirtyState(at: repo.path).rawValue,
        ]
    }

    private static func workspaceActivityProjection(_ activity: GitActivitySnapshot) -> [String: Any] {
        [
            "state": activity.state.rawValue,
            "workspace": activity.workspacePath,
            "linked_branch": activity.linkedBranch,
            "current_branch": activity.currentBranch,
            "baseline_head": activity.baselineHeadSHA ?? NSNull(),
            "current_head": activity.currentHeadSHA ?? NSNull(),
            "commit_count": activity.commits.count,
            "changed_path_count": activity.committedPaths.count,
            "dirty_path_count": activity.dirtyPaths.count,
            "commits": activity.commits.prefix(10).map { commit in
                [
                    "sha": commit.sha,
                    "subject": commit.subject,
                    "committed_at": commit.committedAt,
                ]
            },
            "committed_paths": activity.committedPaths.prefix(20).map(changedPathProjection),
            "uncommitted_paths": activity.dirtyPaths.prefix(20).map(changedPathProjection),
            "provenance": "derived_from_git",
            "captured_at": activity.capturedAt,
        ]
    }

    private static func changedPathProjection(_ path: GitChangedPath) -> [String: Any] {
        [
            "status": path.status,
            "path": path.path,
            "previous_path": path.previousPath ?? NSNull(),
            "additions": path.additions ?? NSNull(),
            "deletions": path.deletions ?? NSNull(),
            "is_binary": path.isBinary,
        ]
    }

    private static func contextPackObject(_ pack: ContextPack) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(pack.content)
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        object["id"] = pack.id
        object["revision"] = pack.revision
        object["effective_freshness"] = pack.freshness
        object["stale_reason"] = pack.staleReason ?? NSNull()
        return object
    }

    private static func sourceIndex(_ references: [ContextSourceRef]) -> [[String: Any]] {
        references.map { source in
            var value: [String: Any] = [
                "id": source.id,
                "kind": source.kind,
                "title": source.title,
                "path": source.path ?? NSNull(),
                "updated_at": source.updatedAt,
                "content_hash": source.contentHash,
                "truncated": source.truncated,
            ]
            if source.kind == ContextPreparationService.clarificationAnswerKind,
                let inlineContent = source.inlineContent
            {
                value["confirmed_content"] = inlineContent
            }
            return value
        }
    }

    private static func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
