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

    func beginWorkspaceProvisioning() {
        guard selectedTaskID != nil else {
            showToast(l10n.nameYourWorkFirst)
            return
        }
        workspaceProvisioningError = ""
        showWorkspaceProvisioningSheet = true
    }

    func createIsolatedWorkspace(_ request: WorkspaceProvisioningRequest) {
        isProvisioningWorkspace = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await performStoreOperation { store in
                    try WorkspaceProvisioningService(store: store).create(request)
                }
                showWorkspaceProvisioningSheet = false
                showToast(l10n.workspaceCreated(result.workspace.path))
                refresh()
            } catch {
                workspaceProvisioningError = l10n.workspaceProvisioningErrorMessage(error)
                showToast(l10n.workspaceProvisioningErrorMessage(error))
                message = "Workspace provisioning error: \(error)"
            }
            isProvisioningWorkspace = false
        }
    }

    func copySelectedWorkspacePath() {
        guard let path = repository?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        showToast(l10n.copyWorkspacePath)
    }

    func revealSelectedWorkspace() {
        guard let path = repository?.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openSelectedWorkspaceInTerminal() {
        guard let path = repository?.path else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    func unlinkSelectedRepository() {
        guard let selectedTaskID else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.unlinkRepository(taskID: selectedTaskID)
                }
                showToast(l10n.workspaceUnlinked)
                refresh()
            } catch {
                showToast(l10n.workspaceUnlinkFailed)
                message = "Workspace unlink error: \(error)"
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
        guard let selectedTaskID, repository != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.refreshRepositoryAnchor(taskID: selectedTaskID)
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

    func refreshCurrentBranches() {
        gitRefreshTask?.cancel()
        let paths = Array(Set(taskRepositoriesByID.values.map(\.path))).sorted()
        guard !paths.isEmpty else {
            if !currentBranchesByRepo.isEmpty { currentBranchesByRepo = [:] }
            if !currentHeadsByRepo.isEmpty { currentHeadsByRepo = [:] }
            if !dirtyStatesByRepo.isEmpty { dirtyStatesByRepo = [:] }
            if !workingTreeSignaturesByRepo.isEmpty { workingTreeSignaturesByRepo = [:] }
            if currentGitActivity != nil { currentGitActivity = nil }
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
            let nextBranches = Dictionary(
                uniqueKeysWithValues: states.map { ($0.path, $0.branch) }
            )
            let nextHeads = Dictionary(
                uniqueKeysWithValues: states.compactMap { state in
                    state.headSHA.map { (state.path, $0) }
                }
            )
            let nextDirtyStates = Dictionary(
                uniqueKeysWithValues: states.map { ($0.path, $0.dirtyState) }
            )
            let nextWorkingTreeSignatures = Dictionary(
                uniqueKeysWithValues: states.map { ($0.path, $0.workingTreeSignature ?? "unavailable") }
            )
            if currentBranchesByRepo != nextBranches { currentBranchesByRepo = nextBranches }
            if currentHeadsByRepo != nextHeads { currentHeadsByRepo = nextHeads }
            if dirtyStatesByRepo != nextDirtyStates { dirtyStatesByRepo = nextDirtyStates }
            if workingTreeSignaturesByRepo != nextWorkingTreeSignatures {
                workingTreeSignaturesByRepo = nextWorkingTreeSignatures
            }
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

    func applyCachedGitState() {
        if let repository {
            let branch = currentBranchesByRepo[repository.path] ?? "-"
            let dirtyState = dirtyStatesByRepo[repository.path] ?? .unknown
            if selectedRepoCurrentBranch != branch { selectedRepoCurrentBranch = branch }
            if selectedRepoDirtyState != dirtyState { selectedRepoDirtyState = dirtyState }
        }
        if let assistantRepository {
            let branch = currentBranchesByRepo[assistantRepository.path] ?? "-"
            let dirtyState = dirtyStatesByRepo[assistantRepository.path] ?? .unknown
            if assistantCurrentBranch != branch { assistantCurrentBranch = branch }
            if assistantDirtyState != dirtyState { assistantDirtyState = dirtyState }
        }

    }
}
