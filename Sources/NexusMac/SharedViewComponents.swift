import AppKit
import NexusCore
import SwiftUI

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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: repository == nil ? "folder.badge.questionmark" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                if let repository {
                    HStack(spacing: 8) {
                        Text(projectName(repository))
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if currentBranch != "-", currentBranch != "(unknown)" {
                            Label(currentBranch, systemImage: "arrow.triangle.branch")
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
                    .help(repository.path)
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
                }
                if repository == nil {
                    Button {
                        chooseRepository()
                    } label: {
                        Label(l10n.connectProject, systemImage: "folder")
                    }
                    .controlSize(.small)
                } else {
                    Menu {
                        Button {
                            chooseRepository()
                        } label: {
                            Label(l10n.changeDirectory, systemImage: "folder")
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.018), radius: 10, x: 0, y: 4)
    }

    private func projectName(_ repository: TaskRepositoryRecord) -> String {
        let root = workspaceInfo?.repositoryRoot ?? repository.path
        return URL(fileURLWithPath: root).lastPathComponent
    }
}
