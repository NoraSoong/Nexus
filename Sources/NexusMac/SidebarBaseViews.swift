import AppKit
import NexusCore
import SwiftUI

struct TaskNavigationRow: View {
    let task: TaskRecord
    let isActive: Bool
    let isSelected: Bool
    let isPlaceholder: Bool
    let l10n: L10n
    var metadata: String? = nil
    var metadataHelp: String? = nil
    let action: () -> Void
    var archiveAction: (() -> Void)? = nil
    var deleteAction: (() -> Void)? = nil
    var hoverAction: ((Bool) -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(isPlaceholder ? l10n.unnamedWork : task.title)
                            .font(.callout.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isPlaceholder ? .secondary : .primary)
                            .lineLimit(1)
                        if isActive {
                            Circle()
                                .fill(Color.green.opacity(0.85))
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(goalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let metadata, !metadata.isEmpty {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(metadataHelp ?? metadata)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover {
            isHovered = $0
            hoverAction?($0)
        }
        .contextMenu {
            if let archiveAction {
                Button {
                    archiveAction()
                } label: {
                    Label(l10n.archiveWork, systemImage: "archivebox")
                }
            }
            if let deleteAction {
                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label(l10n.deleteWork, systemImage: "trash")
                }
            }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.13)
        }
        if isHovered {
            return Color.secondary.opacity(0.065)
        }
        return Color.clear
    }

    private var goalText: String {
        if isPlaceholder {
            return l10n.emptyWorkHint
        }
        return task.goal.isEmpty ? l10n.noGoalYet : task.goal
    }
}

struct SidebarSectionHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            accessory
        }
        .padding(.horizontal, 5)
        .padding(.top, 2)
    }
}

extension SidebarSectionHeader where Accessory == EmptyView {
    init(title: String) {
        self.title = title
        self.accessory = EmptyView()
    }
}

struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(text == "Active Task" ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
            .foregroundStyle(text == "Active Task" ? .green : .secondary)
            .clipShape(Capsule())
    }
}
