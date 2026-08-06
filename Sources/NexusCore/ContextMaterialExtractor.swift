import CryptoKit
import Foundation

public enum ContextMaterialExtractor {
    public static let perSourceCharacterLimit = 40_000
    public static let totalCharacterLimit = 120_000
    public static let gitActivityCharacterLimit = 30_000
    public static let committedGitActivityKind = "git_committed"
    public static let uncommittedGitActivityKind = "git_uncommitted"
    static let repositoryFingerprintVersion = 2

    private static let supportedExtensions: Set<String> = [
        "c", "cc", "conf", "cpp", "csv", "go", "h", "hpp", "ini", "java", "js", "json", "jsonl",
        "jsx", "kt", "kts", "log", "md", "markdown", "mjs", "mm", "py", "rb", "rs", "sh", "sql",
        "swift", "toml", "ts", "tsx", "txt", "xml", "yaml", "yml", "zsh",
    ]

    public static func prepare(
        task: TaskRecord,
        baseRevision: Int64,
        supplement: TaskSupplementRecord?,
        notes: [TaskNoteRecord],
        files: [TaskFileRecord],
        repository: TaskRepositoryRecord?,
        gitActivity: GitActivitySnapshot? = nil
    ) throws -> ContextPreparationInput {
        var candidates: [Candidate] = []
        var excluded: [ContextSourceExclusion] = []

        let taskContent = [
            "Title: \(task.title)",
            task.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Goal: \(task.goal)",
        ].compactMap { $0 }.joined(separator: "\n")
        candidates.append(
            Candidate(
                id: "work:\(task.id)",
                kind: "work",
                title: task.title,
                path: nil,
                updatedAt: task.updatedAt,
                content: taskContent
            )
        )

        if let supplement, !supplement.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(
                Candidate(
                    id: "handoff:\(task.id)",
                    kind: "handoff",
                    title: "Handoff",
                    path: nil,
                    updatedAt: supplement.updatedAt,
                    content: supplement.body
                )
            )
        }

        if let repository {
            let repositoryRoot =
                GitRepositoryReader.workspaceInfo(at: repository.path)?.repositoryRoot
                ?? WorkspacePath.normalize(repository.path)
            let repoContent = [
                "Workspace: \(WorkspacePath.normalize(repository.path))",
                "Repository root: \(WorkspacePath.normalize(repositoryRoot))",
                "Linked branch: \(repository.branch)",
            ].joined(separator: "\n")
            candidates.append(
                Candidate(
                    id: "repository:\(task.id)",
                    kind: "repository",
                    title: URL(fileURLWithPath: repository.path).lastPathComponent,
                    path: repository.path,
                    updatedAt: repository.updatedAt,
                    content: repoContent
                )
            )
        }

        for note in notes.sorted(by: stableNoteSort) {
            let id = "note:\(note.id)"
            guard note.isExposedToMCP else {
                excluded.append(ContextSourceExclusion(id: id, title: note.title, path: nil, reason: .hidden))
                continue
            }
            candidates.append(
                Candidate(
                    id: id,
                    kind: "note",
                    title: note.title,
                    path: nil,
                    updatedAt: note.updatedAt,
                    content: note.body
                )
            )
        }

        for file in files.sorted(by: stableFileSort) {
            let id = "file:\(file.id)"
            guard file.isVisibleToAgent else {
                excluded.append(
                    ContextSourceExclusion(id: id, title: file.displayName, path: file.path, reason: .hidden))
                continue
            }
            let url = URL(fileURLWithPath: file.path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else {
                excluded.append(
                    ContextSourceExclusion(id: id, title: file.displayName, path: file.path, reason: .missing))
                continue
            }
            guard !isDirectory.boolValue else {
                excluded.append(
                    ContextSourceExclusion(id: id, title: file.displayName, path: file.path, reason: .directory))
                continue
            }
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                excluded.append(
                    ContextSourceExclusion(id: id, title: file.displayName, path: file.path, reason: .unsupportedType))
                continue
            }
            guard let content = decodedString(at: url) else {
                excluded.append(
                    ContextSourceExclusion(id: id, title: file.displayName, path: file.path, reason: .unreadable))
                continue
            }
            candidates.append(
                Candidate(
                    id: id,
                    kind: "file",
                    title: file.displayName,
                    path: file.path,
                    updatedAt: file.modifiedAt,
                    content: content
                )
            )
        }

        if let gitActivity {
            candidates.append(
                Candidate(
                    id: "git:committed:\(task.id)",
                    kind: committedGitActivityKind,
                    title: "Committed code changes",
                    path: gitActivity.workspacePath,
                    updatedAt: gitActivity.capturedAt,
                    content: GitActivityContextFormatter.committedContent(gitActivity),
                    characterLimit: gitActivity.dirtyPaths.isEmpty ? gitActivityCharacterLimit : 20_000
                )
            )
            if !gitActivity.dirtyPaths.isEmpty {
                candidates.append(
                    Candidate(
                        id: "git:uncommitted:\(task.id)",
                        kind: uncommittedGitActivityKind,
                        title: "Uncommitted workspace changes",
                        path: gitActivity.workspacePath,
                        updatedAt: gitActivity.capturedAt,
                        content: GitActivityContextFormatter.uncommittedContent(gitActivity),
                        characterLimit: 10_000
                    )
                )
            }
        }

        var remaining = totalCharacterLimit
        var remainingGitActivity = gitActivityCharacterLimit
        var sources: [ContextSourceDocument] = []
        for candidate in candidates {
            guard remaining > 0 else {
                excluded.append(
                    ContextSourceExclusion(
                        id: candidate.id, title: candidate.title, path: candidate.path, reason: .budgetExceeded))
                continue
            }
            let fullCount = candidate.content.count
            let isGitActivity = Self.isGitActivityKind(candidate.kind)
            let sourceLimit = candidate.characterLimit ?? perSourceCharacterLimit
            let allowed =
                isGitActivity
                ? min(sourceLimit, remaining, remainingGitActivity)
                : min(sourceLimit, remaining)
            guard allowed > 0 else {
                excluded.append(
                    ContextSourceExclusion(
                        id: candidate.id,
                        title: candidate.title,
                        path: candidate.path,
                        reason: .budgetExceeded
                    )
                )
                continue
            }
            let included = truncate(candidate.content, limit: allowed)
            let includedCount = included.count
            let reference = ContextSourceRef(
                id: candidate.id,
                kind: candidate.kind,
                title: candidate.title,
                path: candidate.path,
                updatedAt: candidate.updatedAt,
                contentHash: sha256(candidate.content),
                characterCount: fullCount,
                includedCharacterCount: includedCount,
                truncated: includedCount < fullCount,
                fingerprintVersion: candidate.kind == "repository" ? repositoryFingerprintVersion : nil
            )
            sources.append(ContextSourceDocument(reference: reference, content: included))
            remaining -= includedCount
            if isGitActivity {
                remainingGitActivity -= includedCount
            }
        }

        guard !sources.isEmpty else {
            throw ContextPreparationError.noReadableSources
        }
        return ContextPreparationInput(
            taskID: task.id,
            baseRevision: baseRevision,
            sources: sources,
            excludedSources: excluded,
            totalIncludedCharacters: sources.reduce(0) { $0 + $1.reference.includedCharacterCount }
        )
    }

    public static func manifestFingerprint(_ references: [ContextSourceRef]) -> String {
        let canonical =
            references
            .sorted { $0.id < $1.id }
            .map { "\($0.id)|\($0.contentHash)|\($0.includedCharacterCount)|\($0.truncated)" }
            .joined(separator: "\n")
        return sha256(canonical)
    }

    static func isGitActivityKind(_ kind: String) -> Bool {
        kind == committedGitActivityKind || kind == uncommittedGitActivityKind
    }

    private struct Candidate {
        let id: String
        let kind: String
        let title: String
        let path: String?
        let updatedAt: String
        let content: String
        let characterLimit: Int?

        init(
            id: String,
            kind: String,
            title: String,
            path: String?,
            updatedAt: String,
            content: String,
            characterLimit: Int? = nil
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.path = path
            self.updatedAt = updatedAt
            self.content = content
            self.characterLimit = characterLimit
        }
    }

    private static func decodedString(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if data.prefix(min(data.count, 8_192)).contains(0) {
            return nil
        }
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let value = String(data: data, encoding: encoding) {
                return value
            }
        }
        return nil
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard limit > 0, text.count > limit else { return limit > 0 ? text : "" }
        let marker = "\n\n[... Nexus omitted middle content ...]\n\n"
        guard limit > marker.count + 1 else {
            return String(text.prefix(limit))
        }
        let availableContentCount = limit - marker.count
        let tailCount =
            limit >= perSourceCharacterLimit
            ? min(10_000, availableContentCount / 2)
            : max(1, availableContentCount / 4)
        let headCount = availableContentCount - tailCount
        return String(text.prefix(headCount)) + marker + String(text.suffix(tailCount))
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func stableNoteSort(_ lhs: TaskNoteRecord, _ rhs: TaskNoteRecord) -> Bool {
        if lhs.title != rhs.title { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func stableFileSort(_ lhs: TaskFileRecord, _ rhs: TaskFileRecord) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}
