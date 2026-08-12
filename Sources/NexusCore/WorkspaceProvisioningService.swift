import Foundation

public final class WorkspaceProvisioningService: @unchecked Sendable {
    private let store: ProjectionStore
    private let fileManager: FileManager

    public init(store: ProjectionStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    public func localBranches(repositoryRoot: String) throws -> [String] {
        let root = try validatedRepositoryRoot(repositoryRoot)
        let result = try runGit(
            at: root,
            arguments: ["for-each-ref", "--format=%(refname:short)", "refs/heads"]
        )
        return String(decoding: result.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
    }

    public func preview(_ request: WorkspaceProvisioningRequest) throws -> WorkspaceProvisioningPreview {
        let root = try validatedRepositoryRoot(request.repositoryRoot)
        let task = try store.task(id: request.taskID)
        guard task != nil else {
            throw WorkspaceProvisioningError.taskNotFound(request.taskID)
        }
        guard try store.repository(taskID: request.taskID) == nil else {
            throw WorkspaceProvisioningError.taskAlreadyLinked(request.taskID)
        }

        let normalizedDestination = WorkspacePath.normalize(request.destinationPath)
        guard !fileManager.fileExists(atPath: normalizedDestination) else {
            throw WorkspaceProvisioningError.destinationExists(normalizedDestination)
        }

        let workspacePaths = store.gitWorktrees(at: root).map { WorkspacePath.normalize($0.path) }
        guard !workspacePaths.contains(normalizedDestination) else {
            throw WorkspaceProvisioningError.destinationConflicts(normalizedDestination)
        }

        guard isValidBranchName(request.branchName) else {
            throw WorkspaceProvisioningError.invalidBranchName(request.branchName)
        }
        if branchExists(request.branchName, at: root) {
            if let checkedOutPath = store.gitWorktrees(at: root)
                .first(where: { $0.branch == request.branchName })?.path
            {
                throw WorkspaceProvisioningError.branchAlreadyCheckedOut(request.branchName, checkedOutPath)
            }
            throw WorkspaceProvisioningError.branchAlreadyExists(request.branchName)
        }
        guard refExists(request.baseRef, at: root) else {
            throw WorkspaceProvisioningError.baseRefUnavailable(request.baseRef)
        }

        let dirtyState = store.gitDirtyState(at: root)
        let warnings: [String]
        if dirtyState == .modified {
            warnings = ["The new workspace will start from HEAD and will not include uncommitted changes."]
        } else {
            warnings = []
        }
        return WorkspaceProvisioningPreview(
            repositoryRoot: root,
            baseRef: request.baseRef,
            branchName: request.branchName,
            destinationPath: normalizedDestination,
            currentHeadSHA: GitRepositoryReader.headSHA(at: root),
            dirtyState: dirtyState,
            warnings: warnings
        )
    }

    public func create(_ request: WorkspaceProvisioningRequest) throws -> WorkspaceProvisioningResult {
        let preview = try preview(request)
        if preview.dirtyState == .modified && !request.confirmedDirtyBase {
            throw WorkspaceProvisioningError.dirtyBaseRequiresConfirmation(preview.repositoryRoot)
        }

        let parent = URL(fileURLWithPath: preview.destinationPath).deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw WorkspaceProvisioningError.gitCommandFailed(
                command: "create destination parent",
                detail: error.localizedDescription
            )
        }

        _ = try runGit(
            at: preview.repositoryRoot,
            arguments: [
                "worktree", "add", "-b", preview.branchName,
                preview.destinationPath, preview.baseRef,
            ]
        )

        guard let workspace = GitRepositoryReader.workspaceInfo(at: preview.destinationPath) else {
            let cleanupSucceeded = removeCreatedWorktree(
                path: preview.destinationPath,
                repositoryRoot: preview.repositoryRoot
            )
            throw WorkspaceProvisioningError.persistenceFailed(
                cleanupPath: cleanupSucceeded ? nil : preview.destinationPath,
                detail: "Git created the directory, but Nexus could not read it."
            )
        }
        let createdHeadSHA = GitRepositoryReader.headSHA(at: workspace.path)
        do {
            try store.setRepository(
                taskID: request.taskID,
                path: workspace.path,
                workspaceOrigin: .nexusCreated,
                baseRef: preview.baseRef,
                createdHeadSHA: createdHeadSHA
            )
        } catch {
            let cleanupSucceeded = removeCreatedWorktree(path: workspace.path, repositoryRoot: preview.repositoryRoot)
            throw WorkspaceProvisioningError.persistenceFailed(
                cleanupPath: cleanupSucceeded ? nil : workspace.path,
                detail: error.localizedDescription
            )
        }

        return WorkspaceProvisioningResult(
            taskID: request.taskID,
            workspace: workspace,
            branchName: preview.branchName,
            baseRef: preview.baseRef,
            createdHeadSHA: createdHeadSHA
        )
    }

    public static func defaultDestination(
        repositoryRoot: String,
        workTitle: String,
        taskID: String
    ) -> String {
        let root = WorkspacePath.normalize(repositoryRoot)
        let repositoryURL = URL(fileURLWithPath: root)
        let repositoryName = repositoryURL.lastPathComponent.isEmpty ? "repository" : repositoryURL.lastPathComponent
        let parent = repositoryURL.deletingLastPathComponent()
        let slug = slugify(workTitle)
        let shortID = taskID.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let leaf = "\(slug.isEmpty ? "work" : slug)-\(shortID)"
        let worktreeRoot =
            parent
            .appendingPathComponent(".nexus-worktrees", isDirectory: true)
            .appendingPathComponent(repositoryName, isDirectory: true)
        return worktreeRoot.appendingPathComponent(leaf, isDirectory: true).path
    }

    public static func defaultBranchName(workTitle: String, taskID: String) -> String {
        let slug = slugify(workTitle)
        guard !slug.isEmpty else {
            let shortID = String(taskID.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
            return "nexus/work-\(shortID)"
        }
        return "nexus/\(slug)"
    }

    private func validatedRepositoryRoot(_ path: String) throws -> String {
        let normalized = WorkspacePath.normalize(path)
        guard fileManager.fileExists(atPath: normalized),
            let workspace = GitRepositoryReader.workspaceInfo(at: normalized)
        else {
            throw WorkspaceProvisioningError.notGitRepository(normalized)
        }
        return workspace.repositoryRoot
    }

    private func branchExists(_ branch: String, at root: String) -> Bool {
        do {
            _ = try runGit(at: root, arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"])
            return true
        } catch {
            return false
        }
    }

    private func refExists(_ ref: String, at root: String) -> Bool {
        do {
            _ = try runGit(at: root, arguments: ["rev-parse", "--verify", "\(ref)^{commit}"])
            return true
        } catch {
            return false
        }
    }

    private func isValidBranchName(_ branch: String) -> Bool {
        guard !branch.isEmpty, !branch.contains("\0") else { return false }
        do {
            _ = try runGit(at: nil, arguments: ["check-ref-format", "--branch", branch])
            return true
        } catch {
            return false
        }
    }

    private func removeCreatedWorktree(path: String, repositoryRoot: String) -> Bool {
        do {
            _ = try runGit(at: repositoryRoot, arguments: ["worktree", "remove", "--force", path])
            return true
        } catch {
            return false
        }
    }

    private func runGit(at directory: String?, arguments: [String]) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = directory.map { ["-C", $0] + arguments } ?? arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let result = GitCommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
            guard result.status == 0 else {
                let detail = String(decoding: stderr, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw WorkspaceProvisioningError.gitCommandFailed(
                    command: (["git"] + (process.arguments ?? arguments)).joined(separator: " "),
                    detail: detail.isEmpty ? "exit status \(result.status)" : detail
                )
            }
            return result
        } catch let error as WorkspaceProvisioningError {
            throw error
        } catch {
            throw WorkspaceProvisioningError.gitCommandFailed(
                command: (["git"] + (process.arguments ?? arguments)).joined(separator: " "),
                detail: error.localizedDescription
            )
        }
    }

    private static func slugify(_ title: String) -> String {
        let ascii = title.unicodeScalars.map { scalar -> Character in
            let isASCIIAlphaNumeric =
                (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
            if isASCIIAlphaNumeric { return Character(String(scalar).lowercased()) }
            return "-"
        }
        let value = String(ascii)
            .split(separator: "-")
            .joined(separator: "-")
        return String(value.prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private struct GitCommandResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}
