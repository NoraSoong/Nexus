import Foundation
import NexusCore
import SwiftUI

@MainActor
extension AppModel {
    var assistantPreviewIconName: String {
        if !assistantExposureEnabled {
            return "pause.circle.fill"
        }
        return selectedTaskID == activeTaskID ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted"
    }

    var assistantPreviewIconColor: Color {
        if !assistantExposureEnabled {
            return .secondary
        }
        return selectedTaskID == activeTaskID ? .green : .secondary
    }

    var assistantPreviewTitle: String {
        if !assistantExposureEnabled {
            return l10n.assistantContextPausedTitle
        }
        return activeTitle ?? l10n.noActiveWorkSelected
    }

    var assistantPreviewSubtitle: String {
        if !assistantExposureEnabled {
            return l10n.assistantContextPausedSubtitle
        }
        return selectedTaskID == activeTaskID ? l10n.assistantsReadOpenWork : l10n.assistantsReadActiveWork
    }

    var visibleMaterialCount: Int {
        files.filter(\.isVisibleToAgent).count + textMaterials.filter(\.isExposedToMCP).count
    }

    var hiddenMaterialCount: Int {
        files.filter { !$0.isVisibleToAgent }.count + textMaterials.filter { !$0.isExposedToMCP }.count
    }

    var assistantVisibleMaterialCount: Int {
        assistantReadableFiles.count + assistantVisibleNotes.count
    }

    var assistantHiddenMaterialCount: Int {
        assistantHiddenFiles.count + assistantHiddenNoteCount
    }

    var hasAssistantHandoffNote: Bool {
        !assistantHandoffNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAssistantContextPack: Bool {
        !assistantContextPackBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAssistantRecoveryContext: Bool {
        hasAssistantContextPack || hasAssistantHandoffNote
    }

    var assistantRepositoryAligned: Bool {
        guard let assistantRepository else { return true }
        return assistantRepository.branch == assistantCurrentBranch
    }

    var missingAssistantFiles: [AgentFilePreview] {
        assistantReadableFiles.filter { file in
            !file.path.isEmpty && !FileManager.default.fileExists(atPath: file.path)
        }
    }

    var assistantContextIssues: [AssistantContextIssue] {
        var issues: [AssistantContextIssue] = []
        if activeTaskID == nil {
            issues.append(
                AssistantContextIssue(
                    id: "no-active-work",
                    title: l10n.noActiveWork,
                    message: l10n.noActiveWorkIssue,
                    systemImage: "exclamationmark.circle",
                    tone: .warning
                ))
        } else if !assistantProjectionReady {
            issues.append(
                AssistantContextIssue(
                    id: "projection-missing",
                    title: l10n.activeContextNotReady,
                    message: l10n.activeContextMissingProjection,
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                ))
        }
        if let assistantRepository, !assistantRepositoryAligned {
            issues.append(
                AssistantContextIssue(
                    id: "branch-mismatch",
                    title: l10n.branchMismatch,
                    message: l10n.branchMismatchIssue(
                        linked: assistantRepository.branch, current: assistantCurrentBranch),
                    systemImage: "arrow.triangle.branch",
                    tone: .warning
                ))
        }
        if assistantDirtyState == .modified {
            issues.append(
                AssistantContextIssue(
                    id: "dirty-worktree",
                    title: l10n.dirtyWorktree,
                    message: l10n.dirtyWorktreeIssue,
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                ))
        }
        if !missingAssistantFiles.isEmpty {
            let count = missingAssistantFiles.count
            issues.append(
                AssistantContextIssue(
                    id: "missing-files",
                    title: l10n.visibleFilesMissing(count),
                    message: l10n.missingFileIssue,
                    systemImage: "doc.badge.ellipsis",
                    tone: .warning
                ))
        }
        return issues
    }

    func refreshProjectionPreview() {
        guard let selectedTaskID else {
            clearProjectionPreview()
            return
        }
        projectionRefreshTask?.cancel()
        let fallbackFiles = files
        projectionRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await performStoreOperation(priority: .utility) { store in
                    try store.projectionSnapshot(taskID: selectedTaskID)
                }
                guard !Task.isCancelled, self.selectedTaskID == selectedTaskID else { return }
                guard let snapshot else {
                    resumeBriefText = l10n.activateToGenerateBrief
                    agentReadableFiles = fallbackFiles.filter(\.isVisibleToAgent).map(ProjectionJSON.filePreview)
                    agentHiddenFiles = fallbackFiles.filter { !$0.isVisibleToAgent }.map(ProjectionJSON.filePreview)
                    return
                }
                resumeBriefText = ProjectionJSON.brief(from: snapshot.resumeBriefJSON) ?? snapshot.resumeBriefJSON
                let manifestFiles = ProjectionJSON.files(from: snapshot.manifestJSON, key: "files")
                let manifestHiddenFiles = ProjectionJSON.files(from: snapshot.manifestJSON, key: "hidden_files")
                agentReadableFiles =
                    manifestFiles.isEmpty
                    ? fallbackFiles.filter(\.isVisibleToAgent).map(ProjectionJSON.filePreview)
                    : manifestFiles
                agentHiddenFiles =
                    manifestHiddenFiles.isEmpty
                    ? fallbackFiles.filter { !$0.isVisibleToAgent }.map(ProjectionJSON.filePreview)
                    : manifestHiddenFiles
            } catch is CancellationError {
                return
            } catch {
                showToast(l10n.previewFailed)
                message = "Projection preview error: \(error)"
            }
        }
    }

    func refreshAssistantView() {
        guard let activeTaskID else {
            clearAssistantView()
            return
        }
        assistantRefreshTask?.cancel()
        assistantRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await performStoreOperation(priority: .utility) { store in
                    (
                        try store.listNotes(taskID: activeTaskID),
                        try store.repository(taskID: activeTaskID),
                        try store.supplement(taskID: activeTaskID),
                        try store.projectionSnapshot(taskID: activeTaskID)
                    )
                }
                guard !Task.isCancelled, self.activeTaskID == activeTaskID else { return }
                let (activeNotes, activeRepository, supplement, snapshot) = result
                assistantVisibleNotes = activeNotes.filter(\.isExposedToMCP)
                assistantHiddenNoteCount = activeNotes.filter { !$0.isExposedToMCP }.count
                assistantRepository = activeRepository
                if let assistantRepository {
                    assistantCurrentBranch = currentBranchesByRepo[assistantRepository.path] ?? "-"
                    assistantDirtyState = dirtyStatesByRepo[assistantRepository.path] ?? .unknown
                } else {
                    assistantCurrentBranch = "-"
                    assistantDirtyState = .unknown
                }
                assistantHandoffNote = HandoffText.clean(supplement?.body ?? "")
                assistantContextPackBrief = ""

                guard let snapshot else {
                    assistantProjectionReady = false
                    assistantReadableFiles = []
                    assistantHiddenFiles = []
                    diagnosticActiveTask = ""
                    diagnosticManifest = ""
                    return
                }

                assistantProjectionReady = true
                diagnosticActiveTask = ProjectionJSON.prettyString(snapshot.activeTaskJSON)
                diagnosticManifest = ProjectionJSON.prettyString(snapshot.manifestJSON)
                assistantHandoffNote = HandoffText.clean(
                    ProjectionJSON.string(from: snapshot.manifestJSON, key: "supplement") ?? assistantHandoffNote)
                assistantContextPackBrief =
                    ProjectionJSON.nestedString(
                        from: snapshot.manifestJSON,
                        objectKey: "context_pack",
                        key: "brief"
                    ) ?? ""
                assistantReadableFiles = ProjectionJSON.files(from: snapshot.manifestJSON, key: "files")
                assistantHiddenFiles = ProjectionJSON.files(from: snapshot.manifestJSON, key: "hidden_files")
            } catch is CancellationError {
                return
            } catch {
                assistantProjectionReady = false
                showToast(l10n.assistantContextFailed)
                message = "Assistant Context error: \(error)"
            }
        }
    }

    func clearAssistantView() {
        assistantProjectionReady = false
        assistantHandoffNote = ""
        assistantContextPackBrief = ""
        assistantReadableFiles = []
        assistantHiddenFiles = []
        assistantVisibleNotes = []
        assistantHiddenNoteCount = 0
        assistantRepository = nil
        assistantCurrentBranch = "-"
        assistantDirtyState = .unknown
        diagnosticActiveTask = ""
        diagnosticManifest = ""
    }

    func clearProjectionPreview() {
        resumeBriefText = ""
        agentReadableFiles = []
        agentHiddenFiles = []
    }
}
