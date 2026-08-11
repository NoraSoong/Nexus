import Foundation
import NexusCore
import SwiftUI

private struct AppRefreshData: Sendable {
    let tasks: [TaskRecord]
    let repositories: [TaskRepositoryRecord]
    let workspaceBindings: [ContextBindingRecord]
    let workspaceInfoByTaskID: [String: GitWorkspaceInfo]
    let activeTask: ActiveTaskProjection?
}

private struct SelectedTaskData: Sendable {
    let files: [TaskFileRecord]
    let notes: [TaskNoteRecord]
    let repository: TaskRepositoryRecord?
    let latestCheckpoint: CheckpointRecord?
    let handoffHistory: [CheckpointRecord]
    let supplement: TaskSupplementRecord?
    let contextPack: ContextPack?
    let gitActivity: GitActivitySnapshot?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tasks: [TaskRecord] = []
    @Published var archivedTasks: [TaskRecord] = []
    @Published var selectedTaskID: String?
    @Published var activeTaskID: String?
    @Published var activeTitle: String?
    @Published var revision = "0"
    @Published var newTaskTitle = ""
    @Published var taskSearchQuery = ""
    @Published var quickSwitchQuery = ""
    @Published var fileSearchQuery = ""
    @Published var editTitle = ""
    @Published var editGoal = ""
    @Published var taskSaveState: SaveState = .saved
    @Published var files: [TaskFileRecord] = []
    @Published var textMaterials: [TaskNoteRecord] = []
    @Published var repository: TaskRepositoryRecord?
    @Published var taskRepositoriesByID: [String: TaskRepositoryRecord] = [:]
    @Published var workspaceBindingsByTaskID: [String: ContextBindingRecord] = [:]
    @Published var workspaceInfoByTaskID: [String: GitWorkspaceInfo] = [:]
    @Published var availableWorktreesByProjectID: [String: [GitWorkspaceInfo]] = [:]
    @Published var currentBranchesByRepo: [String: String] = [:]
    @Published var currentHeadsByRepo: [String: String] = [:]
    @Published var dirtyStatesByRepo: [String: GitWorkingTreeState] = [:]
    var workingTreeSignaturesByRepo: [String: String] = [:]
    @Published var selectedRepoCurrentBranch = "-"
    @Published var selectedRepoDirtyState: GitWorkingTreeState = .unknown
    @Published var gitSuggestion: GitBranchSuggestion?
    @Published var handoffNote = ""
    @Published var handoffSaveState: SaveState = .saved
    @Published var latestCheckpoint: CheckpointRecord?
    @Published var handoffHistory: [CheckpointRecord] = []
    @Published var resumeBriefText = ""
    @Published var agentReadableFiles: [AgentFilePreview] = []
    @Published var agentHiddenFiles: [AgentFilePreview] = []
    @Published var assistantProjectionReady = false
    @Published var assistantHandoffNote = ""
    @Published var assistantContextPackBrief = ""
    @Published var assistantReadableFiles: [AgentFilePreview] = []
    @Published var assistantHiddenFiles: [AgentFilePreview] = []
    @Published var assistantVisibleNotes: [TaskNoteRecord] = []
    @Published var assistantHiddenNoteCount = 0
    @Published var assistantRepository: TaskRepositoryRecord?
    @Published var assistantCurrentBranch = "-"
    @Published var assistantDirtyState: GitWorkingTreeState = .unknown
    @Published var diagnosticActiveTask = ""
    @Published var diagnosticManifest = ""
    @Published var assistantConnection = AssistantConnectionUIState()
    @Published var assistantExposureEnabled = storedAssistantExposureEnabled()
    @Published var appLanguage = AppLanguage.stored()
    @Published var message = ""
    @Published var toastMessage: String?
    @Published var isDropTargeted = false
    @Published var confirmation: ConfirmationRequest?
    @Published var showArchivedTasks = false
    @Published var showNewTaskSheet = false
    @Published var showQuickSwitcher = false
    @Published var showAddTextMaterialSheet = false
    @Published var newTextMaterialTitle = ""
    @Published var newTextMaterialBody = ""
    @Published var newTextMaterialVisible = true
    @Published var showContextPreparationSheet = false
    let contextPreparation = ContextPreparationModel()
    @Published var currentContextPack: ContextPack?
    @Published var currentContextSourceChanges: [ContextSourceDelta] = []
    @Published var currentGitActivity: GitActivitySnapshot?

    let storagePath = NexusPaths.databaseURL.path
    let assistantHelperPath = NexusPaths.applicationSupportDirectory
        .appendingPathComponent("bin/nexus-mcp")
        .path
    let store = ProjectionStore()
    private var bootstrapped = false
    private var isLoadingSelectedTask = false
    private var supplementSaveTask: Task<Void, Never>?
    private var taskSaveTask: Task<Void, Never>?
    var gitMonitorTask: Task<Void, Never>?
    var gitRefreshTask: Task<Void, Never>?
    var gitActivityRefreshTask: Task<Void, Never>?
    var appRefreshTask: Task<Void, Never>?
    var selectedTaskLoadTask: Task<Void, Never>?
    var projectionRefreshTask: Task<Void, Never>?
    var assistantRefreshTask: Task<Void, Never>?
    var contextSourceRefreshTask: Task<Void, Never>?
    var dismissedGitSuggestionKey: String?
    var contextPreparationTask: Task<Void, Never>?
    var bootstrapTask: Task<Void, Never>?
    let keychainCredentialStore = KeychainCredentialStore()

    var filteredTasks: [TaskRecord] {
        filterTasks(stableTasks, query: taskSearchQuery)
    }

    var visibleWorkTasks: [TaskRecord] {
        stableTasks.filter { !isPlaceholderTask($0) }
    }

    var sidebarProjectGroups: [SidebarProjectGroup] {
        let projectTasks = filteredTasks.filter { task in
            !isPlaceholderTask(task) && taskRepositoriesByID[task.id] != nil
        }
        let grouped = Dictionary(grouping: projectTasks) { task in
            workspaceInfoByTaskID[task.id]?.commonDirectory
                ?? taskRepositoriesByID[task.id].map { WorkspacePath.normalize($0.path) }
                ?? ""
        }
        return grouped.compactMap { identity, tasks in
            guard !identity.isEmpty else { return nil }
            let rootPath =
                tasks.compactMap { workspaceInfoByTaskID[$0.id]?.repositoryRoot }.first
                ?? tasks.compactMap { taskRepositoriesByID[$0.id]?.path }.first
                ?? identity
            return SidebarProjectGroup(
                id: identity,
                name: URL(fileURLWithPath: rootPath).lastPathComponent,
                path: rootPath,
                tasks: tasks.sorted(by: stableTaskSort)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var sidebarInboxTasks: [TaskRecord] {
        filteredTasks
            .filter { !isPlaceholderTask($0) && taskRepositoriesByID[$0.id] == nil }
            .sorted(by: stableTaskSort)
    }

    var quickSwitchResults: [TaskRecord] {
        filterTasks(visibleWorkTasks, query: quickSwitchQuery)
    }

    var recentMenuTasks: [TaskRecord] {
        stableTasks.filter { $0.id != activeTaskID && !isPlaceholderTask($0) }.prefix(5).map { $0 }
    }

    var canCreateNewTask: Bool {
        !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filteredFiles: [TaskFileRecord] {
        let query = fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredTextMaterials: [TaskNoteRecord] {
        let query = fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return textMaterials }
        return textMaterials.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    var contextMaterialCount: Int {
        files.count + textMaterials.count
    }

    var assistantHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: assistantHelperPath)
    }

    var l10n: L10n {
        L10n(appLanguage: appLanguage)
    }

    func performStoreOperation<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable (ProjectionStore) throws -> T
    ) async throws -> T {
        let store = store
        return try await NexusBackgroundWork.run(priority: priority) {
            try operation(store)
        }
    }

    var menuBarSystemImage: String {
        if !assistantExposureEnabled {
            return "pause.circle.fill"
        }
        return activeTitle == nil ? "circle.dashed" : "checkmark.circle.fill"
    }

    var assistantConnectionIconName: String {
        if !assistantExposureEnabled {
            return "pause.circle.fill"
        }
        return assistantConnectionReady ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted"
    }

    var assistantConnectionReady: Bool {
        get { assistantConnection.ready }
        set { assistantConnection.ready = newValue }
    }

    var assistantConnectionStatus: String {
        get { assistantConnection.status }
        set { assistantConnection.status = newValue }
    }

    var assistantConnectionDetail: String {
        get { assistantConnection.detail }
        set { assistantConnection.detail = newValue }
    }

    var assistantConnectionDoctor: String {
        get { assistantConnection.doctor }
        set { assistantConnection.doctor = newValue }
    }

    var contextPreparationPhase: ContextPreparationPhase {
        get { contextPreparation.phase }
        set { updateContextPreparation(\.phase, to: newValue) }
    }

    var contextPreparationInput: ContextPreparationInput? {
        get { contextPreparation.input }
        set { updateContextPreparation(\.input, to: newValue) }
    }

    var selectedContextSourceIDs: Set<String> {
        get { contextPreparation.selectedSourceIDs }
        set { updateContextPreparation(\.selectedSourceIDs, to: newValue) }
    }

    var contextDraft: ContextDraft? {
        get { contextPreparation.draft }
        set { updateContextPreparation(\.draft, to: newValue) }
    }

    var contextDraftBaseline: ContextPackContent? {
        get { contextPreparation.draftBaseline }
        set { updateContextPreparation(\.draftBaseline, to: newValue) }
    }

    var contextDraftBrief: String {
        get { contextPreparation.draftBrief }
        set { updateContextPreparation(\.draftBrief, to: newValue) }
    }

    var contextQuestionAnswers: [String: String] {
        get { contextPreparation.questionAnswers }
        set { updateContextPreparation(\.questionAnswers, to: newValue) }
    }

    var contextPreparationError: String {
        get { contextPreparation.error }
        set { updateContextPreparation(\.error, to: newValue) }
    }

    var contextAPIKeyInput: String {
        get { contextPreparation.apiKeyInput }
        set { updateContextPreparation(\.apiKeyInput, to: newValue) }
    }

    var contextAPIKeyStatus: String {
        get { contextPreparation.apiKeyStatus }
        set { updateContextPreparation(\.apiKeyStatus, to: newValue) }
    }

    var hasContextAPIKey: Bool {
        get { contextPreparation.hasAPIKey }
        set { updateContextPreparation(\.hasAPIKey, to: newValue) }
    }

    var contextModelProvider: ContextModelProvider {
        get { contextPreparation.modelProvider }
        set { updateContextPreparation(\.modelProvider, to: newValue) }
    }

    var contextPreparationModelOverride: String? {
        get { contextPreparation.modelOverride }
        set { updateContextPreparation(\.modelOverride, to: newValue) }
    }

    var hasWorkNotes: Bool {
        !handoffNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAddHandoffHistory: Bool {
        !handoffNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedTaskID != nil
    }

    var canPrepareCurrentContext: Bool {
        selectedTaskID != nil
    }

    var preparedContextDiff: ContextPackDiff? {
        contextPreparation.comparison(to: currentContextPack)
    }

    var preparedContextFindings: [ContextReviewFinding] {
        contextPreparation.findings(currentPack: currentContextPack)
    }

    private func updateContextPreparation<Value>(
        _ keyPath: ReferenceWritableKeyPath<ContextPreparationModel, Value>,
        to value: Value
    ) {
        objectWillChange.send()
        contextPreparation[keyPath: keyPath] = value
    }

    var currentContextNeedsReview: Bool {
        guard currentContextPack != nil else { return false }
        return currentContextSourceChanges.contains {
            $0.kind == .changed || $0.kind == .removed
        }
    }

    var currentContextLifecycleState: ContextLifecycleState {
        ContextLifecycleResolver.resolve(
            hasConfirmedContext: currentContextPack != nil,
            materialsChanged: currentContextNeedsReview,
            gitActivity: currentGitActivity,
            workingTreeState: selectedRepoDirtyState
        )
    }

    var canAddTextMaterial: Bool {
        !newTextMaterialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isSelectedRepoBranchAligned: Bool {
        guard let repository else { return true }
        return repository.branch == selectedRepoCurrentBranch
    }

    var selectedWorkspaceBinding: ContextBindingRecord? {
        guard let selectedTaskID else { return nil }
        return workspaceBindingsByTaskID[selectedTaskID]
    }

    var selectedWorkspaceInfo: GitWorkspaceInfo? {
        guard let selectedTaskID else { return nil }
        return workspaceInfoByTaskID[selectedTaskID]
    }

    private var stableTasks: [TaskRecord] {
        tasks.sorted(by: stableTaskSort)
    }

    func bootstrap() {
        guard !bootstrapped, bootstrapTask == nil else { return }
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { bootstrapTask = nil }
            do {
                try await performStoreOperation { store in
                    try store.bootstrap()
                }
                bootstrapped = true
                refresh()
                startGitMonitor()
            } catch {
                showToast(l10n.bootstrapFailed)
                message = "Bootstrap error: \(error)"
            }
        }
    }

    func refresh() {
        guard bootstrapped else { return }
        appRefreshTask?.cancel()
        appRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await performStoreOperation(priority: .utility) { store in
                    try store.refreshActiveContextFreshness()
                    let tasks = try store.listTasks()
                    let repositories = try store.listRepositories()
                    return AppRefreshData(
                        tasks: tasks,
                        repositories: repositories,
                        workspaceBindings: try store.listWorkspaceBindings(),
                        workspaceInfoByTaskID: Dictionary(
                            uniqueKeysWithValues: repositories.compactMap { repository in
                                store.gitWorkspaceInfo(at: repository.path).map { (repository.taskID, $0) }
                            }
                        ),
                        activeTask: try store.activeTask()
                    )
                }
                guard !Task.isCancelled else { return }
                applyRefreshData(data)
            } catch is CancellationError {
                return
            } catch {
                showToast(l10n.refreshFailed)
                message = "Refresh error: \(error)"
            }
        }
    }

    private func applyRefreshData(_ data: AppRefreshData) {
        tasks = data.tasks
        taskRepositoriesByID = Dictionary(uniqueKeysWithValues: data.repositories.map { ($0.taskID, $0) })
        workspaceBindingsByTaskID = Dictionary(
            grouping: data.workspaceBindings,
            by: \.taskID
        ).compactMapValues(\.first)
        workspaceInfoByTaskID = data.workspaceInfoByTaskID
        let projectIDs = Set(sidebarProjectGroups.map(\.id))
        availableWorktreesByProjectID = availableWorktreesByProjectID.filter {
            projectIDs.contains($0.key)
        }
        refreshCurrentBranches()
        let active = data.activeTask
        activeTaskID = active?.taskID
        let activeTaskRecord = active.flatMap { active in
            tasks.first(where: { $0.id == active.taskID })
        }
        activeTitle = activeTaskRecord.flatMap { isPlaceholderTask($0) ? nil : $0.title }
        if assistantConnectionReady {
            assistantConnectionDetail = activeTitle ?? l10n.noActiveWorkSelectedSentence
        }
        revision = active.map { String($0.revision) } ?? "0"
        if selectedTaskID == nil || !tasks.contains(where: { $0.id == selectedTaskID }) {
            let activeVisibleID = active.flatMap { active in
                tasks.first(where: { $0.id == active.taskID && !isPlaceholderTask($0) })?.id
            }
            selectedTaskID = activeVisibleID ?? visibleWorkTasks.first?.id ?? active?.taskID ?? tasks.first?.id
        }
        loadSelectedTask()
        refreshAssistantView()
    }

    func createTask(openWindow: OpenWindowAction? = nil) {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            showToast(l10n.nameYourWorkFirst)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let task = try await performStoreOperation { store in
                    let task = try store.createTask(title: title, goal: "")
                    try store.switchTask(taskID: task.id)
                    return task
                }
                newTaskTitle = ""
                selectedTaskID = task.id
                showToast(l10n.created)
                openWindow?(id: "main")
                refresh()
            } catch {
                showToast(l10n.createFailed)
                message = "Create error: \(error)"
            }
        }
    }

    func openQuickSwitcher() {
        quickSwitchQuery = ""
        showQuickSwitcher = true
    }

    func openActiveWork() {
        guard let activeTaskID, let task = tasks.first(where: { $0.id == activeTaskID }) else {
            return
        }
        selectTask(task)
    }

    func selectTask(_ task: TaskRecord) {
        selectedTaskID = task.id
        loadSelectedTask()
    }

    func isPlaceholderTask(_ task: TaskRecord) -> Bool {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = task.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return goal.isEmpty && (title.isEmpty || title == "New Task" || title == "New Work")
    }

    func loadSelectedTask() {
        supplementSaveTask?.cancel()
        taskSaveTask?.cancel()
        gitActivityRefreshTask?.cancel()
        selectedTaskLoadTask?.cancel()
        isLoadingSelectedTask = true
        guard let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) else {
            isLoadingSelectedTask = false
            editTitle = ""
            editGoal = ""
            files = []
            textMaterials = []
            repository = nil
            selectedRepoCurrentBranch = "-"
            selectedRepoDirtyState = .unknown
            handoffNote = ""
            latestCheckpoint = nil
            handoffHistory = []
            currentContextPack = nil
            currentContextSourceChanges = []
            currentGitActivity = nil
            clearProjectionPreview()
            return
        }
        editTitle = task.title
        editGoal = task.goal
        taskSaveState = .saved
        selectedTaskLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await performStoreOperation(priority: .utility) { store in
                    SelectedTaskData(
                        files: try store.listFiles(taskID: selectedTaskID),
                        notes: try store.listNotes(taskID: selectedTaskID),
                        repository: try store.repository(taskID: selectedTaskID),
                        latestCheckpoint: try store.latestCheckpoint(taskID: selectedTaskID),
                        handoffHistory: try store.recentCheckpoints(taskID: selectedTaskID, limit: 20),
                        supplement: try store.supplement(taskID: selectedTaskID),
                        contextPack: try store.currentContextPack(taskID: selectedTaskID),
                        gitActivity: try store.gitActivity(taskID: selectedTaskID)
                    )
                }
                guard !Task.isCancelled, self.selectedTaskID == selectedTaskID else { return }
                files = data.files
                textMaterials = data.notes
                fileSearchQuery = ""
                repository = data.repository
                if let repository {
                    selectedRepoCurrentBranch = currentBranchesByRepo[repository.path] ?? "-"
                    selectedRepoDirtyState = dirtyStatesByRepo[repository.path] ?? .unknown
                } else {
                    selectedRepoCurrentBranch = "-"
                    selectedRepoDirtyState = .unknown
                }
                latestCheckpoint = data.latestCheckpoint
                handoffHistory = HandoffText.deduplicatedHistory(data.handoffHistory)
                let storedResumeNote =
                    latestCheckpoint.map { checkpoint in
                        if !checkpoint.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return checkpoint.nextStep
                        }
                        if !checkpoint.currentState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return checkpoint.currentState
                        }
                        return checkpoint.blockers
                    } ?? ""
                let storedHandoffNote = HandoffText.clean(data.supplement?.body ?? "")
                handoffNote = HandoffText.merge(supplement: storedHandoffNote, nextTime: storedResumeNote)
                handoffSaveState = .saved
                currentContextPack = data.contextPack
                currentGitActivity = data.gitActivity
                refreshCurrentContextSourceChanges()
                refreshProjectionPreview()
                updateGitSuggestion()
                isLoadingSelectedTask = false
            } catch is CancellationError {
                return
            } catch {
                guard self.selectedTaskID == selectedTaskID else { return }
                isLoadingSelectedTask = false
                showToast(l10n.loadFailed)
                message = "Load task error: \(error)"
            }
        }
    }

    func scheduleTaskAutosave() {
        guard !isLoadingSelectedTask, let taskID = selectedTaskID else { return }
        taskSaveTask?.cancel()
        let title = editTitle
        let goal = editGoal
        taskSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            do {
                let result = try await performStoreOperation { store in
                    try store.updateTask(id: taskID, title: title, goal: goal)
                    return (
                        try store.listTasks(),
                        try store.currentContextPack(taskID: taskID)
                    )
                }
                guard !Task.isCancelled else { return }
                tasks = result.0
                if activeTaskID == taskID {
                    activeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
                }
                if selectedTaskID == taskID {
                    currentContextPack = result.1
                    refreshCurrentContextSourceChanges()
                }
                taskSaveState = .saved
                refreshProjectionPreview()
                refreshAssistantView()
            } catch {
                taskSaveState = .failed
                message = "Save error: \(error)"
                showToast(l10n.saveFailed)
            }
        }
    }

    func switchToSelected() {
        guard let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) else {
            return
        }
        switchTo(task)
    }

    func switchTo(_ task: TaskRecord) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.switchTask(taskID: task.id)
                }
                selectedTaskID = task.id
                showToast(l10n.activeWorkChanged)
                refresh()
            } catch {
                showToast(l10n.switchFailed)
                message = "Switch error: \(error)"
            }
        }
    }

    func requestArchiveSelectedTask() {
        guard let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) else { return }
        requestArchiveTask(task)
    }

    func requestArchiveTask(_ task: TaskRecord) {
        confirmation = ConfirmationRequest(
            kind: .archive(task.id),
            title: l10n.archiveTitle(task.title),
            message: l10n.archiveMessage,
            confirmTitle: l10n.archiveWork
        )
    }

    func requestDeleteSelectedTask() {
        guard let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) else { return }
        requestDeleteTask(task)
    }

    func requestDeleteTask(_ task: TaskRecord) {
        confirmation = ConfirmationRequest(
            kind: .delete(task.id),
            title: l10n.deleteTitle(task.title),
            message: l10n.deleteMessage,
            confirmTitle: l10n.deleteWork
        )
    }

    func perform(_ request: ConfirmationRequest) {
        switch request.kind {
        case .archive(let taskID):
            archiveTask(taskID)
        case .delete(let taskID):
            deleteTask(taskID)
        case .removeTextMaterial(let materialID, let taskID):
            removeTextMaterial(id: materialID, taskID: taskID)
        }
    }

    func loadArchivedTasks() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                archivedTasks = try await performStoreOperation(priority: .utility) { store in
                    try store.listArchivedTasks()
                }
            } catch {
                showToast(l10n.loadArchivedFailed)
                message = "Archived task error: \(error)"
            }
        }
    }

    func restoreTask(_ task: TaskRecord) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.restoreTask(id: task.id)
                }
                selectedTaskID = task.id
                showToast(l10n.restored)
                refresh()
                loadArchivedTasks()
            } catch {
                showToast(l10n.restoreFailed)
                message = "Restore error: \(error)"
            }
        }
    }

    func scheduleHandoffAutosave() {
        guard !isLoadingSelectedTask, let taskID = selectedTaskID else { return }
        supplementSaveTask?.cancel()
        let body = HandoffText.clean(handoffNote)
        supplementSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            do {
                let pack = try await performStoreOperation { store in
                    try store.updateSupplement(taskID: taskID, body: body)
                    return try store.currentContextPack(taskID: taskID)
                }
                guard !Task.isCancelled else { return }
                if selectedTaskID == taskID {
                    currentContextPack = pack
                    refreshCurrentContextSourceChanges()
                }
                handoffSaveState = .saved
                refreshProjectionPreview()
                refreshAssistantView()
            } catch {
                handoffSaveState = .failed
                message = "Handoff note error: \(error)"
                showToast(l10n.saveFailed)
            }
        }
    }

    func addHandoffToHistory() {
        guard let taskID = selectedTaskID else { return }
        let body = HandoffText.clean(handoffNote)
        guard !body.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await performStoreOperation { store in
                    try store.updateSupplement(taskID: taskID, body: body)
                    let checkpoint = try store.saveCheckpoint(
                        taskID: taskID,
                        currentState: "",
                        nextStep: body,
                        blockers: ""
                    )
                    return (checkpoint, try store.recentCheckpoints(taskID: taskID, limit: 20))
                }
                guard selectedTaskID == taskID else { return }
                latestCheckpoint = result.0
                handoffHistory = HandoffText.deduplicatedHistory(result.1)
                handoffSaveState = .saved
                showToast(l10n.snapshotSaved)
                refreshProjectionPreview()
                refreshAssistantView()
            } catch {
                handoffSaveState = .failed
                message = "Handoff history error: \(error)"
                showToast(l10n.saveFailed)
            }
        }
    }

    private func archiveTask(_ taskID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.archiveTask(id: taskID)
                }
                selectedTaskID = nil
                showToast(l10n.archived)
                refresh()
            } catch {
                showToast(l10n.archiveFailed)
                message = "Archive error: \(error)"
            }
        }
    }

    private func deleteTask(_ taskID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.deleteTask(id: taskID)
                }
                selectedTaskID = nil
                showToast(l10n.deleted)
                refresh()
            } catch {
                showToast(l10n.deleteBlocked)
                message = "Delete blocked: \(error)"
            }
        }
    }

    private func filterTasks(_ tasks: [TaskRecord], query: String) -> [TaskRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return tasks }
        return tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmed) || task.goal.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func stableTaskSort(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            toastMessage = text
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if toastMessage == text {
                withAnimation(.easeInOut(duration: 0.16)) {
                    toastMessage = nil
                }
            }
        }
    }

}
