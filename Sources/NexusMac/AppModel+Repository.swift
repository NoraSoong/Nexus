import AppKit
import Foundation
import NexusCore

@MainActor
extension AppModel {
    func refreshAvailableWorktrees(for group: SidebarProjectGroup) {
        let linkedPaths = Set(taskRepositoriesByID.values.map { WorkspacePath.normalize($0.path) })
        let projectID = group.id
        let projectPath = group.path
        Task { @MainActor [weak self] in
            guard let self else { return }
            let worktrees =
                (try? await NexusBackgroundWork.run(priority: .utility) { [store] in
                    store.gitWorktrees(at: projectPath)
                }) ?? []
            let available = worktrees.filter {
                $0.commonDirectory == projectID && !linkedPaths.contains(WorkspacePath.normalize($0.path))
            }
            availableWorktreesByProjectID[projectID] = available
        }
    }

    func createWork(from workspace: GitWorkspaceInfo, projectID: String) {
        let title = workTitle(for: workspace)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let task = try await performStoreOperation { store in
                    try store.createTask(title: title, goal: "", workspacePath: workspace.path)
                }
                selectedTaskID = task.id
                showToast(l10n.workCreatedFromWorkspace)
                refresh()
                refreshProjectWorktrees(projectID)
            } catch {
                showToast(
                    l10n.workspaceAssociationErrorMessage(
                        error,
                        existingWorkTitle: existingWorkTitle(for: error)
                    )
                )
                message = "Create work from workspace error: \(error)"
            }
        }
    }

    func bindWorkspace(_ workspace: GitWorkspaceInfo, to task: TaskRecord, projectID: String) {
        guard taskRepositoriesByID[task.id] == nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.setRepository(taskID: task.id, path: workspace.path)
                }
                selectedTaskID = task.id
                showToast(l10n.workspaceLinked)
                refresh()
                refreshProjectWorktrees(projectID)
            } catch {
                showToast(
                    l10n.workspaceAssociationErrorMessage(
                        error,
                        existingWorkTitle: existingWorkTitle(for: error)
                    )
                )
                message = "Bind workspace error: \(error)"
            }
        }
    }

    func chooseRepository() {
        guard let selectedTaskID else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = l10n.chooseGitRepository
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await performStoreOperation { store in
                        try store.setRepository(taskID: selectedTaskID, path: path)
                    }
                    showToast(l10n.repositoryLinked)
                    refresh()
                    updateGitSuggestion()
                } catch {
                    showToast(
                        l10n.workspaceAssociationErrorMessage(
                            error,
                            existingWorkTitle: existingWorkTitle(for: error)
                        )
                    )
                    message = "Repository error: \(error)"
                }
            }
        }
    }

    private func existingWorkTitle(for error: Error) -> String? {
        let taskID: String?
        switch error {
        case let associationError as WorkspaceAssociationError:
            switch associationError {
            case .alreadyBound(_, let existingTaskID), .alreadyLinked(_, let existingTaskID):
                taskID = existingTaskID
            default:
                taskID = nil
            }
        default:
            taskID = nil
        }
        return taskID.flatMap { existingTaskID in
            tasks.first(where: { $0.id == existingTaskID })?.title
        }
    }

    func relinkSelectedRepositoryBranch() {
        guard let selectedTaskID, let repository else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.setRepository(taskID: selectedTaskID, path: repository.path)
                }
                showToast(l10n.branchLinked)
                refresh()
            } catch {
                showToast(
                    l10n.workspaceAssociationErrorMessage(
                        error,
                        existingWorkTitle: existingWorkTitle(for: error)
                    )
                )
                message = "Repository error: \(error)"
            }
        }
    }

    func switchToSuggestedGitTask() {
        guard let suggestion = gitSuggestion,
            let task = tasks.first(where: { $0.id == suggestion.taskID })
        else {
            return
        }
        switchTo(task)
        gitSuggestion = nil
    }

    func dismissGitSuggestion() {
        dismissedGitSuggestionKey = gitSuggestion.map { "\($0.repositoryPath)|\($0.branch)|\($0.taskID)" }
        gitSuggestion = nil
    }

    func startGitMonitor() {
        guard gitMonitorTask == nil else { return }
        gitMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.refreshCurrentBranches()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func updateGitSuggestion() {
        refreshCurrentBranches()
    }

    func refreshCurrentBranches() {
        gitRefreshTask?.cancel()
        let paths = Array(Set(taskRepositoriesByID.values.map(\.path))).sorted()
        guard !paths.isEmpty else {
            currentBranchesByRepo = [:]
            currentHeadsByRepo = [:]
            dirtyStatesByRepo = [:]
            workingTreeSignaturesByRepo = [:]
            currentGitActivity = nil
            applyCachedGitState()
            return
        }
        gitRefreshTask = Task { @MainActor [weak self, paths] in
            let states =
                (try? await NexusBackgroundWork.run(priority: .utility) {
                    ProjectionStore.gitPathStates(at: paths)
                }) ?? []
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let previousBranches = currentBranchesByRepo
            let previousHeads = currentHeadsByRepo
            let previousDirtyStates = dirtyStatesByRepo
            let previousWorkingTreeSignatures = workingTreeSignaturesByRepo
            currentBranchesByRepo = Dictionary(
                uniqueKeysWithValues: states.map { ($0.path, $0.branch) }
            )
            currentHeadsByRepo = Dictionary(
                uniqueKeysWithValues: states.compactMap { state in
                    state.headSHA.map { (state.path, $0) }
                }
            )
            dirtyStatesByRepo = Dictionary(
                uniqueKeysWithValues: states.map { ($0.path, $0.dirtyState) }
            )
            workingTreeSignaturesByRepo = Dictionary(
                uniqueKeysWithValues: states.map { ($0.path, $0.workingTreeSignature ?? "unavailable") }
            )
            applyCachedGitState()
            let changedPaths = Set(
                states.filter { state in
                    previousBranches[state.path] != state.branch
                        || previousHeads[state.path] != state.headSHA
                        || previousDirtyStates[state.path] != state.dirtyState
                        || previousWorkingTreeSignatures[state.path] != (state.workingTreeSignature ?? "unavailable")
                }.map(\.path)
            )
            let changedTaskIDs = Set(
                taskRepositoriesByID.values.compactMap { repository in
                    changedPaths.contains(repository.path) ? repository.taskID : nil
                }
            )
            if !changedTaskIDs.isEmpty {
                do {
                    let refreshedTaskIDs = try await performStoreOperation(priority: .utility) { store in
                        try store.refreshWorkspaceActivity(taskIDs: Array(changedTaskIDs))
                    }
                    guard !Task.isCancelled else { return }
                    if let selectedTaskID, refreshedTaskIDs.contains(selectedTaskID) {
                        refreshSelectedGitActivity()
                        refreshProjectionPreview()
                    }
                    if let activeTaskID, refreshedTaskIDs.contains(activeTaskID) {
                        refreshAssistantView()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    message = "Workspace activity refresh error: \(error)"
                }
            }
        }
    }

    func refreshSelectedGitActivity() {
        gitActivityRefreshTask?.cancel()
        guard let taskID = selectedTaskID, repository != nil else {
            currentGitActivity = nil
            return
        }
        gitActivityRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let activity = try? await performStoreOperation(priority: .utility) { store in
                try store.gitActivity(taskID: taskID)
            }
            guard !Task.isCancelled, selectedTaskID == taskID else { return }
            currentGitActivity = activity
        }
    }

    private func refreshProjectWorktrees(_ projectID: String) {
        guard let group = sidebarProjectGroups.first(where: { $0.id == projectID }) else {
            availableWorktreesByProjectID.removeValue(forKey: projectID)
            return
        }
        refreshAvailableWorktrees(for: group)
    }

    private func workTitle(for workspace: GitWorkspaceInfo) -> String {
        let branchName =
            workspace.branch == "(detached)"
            ? URL(fileURLWithPath: workspace.path).lastPathComponent
            : workspace.branch.split(separator: "/").last.map(String.init) ?? workspace.branch
        let words =
            branchName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return words.isEmpty ? URL(fileURLWithPath: workspace.path).lastPathComponent : words
    }

    private func applyCachedGitState() {
        if let repository {
            selectedRepoCurrentBranch = currentBranchesByRepo[repository.path] ?? "-"
            selectedRepoDirtyState = dirtyStatesByRepo[repository.path] ?? .unknown
        }
        if let assistantRepository {
            assistantCurrentBranch = currentBranchesByRepo[assistantRepository.path] ?? "-"
            assistantDirtyState = dirtyStatesByRepo[assistantRepository.path] ?? .unknown
        }

        let repositories = Array(taskRepositoriesByID.values)
        guard !repositories.isEmpty else {
            gitSuggestion = nil
            return
        }
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for path in Set(repositories.map(\.path)).sorted() {
            guard let currentBranch = currentBranchesByRepo[path],
                currentBranch != "(unknown)"
            else {
                continue
            }
            let matches = repositories.filter { repo in
                repo.path == path
                    && repo.branch == currentBranch
                    && repo.taskID != activeTaskID
                    && repo.taskID != selectedTaskID
            }
            guard let match = matches.first, let task = taskByID[match.taskID] else {
                continue
            }
            let key = "\(path)|\(currentBranch)|\(match.taskID)"
            guard dismissedGitSuggestionKey != key else {
                continue
            }
            gitSuggestion = GitBranchSuggestion(
                taskID: match.taskID,
                taskTitle: task.title,
                repositoryPath: path,
                branch: currentBranch
            )
            return
        }
        gitSuggestion = nil
    }
}
