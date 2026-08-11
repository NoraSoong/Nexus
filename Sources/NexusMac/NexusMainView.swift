import AppKit
import NexusCore
import SwiftUI
import UniformTypeIdentifiers

struct NexusMainView: View {
    @ObservedObject var model: AppModel
    @State private var showAgentInspector = false
    @State private var showAssistantConnection = false
    @State private var showDiagnostics = false
    @State private var showAssistantIssues = false
    @State private var showAssistantDetails = false
    @State private var showDeveloperDiagnostics = false
    @State private var showCurrentContextDetails = false
    @State private var showWorkNotes = false
    @State private var collapsedProjectIDs: Set<String> = []
    private var l10n: L10n { model.l10n }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            workspace
            if showAgentInspector {
                Divider()
                inspector
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 1100, minHeight: 680)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) {
            if let toast = model.toastMessage {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.openQuickSwitcher()
                } label: {
                    Label(l10n.switchWork, systemImage: "magnifyingglass")
                }
                .help("\(l10n.switchWork) (Command-K)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAssistantConnection.toggle()
                } label: {
                    Label(l10n.assistantConnection, systemImage: model.assistantConnectionIconName)
                }
                .help(l10n.assistantConnection)
                .popover(isPresented: $showAssistantConnection, arrowEdge: .bottom) {
                    AssistantConnectionPopover(model: model)
                        .padding(14)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAgentInspector.toggle()
                    }
                } label: {
                    Label(l10n.assistantPreview, systemImage: showAgentInspector ? "sidebar.right" : "sparkles")
                }
                .help(l10n.showAssistantContextHelp)
            }
        }
        .alert(item: $model.confirmation) { request in
            Alert(
                title: Text(request.title),
                message: Text(request.message),
                primaryButton: .destructive(Text(request.confirmTitle)) {
                    model.perform(request)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $model.showArchivedTasks) {
            ArchivedTasksView(model: model)
                .frame(width: 520, height: 420)
        }
        .sheet(isPresented: $model.showNewTaskSheet) {
            NewTaskView(model: model)
                .frame(width: 420)
        }
        .sheet(isPresented: $model.showQuickSwitcher) {
            QuickSwitchView(model: model)
                .frame(width: 560, height: 460)
        }
        .sheet(isPresented: $model.showAddTextMaterialSheet) {
            AddTextMaterialView(model: model)
                .frame(width: 520, height: 460)
        }
        .sheet(isPresented: $model.showContextPreparationSheet) {
            ContextPreparationView(model: model)
                .frame(width: 720, height: 680)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                TextField(l10n.searchWork, text: $model.taskSearchQuery)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.showNewTaskSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help(l10n.newWork)
            }

            SidebarSectionHeader(title: l10n.currentAssistantContext)
            ActiveContextFooter(activeTitle: model.activeTitle, l10n: l10n)

            SidebarSectionHeader(
                title: model.taskSearchQuery.isEmpty
                    ? (model.sidebarProjectGroups.isEmpty ? l10n.work : l10n.projects) : l10n.results,
                accessory: {
                    Button {
                        model.openQuickSwitcher()
                    } label: {
                        Text("⌘K")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.quickSwitchHelp)
                }
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !model.sidebarProjectGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.sidebarProjectGroups) { group in
                                ProjectTaskGroupView(
                                    group: group,
                                    isExpanded: isProjectExpanded(group),
                                    activeTaskID: model.activeTaskID,
                                    selectedTaskID: model.selectedTaskID,
                                    repositoriesByTaskID: model.taskRepositoriesByID,
                                    workspaceInfoByTaskID: model.workspaceInfoByTaskID,
                                    workspaceBindingsByTaskID: model.workspaceBindingsByTaskID,
                                    availableWorktrees: model.availableWorktreesByProjectID[group.id] ?? [],
                                    unboundTasks: model.sidebarInboxTasks,
                                    isPlaceholder: model.isPlaceholderTask,
                                    l10n: l10n,
                                    toggleExpanded: {
                                        toggleProjectExpansion(group)
                                    },
                                    refreshWorktrees: {
                                        model.refreshAvailableWorktrees(for: group)
                                    },
                                    select: model.selectTask,
                                    createWork: {
                                        model.createWork(from: $0, projectID: group.id)
                                    },
                                    bindWorktree: {
                                        model.bindWorkspace($0, to: $1, projectID: group.id)
                                    },
                                    archive: model.requestArchiveTask,
                                    delete: model.requestDeleteTask
                                )
                            }
                        }
                    }

                    if !model.sidebarInboxTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !model.sidebarProjectGroups.isEmpty {
                                SidebarSectionHeader(title: l10n.inbox)
                            }
                            ForEach(model.sidebarInboxTasks) { task in
                                TaskNavigationRow(
                                    task: task,
                                    isActive: task.id == model.activeTaskID,
                                    isSelected: task.id == model.selectedTaskID,
                                    isPlaceholder: false,
                                    l10n: l10n
                                ) {
                                    model.selectTask(task)
                                } archiveAction: {
                                    model.requestArchiveTask(task)
                                } deleteAction: {
                                    model.requestDeleteTask(task)
                                }
                            }
                        }
                    }

                    if model.sidebarProjectGroups.isEmpty, model.sidebarInboxTasks.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: model.taskSearchQuery.isEmpty ? l10n.noWorkYet : l10n.noMatchingWork,
                            message: model.taskSearchQuery.isEmpty ? l10n.noWorkMessage : l10n.noMatchingWorkMessage
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)

            Button {
                model.loadArchivedTasks()
                model.showArchivedTasks = true
            } label: {
                Label(l10n.archivedTasks, systemImage: "archivebox")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .frame(width: 286)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var workspace: some View {
        Group {
            if model.selectedTaskID == nil {
                EmptyWorkspacePanel(l10n: l10n) {
                    model.showNewTaskSheet = true
                } openExistingWork: {
                    model.openQuickSwitcher()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        workspaceHeader
                        if let pack = model.currentContextPack {
                            currentContextSection(pack)
                        }
                        workNotesSection
                        contextMaterialsSection
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 34)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .frame(minWidth: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(l10n.titlePlaceholder, text: $model.editTitle)
                        .font(.largeTitle.weight(.semibold))
                        .textFieldStyle(.plain)
                        .onChange(of: model.editTitle) { _, _ in
                            model.scheduleTaskAutosave()
                        }
                    TextField(l10n.goalPlaceholder, text: $model.editGoal, axis: .vertical)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .onChange(of: model.editGoal) { _, _ in
                            model.scheduleTaskAutosave()
                        }
                }
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    ContextReadyBadge(isReady: model.selectedTaskID == model.activeTaskID, l10n: l10n)
                    Menu {
                        Button {
                            model.requestArchiveSelectedTask()
                        } label: {
                            Label(l10n.archiveWork, systemImage: "archivebox")
                        }
                        .disabled(model.selectedTaskID == nil)
                        Button(role: .destructive) {
                            model.requestDeleteSelectedTask()
                        } label: {
                            Label(l10n.deleteWork, systemImage: "trash")
                        }
                        .disabled(model.selectedTaskID == nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help(l10n.workActions)
                }
            }

            contextStatusStrip

            if let suggestion = model.gitSuggestion {
                GitSuggestionNotice(suggestion: suggestion, l10n: l10n) {
                    model.switchToSuggestedGitTask()
                } dismiss: {
                    model.dismissGitSuggestion()
                }
            }

            if model.taskSaveState == .failed {
                Text(l10n.saveFailed)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var contextStatusStrip: some View {
        ProjectContextBar(
            repository: model.repository,
            workspaceInfo: model.selectedWorkspaceInfo,
            currentBranch: model.selectedRepoCurrentBranch,
            dirtyState: model.selectedRepoDirtyState,
            aligned: model.isSelectedRepoBranchAligned,
            isCurrentWork: model.selectedTaskID == model.activeTaskID,
            l10n: l10n,
            makeCurrent: {
                model.switchToSelected()
            },
            useCurrentBranch: {
                model.relinkSelectedRepositoryBranch()
            },
            chooseRepository: {
                model.chooseRepository()
            }
        )
    }

    private var workNotesSection: some View {
        WorkCard {
            if model.currentContextPack == nil {
                workNotesEditor
            } else {
                DisclosureGroup(isExpanded: $showWorkNotes) {
                    workNotesEditorBody
                        .padding(.top, 14)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                        Text(l10n.handoffTitle)
                            .font(.headline)
                        if !model.hasWorkNotes {
                            Text(l10n.optional)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if model.handoffSaveState == .failed {
                            Text(l10n.saveFailed)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if model.hasWorkNotes {
                            Text(l10n.includedInNextPreparation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: model.selectedTaskID) { _, _ in
                    showWorkNotes = false
                }
            }
        }
    }

    private var workNotesEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(l10n.handoffTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    model.beginContextPreparation()
                } label: {
                    Label(l10n.prepareCurrentWork, systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canPrepareCurrentContext)
                .help(l10n.contextPreparationDescription)
            }
            workNotesEditorBody
        }
    }

    private var workNotesEditorBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            SupplementEditor(
                text: $model.handoffNote,
                placeholder: l10n.handoffPlaceholder
            )
            .frame(minHeight: model.hasWorkNotes ? 150 : 126)
            .onChange(of: model.handoffNote) { _, _ in
                model.scheduleHandoffAutosave()
            }

            HStack {
                if model.handoffSaveState == .failed {
                    Text(l10n.saveFailed)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Menu {
                    Button {
                        model.addHandoffToHistory()
                    } label: {
                        Label(l10n.saveSnapshot, systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(!model.canAddHandoffHistory)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help(l10n.saveSnapshotHelp)
            }

            if !model.handoffHistory.isEmpty {
                HandoffHistoryView(entries: model.handoffHistory, l10n: l10n)
            }
        }
    }

    private func currentContextSection(_ pack: ContextPack) -> some View {
        WorkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: currentContextIcon)
                        .foregroundStyle(currentContextColor)
                    Text(l10n.currentContextTitle)
                        .font(.title3.weight(.semibold))
                    Text(currentContextStatus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(currentContextColor)
                    Spacer()
                    Button {
                        model.beginContextPreparation()
                    } label: {
                        Label(l10n.updateCurrentContext, systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                Text(pack.content.brief)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(showCurrentContextDetails ? nil : 5)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = currentCodeActivitySummary {
                    Label(summary, systemImage: "arrow.triangle.branch")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    currentContextMetric(
                        value: pack.sourceManifest.count,
                        label: l10n.sources
                    )
                    if !pack.content.constraints.isEmpty {
                        currentContextMetric(
                            value: pack.content.constraints.count,
                            label: l10n.contextConstraints
                        )
                    }
                    if !pack.content.questions.isEmpty {
                        currentContextMetric(
                            value: pack.content.questions.count,
                            label: l10n.clarificationQuestions
                        )
                    }
                    Spacer()
                    Text(l10n.lastApplied(ReadableFileType.shortDate(pack.createdAt)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                DisclosureGroup(isExpanded: $showCurrentContextDetails) {
                    currentContextDetails(pack)
                        .padding(.top, 12)
                } label: {
                    Text(l10n.viewCurrentContext)
                        .font(.callout.weight(.medium))
                }
                .onChange(of: model.selectedTaskID) { _, _ in
                    showCurrentContextDetails = false
                }
            }
        }
    }

    private func currentContextMetric(value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .fontWeight(.semibold)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func currentContextDetails(_ pack: ContextPack) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !pack.content.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentContextTextSection(
                    title: l10n.contextObjective,
                    text: pack.content.objective
                )
            }
            currentContextClaimsSection(title: l10n.contextScopeIn, claims: pack.content.scopeIn)
            currentContextClaimsSection(title: l10n.contextScopeOut, claims: pack.content.scopeOut)
            currentContextClaimsSection(title: l10n.contextConfirmedFacts, claims: pack.content.confirmedFacts)
            currentContextClaimsSection(title: l10n.contextConstraints, claims: pack.content.constraints)
            currentContextClaimsSection(
                title: l10n.contextAcceptanceCriteria,
                claims: pack.content.acceptanceCriteria
            )
            currentContextClaimsSection(title: l10n.contextAssumptions, claims: pack.content.assumptions)

            if !pack.content.questions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(l10n.clarificationQuestions)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(pack.content.questions) { question in
                        Label(question.question, systemImage: "questionmark.circle")
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                }
            }

            if !pack.sourceManifest.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(l10n.sources)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(pack.sourceManifest) { source in
                        currentContextSourceRow(source)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func currentContextClaimsSection(title: String, claims: [ContextClaim]) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(claims.enumerated()), id: \.offset) { _, claim in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(Color.secondary.opacity(0.55))
                            .frame(width: 4, height: 4)
                        Text(claim.text)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func currentContextTextSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func currentContextSourceRow(_ source: ContextSourceRef) -> some View {
        HStack(spacing: 8) {
            Image(systemName: currentContextSourceIcon(source))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(currentContextSourceTitle(source))
                    .font(.callout)
                    .lineLimit(1)
                if source.truncated {
                    Text(l10n.truncatedSource)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let path = source.path {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Image(systemName: "arrow.forward.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(path)
            }
        }
    }

    private func currentContextSourceTitle(_ source: ContextSourceRef) -> String {
        switch source.kind {
        case ContextMaterialExtractor.committedGitActivityKind:
            return l10n.committedCodeChanges
        case ContextMaterialExtractor.uncommittedGitActivityKind:
            return l10n.uncommittedCodeChanges
        default:
            return source.title
        }
    }

    private func currentContextSourceIcon(_ source: ContextSourceRef) -> String {
        switch source.kind {
        case ContextMaterialExtractor.committedGitActivityKind:
            return "point.bottomleft.forward.to.point.topright.scurvepath"
        case ContextMaterialExtractor.uncommittedGitActivityKind:
            return "pencil.line"
        default:
            return source.path == nil ? "text.quote" : "doc"
        }
    }

    private var currentContextStatus: String {
        switch model.currentContextLifecycleState {
        case .materialsChanged:
            return l10n.contextNeedsReview
        case .codeChanged:
            return l10n.codeChangesAvailable
        case .materialsAndCodeChanged:
            return l10n.materialsAndCodeChanged
        case .needsConfirmation:
            return l10n.workspaceNeedsConfirmation
        case .workspaceUnavailable:
            return l10n.workspaceUnavailable
        case .noConfirmedContext:
            return l10n.noCurrentContext
        case .confirmed:
            break
        }
        if !model.assistantExposureEnabled {
            return l10n.currentContextPaused
        }
        if model.selectedTaskID == model.activeTaskID {
            return l10n.currentContextAvailable
        }
        return l10n.currentContextSaved
    }

    private var currentContextIcon: String {
        switch model.currentContextLifecycleState {
        case .confirmed:
            return "checkmark.circle.fill"
        case .codeChanged:
            return "arrow.triangle.branch"
        case .materialsChanged, .materialsAndCodeChanged, .needsConfirmation:
            return "exclamationmark.circle.fill"
        case .workspaceUnavailable, .noConfirmedContext:
            return "circle.dashed"
        }
    }

    private var currentContextColor: Color {
        switch model.currentContextLifecycleState {
        case .confirmed:
            return .green
        case .codeChanged:
            return .blue
        case .materialsChanged, .materialsAndCodeChanged, .needsConfirmation:
            return .orange
        case .workspaceUnavailable, .noConfirmedContext:
            return .secondary
        }
    }

    private var currentCodeActivitySummary: String? {
        guard let activity = model.currentGitActivity, activity.hasCodeChanges else {
            return model.selectedRepoDirtyState == .modified ? l10n.uncommittedChanges : nil
        }
        return l10n.codeActivitySummary(
            commits: activity.commits.count,
            paths: Set((activity.committedPaths + activity.dirtyPaths).map(\.path)).count,
            hasUncommittedChanges: !activity.dirtyPaths.isEmpty
        )
    }

    private var contextMaterialsSection: some View {
        WorkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(l10n.contextMaterials)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(l10n.itemCount(model.contextMaterialCount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Menu {
                        Button {
                            model.addClipboardTextMaterial()
                        } label: {
                            Label(l10n.pasteClipboard, systemImage: "doc.on.clipboard")
                        }
                        Button {
                            model.prepareTextMaterial()
                        } label: {
                            Label(l10n.addText, systemImage: "text.badge.plus")
                        }
                    } label: {
                        Label(l10n.add, systemImage: "plus")
                    }
                    .controlSize(.small)
                }

                fileDropZone
                if model.contextMaterialCount >= 6 {
                    HStack {
                        Spacer()
                        TextField(l10n.searchMaterials, text: $model.fileSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                    }
                }
                if model.contextMaterialCount > 0, model.filteredFiles.isEmpty, model.filteredTextMaterials.isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: l10n.noMatchingMaterials,
                        message: l10n.noMatchingMaterialsMessage
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if !model.filteredTextMaterials.isEmpty {
                                materialGroup(l10n.textGroup) {
                                    ForEach(model.filteredTextMaterials) { note in
                                        let binding = textMaterialBinding(for: note)
                                        TextMaterialRow(
                                            material: binding,
                                            l10n: l10n,
                                            save: { model.updateTextMaterial(binding.wrappedValue) },
                                            remove: { model.requestRemoveTextMaterial(binding.wrappedValue) }
                                        )
                                    }
                                }
                            }
                            if !model.filteredFiles.isEmpty {
                                materialGroup(l10n.filesGroup) {
                                    ForEach(model.filteredFiles) { file in
                                        let binding = fileBinding(for: file)
                                        FileRow(
                                            file: binding,
                                            l10n: l10n,
                                            save: { model.updateFile(binding.wrappedValue) },
                                            remove: { model.removeFile(binding.wrappedValue) },
                                            reveal: { model.revealFile(binding.wrappedValue) }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 360)
                }
            }
        }
    }

    private var fileDropZone: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: model.contextMaterialCount == 0 ? 1.35 : 1, dash: [6, 5]))
            .foregroundStyle(
                model.isDropTargeted
                    ? Color.accentColor : Color.secondary.opacity(model.contextMaterialCount == 0 ? 0.42 : 0.24)
            )
            .background(Color.secondary.opacity(model.contextMaterialCount == 0 ? 0.026 : 0.014))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                VStack(spacing: model.contextMaterialCount == 0 ? 6 : 2) {
                    Image(systemName: "doc.badge.plus")
                        .font(model.contextMaterialCount == 0 ? .body : .caption)
                    if model.contextMaterialCount == 0 {
                        Text(l10n.dropLocalFilesHere)
                            .font(.callout.weight(.medium))
                        Text(l10n.originalFilesStayOnDisk)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(l10n.dropFiles)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: model.contextMaterialCount == 0 ? 104 : 44)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $model.isDropTargeted) { providers in
                model.handleDrop(providers: providers)
            }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(l10n.assistantPreview)
                        .font(.headline)
                    Spacer()
                    Menu {
                        Button {
                            model.copyAssistantRule()
                        } label: {
                            Label(l10n.copyAssistantRule, systemImage: "doc.on.doc")
                        }
                        Button {
                            model.copyContextSummary()
                        } label: {
                            Label(l10n.copyContextSummary, systemImage: "doc.text")
                        }
                        Divider()
                        Toggle(l10n.showDeveloperDiagnostics, isOn: $showDeveloperDiagnostics)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help(l10n.moreAssistantContextActions)
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showAgentInspector = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(l10n.hideAssistantContext)
                }

                AssistantPreviewCard(model: model)

                if !model.assistantContextIssues.isEmpty {
                    DisclosureGroup(isExpanded: $showAssistantIssues) {
                        ForEach(model.assistantContextIssues) { issue in
                            AssistantIssueRow(issue: issue)
                        }
                        .padding(.top, 8)
                    } label: {
                        AssistantDisclosureLabel(
                            title: l10n.needsAttention,
                            count: model.assistantContextIssues.count
                        )
                    }
                    .padding(11)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.11), lineWidth: 1)
                    )
                }

                DisclosureGroup(isExpanded: $showAssistantDetails) {
                    AssistantDetailsContent(model: model)
                        .padding(.top, 8)
                } label: {
                    AssistantDisclosureLabel(title: l10n.details)
                }
                .padding(11)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.11), lineWidth: 1)
                )

                if showDeveloperDiagnostics {
                    DisclosureGroup(isExpanded: $showDiagnostics) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(l10n.database)
                                .font(.caption.weight(.semibold))
                            Text(model.storagePath)
                                .font(.caption)
                                .textSelection(.enabled)
                            Text(l10n.revision(model.revision))
                                .font(.caption)
                            Text(l10n.activeTaskProjection)
                                .font(.caption.weight(.semibold))
                            Text(model.diagnosticActiveTask)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text(l10n.manifest)
                                .font(.caption.weight(.semibold))
                            Text(model.diagnosticManifest)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            if !model.contextPreparationDiagnostic.isEmpty {
                                Text(l10n.preparationDiagnostic)
                                    .font(.caption.weight(.semibold))
                                Text(model.contextPreparationDiagnostic)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        AssistantDisclosureLabel(title: l10n.developerDiagnostics)
                    }
                    .padding(11)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.11), lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
        .frame(width: 320)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func materialGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            content()
        }
    }

    private func fileBinding(for file: TaskFileRecord) -> Binding<TaskFileRecord> {
        return Binding(
            get: {
                model.files.first(where: { $0.id == file.id }) ?? file
            },
            set: { updated in
                guard let index = model.files.firstIndex(where: { $0.id == file.id }) else { return }
                model.files[index] = updated
            }
        )
    }

    private func textMaterialBinding(for material: TaskNoteRecord) -> Binding<TaskNoteRecord> {
        return Binding(
            get: {
                model.textMaterials.first(where: { $0.id == material.id }) ?? material
            },
            set: { updated in
                guard let index = model.textMaterials.firstIndex(where: { $0.id == material.id }) else { return }
                model.textMaterials[index] = updated
            }
        )
    }

    private func isProjectExpanded(_ group: SidebarProjectGroup) -> Bool {
        if !model.taskSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !collapsedProjectIDs.contains(group.id)
    }

    private func toggleProjectExpansion(_ group: SidebarProjectGroup) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if collapsedProjectIDs.contains(group.id) {
                collapsedProjectIDs.remove(group.id)
            } else {
                collapsedProjectIDs.insert(group.id)
            }
        }
    }
}
