import AppKit
import NexusCore
import SwiftUI

struct ProjectSummary: View {
    let repository: TaskRepositoryRecord?
    let currentBranch: String
    let dirtyState: GitWorkingTreeState
    let aligned: Bool
    let l10n: L10n

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                if let repository {
                    Text(URL(fileURLWithPath: repository.path).lastPathComponent)
                        .font(.caption.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(URL(fileURLWithPath: repository.path).deletingLastPathComponent().path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(currentBranch)
                            .foregroundStyle(aligned ? Color.secondary : Color.orange)
                        if dirtyState != .unknown {
                            Text(dirtyState == .clean ? l10n.cleanWorkingTree : l10n.modifiedWorkingTree)
                                .foregroundStyle(dirtyState == .clean ? Color.secondary : Color.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                } else {
                    Text(l10n.noProjectConnected)
                        .font(.caption.weight(.semibold))
                    Text(l10n.connectProjectHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ActiveContextFooter: View {
    let activeTitle: String?
    let l10n: L10n

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(activeTitle == nil ? Color.secondary.opacity(0.55) : Color.green.opacity(0.75))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.assistantCurrentlyReads)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(activeTitle ?? l10n.notConnected)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(activeTitle == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

struct GitBranchSuggestion: Equatable {
    let taskID: String
    let taskTitle: String
    let repositoryPath: String
    let branch: String
}

struct SidebarProjectGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let tasks: [TaskRecord]
}

struct ProjectTaskGroupView: View {
    let group: SidebarProjectGroup
    let isExpanded: Bool
    let activeTaskID: String?
    let selectedTaskID: String?
    let repositoriesByTaskID: [String: TaskRepositoryRecord]
    let workspaceInfoByTaskID: [String: GitWorkspaceInfo]
    let workspaceBindingsByTaskID: [String: ContextBindingRecord]
    let availableWorktrees: [GitWorkspaceInfo]
    let unboundTasks: [TaskRecord]
    let isPlaceholder: (TaskRecord) -> Bool
    let l10n: L10n
    let toggleExpanded: () -> Void
    let refreshWorktrees: () -> Void
    let select: (TaskRecord) -> Void
    let createWork: (GitWorkspaceInfo) -> Void
    let bindWorktree: (GitWorkspaceInfo, TaskRecord) -> Void
    let archive: (TaskRecord) -> Void
    let delete: (TaskRecord) -> Void
    @State private var isHovered = false
    @State private var showsAvailableWorktrees = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                Button(action: toggleExpanded) {
                    HStack(alignment: .center, spacing: 7) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 9)
                        Image(systemName: "folder")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(group.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if containsActiveTask {
                                    Circle()
                                        .fill(Color.green.opacity(0.85))
                                        .frame(width: 5, height: 5)
                                }
                            }
                            if !group.path.isEmpty {
                                Text(group.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("\(group.tasks.count)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(headerBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .help(group.path)
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group.tasks) { task in
                        TaskNavigationRow(
                            task: task,
                            isActive: task.id == activeTaskID,
                            isSelected: task.id == selectedTaskID,
                            isPlaceholder: isPlaceholder(task),
                            l10n: l10n,
                            metadata: workspaceMetadata(for: task),
                            metadataHelp: repositoriesByTaskID[task.id]?.path
                        ) {
                            select(task)
                        } archiveAction: {
                            archive(task)
                        } deleteAction: {
                            delete(task)
                        }
                        .padding(.leading, 22)
                    }
                    if !availableWorktrees.isEmpty {
                        availableWorktreesSection
                            .padding(.leading, 22)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            if isExpanded {
                refreshWorktrees()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                refreshWorktrees()
            } else {
                showsAvailableWorktrees = false
            }
        }
    }

    private var containsActiveTask: Bool {
        guard let activeTaskID else { return false }
        return group.tasks.contains { $0.id == activeTaskID }
    }

    private var containsSelectedTask: Bool {
        guard let selectedTaskID else { return false }
        return group.tasks.contains { $0.id == selectedTaskID }
    }

    private var headerBackground: Color {
        if containsSelectedTask && !isExpanded {
            return Color.accentColor.opacity(0.11)
        }
        if isHovered {
            return Color.secondary.opacity(0.06)
        }
        return Color.clear
    }

    private func workspaceMetadata(for task: TaskRecord) -> String? {
        guard let repository = repositoriesByTaskID[task.id] else { return nil }
        let branch = repository.branch
        let workspaceKind: String
        if let info = workspaceInfoByTaskID[task.id] {
            workspaceKind =
                info.kind == "worktree"
                ? l10n.worktreeName(URL(fileURLWithPath: info.path).lastPathComponent)
                : l10n.mainCheckout
        } else {
            workspaceKind = URL(fileURLWithPath: repository.path).lastPathComponent
        }
        let bindingMark = workspaceBindingsByTaskID[task.id] == nil ? "" : " · \(l10n.contextPinned)"
        return "\(branch) · \(workspaceKind)\(bindingMark)"
    }

    private var availableWorktreesSection: some View {
        DisclosureGroup(isExpanded: $showsAvailableWorktrees) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(availableWorktrees) { workspace in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(workspace.branch)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(URL(fileURLWithPath: workspace.path).lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Menu {
                            Button {
                                createWork(workspace)
                            } label: {
                                Label(l10n.createWorkFromWorkspace, systemImage: "plus")
                            }
                            if !unboundTasks.isEmpty {
                                Menu {
                                    ForEach(unboundTasks) { task in
                                        Button(task.title) {
                                            bindWorktree(workspace, task)
                                        }
                                    }
                                } label: {
                                    Label(l10n.linkToExistingWork, systemImage: "link")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(.leading, 10)
                    .padding(.vertical, 5)
                    .help(workspace.path)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                    .font(.caption2)
                Text(l10n.availableWorkspaces)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(availableWorktrees.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
    }
}

struct GitSuggestionNotice: View {
    let suggestion: GitBranchSuggestion
    let l10n: L10n
    let switchAction: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.currentBranchHasWork)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("\(suggestion.taskTitle) · \(suggestion.branch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(l10n.openMatchedWork) { switchAction() }
                .controlSize(.small)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
