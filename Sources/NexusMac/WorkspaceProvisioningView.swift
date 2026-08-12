import AppKit
import NexusCore
import SwiftUI

struct WorkspaceProvisioningView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var repositoryPath = ""
    @State private var repositoryName = ""
    @State private var branches: [String] = []
    @State private var baseRef = ""
    @State private var branchName = ""
    @State private var destinationPath = ""
    @State private var preview: WorkspaceProvisioningPreview?
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var confirmedDirtyBase = false

    private var l10n: L10n { model.l10n }
    private var selectedTask: TaskRecord? {
        guard let selectedTaskID = model.selectedTaskID else { return nil }
        return model.tasks.first(where: { $0.id == selectedTaskID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(l10n.workspaceProvisioningTitle)
                    .font(.title2.weight(.semibold))
                Text(l10n.zhWorkspaceProvisioningSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    repositorySection
                    branchSection
                    destinationSection
                    if let preview {
                        previewSection(preview)
                    }
                    if !errorMessage.isEmpty || !model.workspaceProvisioningError.isEmpty {
                        Label(
                            errorMessage.isEmpty ? model.workspaceProvisioningError : errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button(l10n.cancel) { dismiss() }
                    .disabled(model.isProvisioningWorkspace)
                Spacer()
                if preview == nil {
                    Button(l10n.preview) {
                        preparePreview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPreview || isLoading)
                } else {
                    Button(l10n.createWorkspace) {
                        createWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate || isLoading || model.isProvisioningWorkspace)
                }
            }
            .padding(18)
        }
        .task {
            if repositoryPath.isEmpty {
                repositoryPath = model.repository?.path ?? ""
            }
            if !repositoryPath.isEmpty {
                await loadRepository()
            }
        }
        .onChange(of: repositoryPath) { _, _ in
            preview = nil
            Task { await loadRepository() }
        }
        .onChange(of: baseRef) { _, _ in preview = nil }
        .onChange(of: branchName) { _, _ in preview = nil }
        .onChange(of: destinationPath) { _, _ in preview = nil }
    }

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(l10n.repositoryRoot)
                .font(.headline)
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(repositoryName.isEmpty ? l10n.chooseExistingWorkspace : repositoryName)
                        .font(.callout.weight(.medium))
                    Text(repositoryPath.isEmpty ? l10n.chooseGitRepository : repositoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(l10n.chooseExistingWorkspace) {
                    chooseRepository()
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(l10n.baseBranch)
                .font(.headline)
            HStack(spacing: 12) {
                Picker(l10n.baseBranch, selection: $baseRef) {
                    ForEach(branches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(l10n.newBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(l10n.newBranch, text: $branchName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(l10n.destinationDirectory)
                .font(.headline)
            TextField(l10n.destinationDirectory, text: $destinationPath)
                .textFieldStyle(.roundedBorder)
            Text(l10n.zhWorkspaceProvisioningPathHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func previewSection(_ preview: WorkspaceProvisioningPreview) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(l10n.confirm)
                .font(.headline)
            VStack(alignment: .leading, spacing: 7) {
                summaryRow(l10n.baseBranch, preview.baseRef)
                summaryRow(l10n.newBranch, preview.branchName)
                summaryRow(l10n.destinationDirectory, preview.destinationPath)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if preview.dirtyState == .modified {
                Toggle(l10n.confirmDirtyBase, isOn: $confirmedDirtyBase)
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
                Label(l10n.dirtyBaseWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var canPreview: Bool {
        !repositoryPath.isEmpty && !baseRef.isEmpty && !branchName.isEmpty && !destinationPath.isEmpty
    }

    private var canCreate: Bool {
        guard let preview else { return false }
        return preview.dirtyState != .modified || confirmedDirtyBase
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = l10n.chooseGitRepository
        guard panel.runModal() == .OK, let url = panel.url else { return }
        repositoryPath = url.path
        errorMessage = ""
        model.workspaceProvisioningError = ""
    }

    private func loadRepository() async {
        guard !repositoryPath.isEmpty else { return }
        let path = repositoryPath
        isLoading = true
        do {
            let data = try await model.performStoreOperation(priority: .utility) { store in
                guard let info = store.gitWorkspaceInfo(at: path) else {
                    throw WorkspaceProvisioningError.notGitRepository(path)
                }
                let service = WorkspaceProvisioningService(store: store)
                return (
                    info,
                    try service.localBranches(repositoryRoot: info.repositoryRoot),
                    store.currentGitBranch(at: path)
                )
            }
            guard !Task.isCancelled, repositoryPath == path else { return }
            repositoryName = URL(fileURLWithPath: data.0.repositoryRoot).lastPathComponent
            branches = data.1
            if baseRef.isEmpty || !branches.contains(baseRef) {
                baseRef = data.2 == "(unknown)" || data.2 == "(detached)" ? branches.first ?? "" : data.2
            }
            if branchName.isEmpty {
                branchName = WorkspaceProvisioningService.defaultBranchName(
                    workTitle: selectedTask?.title ?? "work",
                    taskID: selectedTask?.id ?? UUID().uuidString
                )
            }
            if destinationPath.isEmpty {
                destinationPath = WorkspaceProvisioningService.defaultDestination(
                    repositoryRoot: data.0.repositoryRoot,
                    workTitle: selectedTask?.title ?? "work",
                    taskID: selectedTask?.id ?? UUID().uuidString
                )
            }
            errorMessage = ""
        } catch {
            errorMessage = l10n.workspaceProvisioningErrorMessage(error)
        }
        isLoading = false
    }

    private func preparePreview() {
        guard let taskID = model.selectedTaskID else { return }
        let request = WorkspaceProvisioningRequest(
            taskID: taskID,
            repositoryRoot: repositoryPath,
            baseRef: baseRef,
            branchName: branchName,
            destinationPath: destinationPath,
            confirmedDirtyBase: confirmedDirtyBase
        )
        isLoading = true
        errorMessage = ""
        Task {
            do {
                let prepared = try await model.performStoreOperation(priority: .utility) { store in
                    try WorkspaceProvisioningService(store: store).preview(request)
                }
                guard !Task.isCancelled else { return }
                preview = prepared
            } catch {
                errorMessage = l10n.workspaceProvisioningErrorMessage(error)
            }
            isLoading = false
        }
    }

    private func createWorkspace() {
        guard let taskID = model.selectedTaskID else { return }
        let request = WorkspaceProvisioningRequest(
            taskID: taskID,
            repositoryRoot: repositoryPath,
            baseRef: baseRef,
            branchName: branchName,
            destinationPath: destinationPath,
            confirmedDirtyBase: confirmedDirtyBase
        )
        model.createIsolatedWorkspace(request)
    }

}
