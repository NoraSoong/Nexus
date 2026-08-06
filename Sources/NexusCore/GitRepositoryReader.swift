import Foundation

enum GitRepositoryReader {
    static let diffCharacterLimit = 30_000

    static func branch(at path: String) -> String {
        guard let value = output(["-C", path, "branch", "--show-current"]) else {
            return "(unknown)"
        }
        return value.isEmpty ? "(detached)" : value
    }

    static func headSHA(at path: String) -> String? {
        let value = output(["-C", path, "rev-parse", "--verify", "HEAD"])
        return value?.isEmpty == false ? value : nil
    }

    static func dirtyState(at path: String) -> GitWorkingTreeState {
        workingTreeStatus(at: path).state
    }

    static func pathState(at path: String) -> GitPathState {
        let workingTree = workingTreeStatus(at: path)
        return GitPathState(
            path: path,
            branch: branch(at: path),
            headSHA: headSHA(at: path),
            dirtyState: workingTree.state,
            workingTreeSignature: workingTree.signature
        )
    }

    static func workspaceInfo(at path: String) -> GitWorkspaceInfo? {
        let workspacePath = WorkspacePath.normalize(path)
        guard let topLevel = output(["-C", workspacePath, "rev-parse", "--show-toplevel"]),
            let commonDirectory = absoluteGitPath(
                output(["-C", workspacePath, "rev-parse", "--path-format=absolute", "--git-common-dir"]),
                relativeTo: workspacePath
            ),
            let gitDirectory = absoluteGitPath(
                output(["-C", workspacePath, "rev-parse", "--path-format=absolute", "--git-dir"]),
                relativeTo: workspacePath
            )
        else {
            return nil
        }

        let normalizedCommon = WorkspacePath.normalize(commonDirectory)
        let normalizedGit = WorkspacePath.normalize(gitDirectory)
        let repositoryRoot: String
        if URL(fileURLWithPath: normalizedCommon).lastPathComponent == ".git" {
            repositoryRoot = URL(fileURLWithPath: normalizedCommon).deletingLastPathComponent().path
        } else {
            repositoryRoot = WorkspacePath.normalize(topLevel)
        }

        return GitWorkspaceInfo(
            path: WorkspacePath.normalize(topLevel),
            branch: branch(at: workspacePath),
            repositoryRoot: repositoryRoot,
            commonDirectory: normalizedCommon,
            kind: normalizedGit == normalizedCommon ? "main" : "worktree"
        )
    }

    static func worktrees(at path: String) -> [GitWorkspaceInfo] {
        guard let value = output(["-C", path, "worktree", "list", "--porcelain"]) else {
            return []
        }
        var seen: Set<String> = []
        return
            value
            .components(separatedBy: "\n\n")
            .compactMap { block -> GitWorkspaceInfo? in
                guard let line = block.split(separator: "\n").first,
                    line.hasPrefix("worktree ")
                else {
                    return nil
                }
                let workspacePath = String(line.dropFirst("worktree ".count))
                guard let info = workspaceInfo(at: workspacePath),
                    seen.insert(info.path).inserted
                else {
                    return nil
                }
                return info
            }
            .sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
    }

    static func activity(
        repository: TaskRepositoryRecord,
        baseline: GitContextBaseline?,
        includeCommittedDiff: Bool,
        includeUncommittedDiff: Bool,
        capturedAt: String
    ) -> GitActivitySnapshot {
        let path = repository.path
        let currentBranch = branch(at: path)
        let currentHead = headSHA(at: path)
        let dirtyPaths = workingTreePaths(at: path)

        guard workspaceInfo(at: path) != nil, let currentHead else {
            return snapshot(
                repository: repository,
                currentBranch: currentBranch,
                baseline: baseline,
                currentHead: currentHead,
                state: .unavailable,
                dirtyPaths: dirtyPaths,
                capturedAt: capturedAt
            )
        }
        guard currentBranch == repository.branch else {
            return snapshot(
                repository: repository,
                currentBranch: currentBranch,
                baseline: baseline,
                currentHead: currentHead,
                state: .branchMismatch,
                dirtyPaths: dirtyPaths,
                capturedAt: capturedAt
            )
        }
        guard let baseline else {
            return snapshot(
                repository: repository,
                currentBranch: currentBranch,
                baseline: nil,
                currentHead: currentHead,
                state: .noBaseline,
                dirtyPaths: dirtyPaths,
                capturedAt: capturedAt
            )
        }
        guard baseline.workspacePath == WorkspacePath.normalize(path),
            baseline.branch == repository.branch
        else {
            return snapshot(
                repository: repository,
                currentBranch: currentBranch,
                baseline: baseline,
                currentHead: currentHead,
                state: .branchMismatch,
                dirtyPaths: dirtyPaths,
                capturedAt: capturedAt
            )
        }
        guard baseline.headSHA != currentHead else {
            return snapshot(
                repository: repository,
                currentBranch: currentBranch,
                baseline: baseline,
                currentHead: currentHead,
                state: .current,
                dirtyPaths: dirtyPaths,
                uncommittedDiff: includeUncommittedDiff ? workingTreeDiff(at: path) : nil,
                capturedAt: capturedAt
            )
        }
        guard isAncestor(baseline.headSHA, of: currentHead, at: path) == true else {
            return snapshot(
                repository: repository,
                currentBranch: currentBranch,
                baseline: baseline,
                currentHead: currentHead,
                state: .historyRewritten,
                dirtyPaths: dirtyPaths,
                capturedAt: capturedAt
            )
        }

        return GitActivitySnapshot(
            workspacePath: WorkspacePath.normalize(path),
            linkedBranch: repository.branch,
            currentBranch: currentBranch,
            baselineHeadSHA: baseline.headSHA,
            currentHeadSHA: currentHead,
            state: .commitsAvailable,
            commits: commitSummaries(fromExclusive: baseline.headSHA, toInclusive: currentHead, at: path),
            committedPaths: changedPaths(fromExclusive: baseline.headSHA, toInclusive: currentHead, at: path),
            dirtyPaths: dirtyPaths,
            committedDiff: includeCommittedDiff
                ? diff(fromExclusive: baseline.headSHA, toInclusive: currentHead, at: path)
                : nil,
            uncommittedDiff: includeUncommittedDiff ? workingTreeDiff(at: path) : nil,
            capturedAt: capturedAt
        )
    }

    static func commitSummaries(
        fromExclusive baseline: String,
        toInclusive head: String,
        at path: String,
        limit: Int = 100
    ) -> [GitCommitSummary] {
        guard limit > 0,
            let value = output(
                [
                    "-C", path, "log", "--max-count=\(limit)", "--format=%H%x00%aI%x00%s%x1e",
                    "\(baseline)..\(head)",
                ],
                trimming: false
            )
        else {
            return []
        }

        return value.split(separator: "\u{1e}").compactMap { record in
            let fields =
                record
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\u{0}", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { return nil }
            return GitCommitSummary(
                sha: String(fields[0]),
                subject: String(fields[2]),
                committedAt: String(fields[1])
            )
        }
    }

    static func changedPaths(
        fromExclusive baseline: String,
        toInclusive head: String,
        at path: String
    ) -> [GitChangedPath] {
        guard
            let data = outputData(
                ["-C", path, "diff", "--name-status", "-z", "--find-renames", baseline, head]
            )
        else {
            return []
        }
        let stats = numstat(fromExclusive: baseline, toInclusive: head, at: path)
        let tokens = data.split(separator: 0, omittingEmptySubsequences: true).map {
            String(decoding: $0, as: UTF8.self)
        }
        var result: [GitChangedPath] = []
        var index = 0
        while index + 1 < tokens.count {
            let status = tokens[index]
            index += 1
            let firstPath = tokens[index]
            index += 1
            let isMove = status.hasPrefix("R") || status.hasPrefix("C")
            let previousPath = isMove ? firstPath : nil
            let currentPath: String
            if isMove, index < tokens.count {
                currentPath = tokens[index]
                index += 1
            } else {
                currentPath = firstPath
            }
            let stat = stats[currentPath]
            result.append(
                GitChangedPath(
                    status: status,
                    path: currentPath,
                    previousPath: previousPath,
                    additions: stat?.additions,
                    deletions: stat?.deletions,
                    isBinary: stat?.isBinary ?? false
                )
            )
        }
        return result.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    static func workingTreePaths(at path: String) -> [GitChangedPath] {
        guard let data = outputData(["-C", path, "status", "--porcelain=v1", "-z"]) else {
            return []
        }
        let tokens = data.split(separator: 0, omittingEmptySubsequences: true).map {
            String(decoding: $0, as: UTF8.self)
        }
        var result: [GitChangedPath] = []
        var index = 0
        while index < tokens.count {
            let entry = tokens[index]
            index += 1
            guard entry.count >= 4 else { continue }
            let status = String(entry.prefix(2))
            let currentPath = String(entry.dropFirst(3))
            var previousPath: String?
            if status.contains("R") || status.contains("C"), index < tokens.count {
                previousPath = tokens[index]
                index += 1
            }
            result.append(
                GitChangedPath(
                    status: status.trimmingCharacters(in: .whitespaces),
                    path: currentPath,
                    previousPath: previousPath
                )
            )
        }
        return result.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    private static func workingTreeStatus(at path: String) -> (
        state: GitWorkingTreeState,
        signature: String?
    ) {
        guard let data = outputData(["-C", path, "status", "--porcelain=v1", "-z"]) else {
            return (.unknown, nil)
        }
        return (
            data.isEmpty ? .clean : .modified,
            data.base64EncodedString()
        )
    }

    private static func snapshot(
        repository: TaskRepositoryRecord,
        currentBranch: String,
        baseline: GitContextBaseline?,
        currentHead: String?,
        state: GitActivityState,
        dirtyPaths: [GitChangedPath],
        committedDiff: String? = nil,
        uncommittedDiff: String? = nil,
        capturedAt: String
    ) -> GitActivitySnapshot {
        GitActivitySnapshot(
            workspacePath: WorkspacePath.normalize(repository.path),
            linkedBranch: repository.branch,
            currentBranch: currentBranch,
            baselineHeadSHA: baseline?.headSHA,
            currentHeadSHA: currentHead,
            state: state,
            commits: [],
            committedPaths: [],
            dirtyPaths: dirtyPaths,
            committedDiff: committedDiff,
            uncommittedDiff: uncommittedDiff,
            capturedAt: capturedAt
        )
    }

    private static func isAncestor(_ baseline: String, of head: String, at path: String) -> Bool? {
        let result = run(["-C", path, "merge-base", "--is-ancestor", baseline, head])
        switch result.status {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    private static func diff(fromExclusive baseline: String, toInclusive head: String, at path: String) -> String? {
        guard
            let value = output(
                [
                    "-C", path, "diff", "--no-ext-diff", "--no-color", "--unified=3", "--find-renames",
                    baseline, head,
                ],
                trimming: false
            ), !value.isEmpty
        else {
            return nil
        }
        return truncate(value, limit: diffCharacterLimit)
    }

    private static func workingTreeDiff(at path: String) -> String? {
        let unstaged =
            output(
                ["-C", path, "diff", "--no-ext-diff", "--no-color", "--unified=3"],
                trimming: false
            ) ?? ""
        let staged =
            output(
                ["-C", path, "diff", "--cached", "--no-ext-diff", "--no-color", "--unified=3"],
                trimming: false
            ) ?? ""
        let combined = [staged, unstaged].filter { !$0.isEmpty }.joined(separator: "\n")
        return combined.isEmpty ? nil : truncate(combined, limit: diffCharacterLimit)
    }

    private struct FileStat {
        let additions: Int?
        let deletions: Int?
        let isBinary: Bool
    }

    private static func numstat(
        fromExclusive baseline: String,
        toInclusive head: String,
        at path: String
    ) -> [String: FileStat] {
        guard
            let value = output(
                ["-C", path, "diff", "--numstat", "--find-renames", baseline, head],
                trimming: false
            )
        else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: value.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard fields.count == 3 else { return nil }
                let additions = Int(fields[0])
                let deletions = Int(fields[1])
                return (
                    String(fields[2]),
                    FileStat(
                        additions: additions,
                        deletions: deletions,
                        isBinary: additions == nil || deletions == nil
                    )
                )
            }
        )
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let marker = "\n\n[... Nexus omitted remaining diff ...]\n"
        return String(text.prefix(max(0, limit - marker.count))) + marker
    }

    private static func absoluteGitPath(_ value: String?, relativeTo workspacePath: String) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return value
        }
        return URL(fileURLWithPath: workspacePath).appendingPathComponent(value).path
    }

    private static func output(_ arguments: [String], trimming: Bool = true) -> String? {
        let result = run(arguments)
        guard result.status == 0 else { return nil }
        let value = String(decoding: result.stdout, as: UTF8.self)
        return trimming ? value.trimmingCharacters(in: .whitespacesAndNewlines) : value
    }

    private static func outputData(_ arguments: [String]) -> Data? {
        let result = run(arguments)
        return result.status == 0 ? result.stdout : nil
    }

    private static func run(_ arguments: [String]) -> (status: Int32, stdout: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        } catch {
            return (-1, Data())
        }
    }
}
