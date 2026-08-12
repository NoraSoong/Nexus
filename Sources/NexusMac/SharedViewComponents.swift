import AppKit
import NexusCore
import SwiftUI

struct NexusPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.028), radius: 12, x: 0, y: 5)
    }
}

struct NexusPanelHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let accent: Color
    let trailing: String?

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        accent: Color = .accentColor,
        trailing: String? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }
}

struct ContextReadyBadge: View {
    let isReady: Bool
    let l10n: L10n

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isReady ? Color.green : Color.secondary.opacity(0.55))
                .frame(width: 8, height: 8)
            Text(isReady ? l10n.activeBadge : l10n.previewBadge)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(isReady ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}

struct EmptyWorkspacePanel: View {
    let l10n: L10n
    let createWork: () -> Void
    let openExistingWork: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(l10n.emptyWorkspaceTitle)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(l10n.emptyWorkspaceMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 10) {
                Button {
                    createWork()
                } label: {
                    Label(l10n.createFirstWork, systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openExistingWork()
                } label: {
                    Label(l10n.openExistingWork, systemImage: "magnifyingglass")
                }
            }
            .controlSize(.large)
        }
        .padding(34)
        .frame(maxWidth: 620)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.025), radius: 18, x: 0, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
    }
}

struct ProjectContextBar: View {
    let repository: TaskRepositoryRecord?
    let workspaceInfo: GitWorkspaceInfo?
    let currentBranch: String
    let dirtyState: GitWorkingTreeState
    let aligned: Bool
    let isCurrentWork: Bool
    let l10n: L10n
    let makeCurrent: () -> Void
    let useCurrentBranch: () -> Void
    let chooseRepository: () -> Void
    let createWorkspace: () -> Void
    let copyWorkspacePath: () -> Void
    let revealWorkspace: () -> Void
    let openWorkspaceInTerminal: () -> Void
    let unlinkWorkspace: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(repository == nil ? 0.07 : 0.11))
                Image(systemName: repository == nil ? "folder.badge.questionmark" : "folder")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(repository == nil ? .secondary : Color.accentColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                if let repository {
                    HStack(spacing: 8) {
                        Text(projectName(repository))
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    .help(repository.path)
                    HStack(spacing: 7) {
                        Label(
                            workspaceInfo?.kind == "worktree"
                                ? l10n.isolatedCodeWorkspace
                                : l10n.mainCodeWorkspace,
                            systemImage: workspaceInfo?.kind == "worktree" ? "square.stack.3d.up" : "folder"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if currentBranch != "-", currentBranch != "(unknown)" {
                            Text(currentBranch)
                                .font(.caption)
                                .foregroundStyle(aligned ? Color.secondary : Color.orange)
                                .lineLimit(1)
                        }
                        if dirtyState == .modified {
                            Text(l10n.modifiedWorkingTree)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    if !aligned, currentBranch != "-", currentBranch != "(unknown)" {
                        HStack(spacing: 5) {
                            Text("\(l10n.linkedBranch): \(repository.branch)")
                            Text("·")
                            Text("\(l10n.currentBranch): \(currentBranch)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    }
                } else {
                    Text(l10n.noProjectConnected)
                        .font(.callout.weight(.semibold))
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 7) {
                if !isCurrentWork {
                    Button {
                        makeCurrent()
                    } label: {
                        Label(l10n.makeActive, systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .controlSize(.small)
                }
                if repository != nil, !aligned {
                    Button {
                        useCurrentBranch()
                    } label: {
                        Label(l10n.useCurrentBranch, systemImage: "arrow.triangle.branch")
                    }
                    .controlSize(.small)
                    .help(l10n.useCurrentBranchHelp)
                }
                if repository == nil {
                    Menu {
                        Button {
                            chooseRepository()
                        } label: {
                            Label(l10n.chooseExistingWorkspace, systemImage: "folder")
                        }
                        Button {
                            createWorkspace()
                        } label: {
                            Label(l10n.createIsolatedWorkspace, systemImage: "square.stack.3d.up")
                        }
                    } label: {
                        Label(l10n.connectProject, systemImage: "folder")
                    }
                    .controlSize(.small)
                } else {
                    Menu {
                        Button {
                            chooseRepository()
                        } label: {
                            Label(l10n.chooseExistingWorkspace, systemImage: "folder")
                        }
                        Divider()
                        Button {
                            copyWorkspacePath()
                        } label: {
                            Label(l10n.copyWorkspacePath, systemImage: "doc.on.doc")
                        }
                        Button {
                            revealWorkspace()
                        } label: {
                            Label(l10n.revealWorkspaceInFinder, systemImage: "folder.badge.gearshape")
                        }
                        Button {
                            openWorkspaceInTerminal()
                        } label: {
                            Label(l10n.openWorkspaceInTerminal, systemImage: "terminal")
                        }
                        Divider()
                        Button(role: .destructive) {
                            unlinkWorkspace()
                        } label: {
                            Label(l10n.removeWorkspaceLink, systemImage: "link.badge.minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help(l10n.changeDirectory)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.028), radius: 12, x: 0, y: 5)
    }

    private func projectName(_ repository: TaskRepositoryRecord) -> String {
        let root = workspaceInfo?.repositoryRoot ?? repository.path
        return URL(fileURLWithPath: root).lastPathComponent
    }
}
