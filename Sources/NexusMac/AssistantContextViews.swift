import AppKit
import NexusCore
import SwiftUI

struct AssistantPreviewCard: View {
    @ObservedObject var model: AppModel
    private var l10n: L10n { model.l10n }

    private let maxVisibleItems = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: model.assistantPreviewIconName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(model.assistantPreviewIconColor)
                    .frame(width: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.assistantPreviewTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    Text(model.assistantPreviewSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Divider()
                .opacity(0.55)

            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.assistantPreviewPrimaryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if !model.assistantExposureEnabled {
                    AssistantPreviewRow(
                        systemImage: "pause.circle",
                        title: l10n.assistantContextPausedTitle,
                        detail: l10n.assistantPreviewPausedBody,
                        tone: .muted
                    )
                } else if model.activeTaskID == nil {
                    AssistantPreviewRow(
                        systemImage: "minus.circle",
                        title: l10n.noActiveWorkSelected,
                        detail: l10n.assistantPreviewNoActiveBody,
                        tone: .muted
                    )
                } else {
                    if model.hasAssistantContextPack {
                        AssistantPreviewRow(
                            systemImage: "checklist.checked",
                            title: l10n.assistantPreviewContextPackTitle,
                            detail: contextPackSnippet,
                            tone: .normal
                        )
                    } else if model.hasAssistantHandoffNote {
                        AssistantPreviewRow(
                            systemImage: "text.alignleft",
                            title: l10n.assistantPreviewHandoffTitle,
                            detail: handoffSnippet,
                            tone: .normal
                        )
                    } else {
                        AssistantPreviewRow(
                            systemImage: "text.alignleft",
                            title: l10n.assistantPreviewHandoffTitle,
                            detail: l10n.assistantPreviewHandoffMissing,
                            tone: .muted
                        )
                    }

                    if visibleMaterialCount == 0 {
                        AssistantPreviewRow(
                            systemImage: "tray",
                            title: l10n.assistantPreviewReadableMaterials,
                            detail: l10n.noReadableMaterialsShort,
                            tone: .muted
                        )
                    } else {
                        ForEach(visiblePreviewItems) { item in
                            AssistantPreviewRow(
                                systemImage: item.systemImage,
                                title: item.title,
                                detail: item.detail,
                                tone: .normal
                            )
                        }
                        if remainingVisibleItemCount > 0 {
                            AssistantPreviewRow(
                                systemImage: "ellipsis",
                                title: l10n.moreReadableItems(remainingVisibleItemCount),
                                detail: nil,
                                tone: .muted
                            )
                        }
                    }
                }

                if model.assistantHiddenMaterialCount > 0 {
                    Text(l10n.assistantPreviewHiddenNotice(model.assistantHiddenMaterialCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 6) {
                AssistantPill(text: l10n.assistantVisiblePill(model.assistantVisibleMaterialCount))
                AssistantPill(text: l10n.assistantHiddenPill(model.assistantHiddenMaterialCount))
                AssistantPill(
                    text: model.hasAssistantContextPack
                        ? l10n.assistantPreviewContextPackPill
                        : l10n.handoffPill(hasHandoff: model.hasAssistantHandoffNote),
                    tone: model.hasAssistantRecoveryContext ? .normal : .muted
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.025), radius: 8, x: 0, y: 3)
    }

    private var visibleMaterialCount: Int {
        model.assistantVisibleNotes.count + model.assistantReadableFiles.count
    }

    private var remainingVisibleItemCount: Int {
        max(0, visiblePreviewItemsAll.count - maxVisibleItems)
    }

    private var visiblePreviewItems: [AssistantPreviewItem] {
        Array(visiblePreviewItemsAll.prefix(maxVisibleItems))
    }

    private var visiblePreviewItemsAll: [AssistantPreviewItem] {
        let notes = model.assistantVisibleNotes.map { material in
            AssistantPreviewItem(
                id: "note-\(material.id)",
                systemImage: "text.page",
                title: material.title,
                detail: l10n.textKind
            )
        }
        let files = model.assistantReadableFiles.map { file in
            AssistantPreviewItem(
                id: "file-\(file.id)",
                systemImage: "doc.text",
                title: file.name,
                detail: file.type
            )
        }
        return notes + files
    }

    private var handoffSnippet: String {
        let cleaned = model.assistantHandoffNote
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 90 else { return cleaned }
        return "\(cleaned.prefix(90))..."
    }

    private var contextPackSnippet: String {
        let cleaned = model.assistantContextPackBrief
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 90 else { return cleaned }
        return "\(cleaned.prefix(90))..."
    }
}

private struct AssistantPreviewItem: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let detail: String?
}

struct AssistantPreviewRow: View {
    enum Tone {
        case normal
        case muted
    }

    let systemImage: String
    let title: String
    let detail: String?
    var tone: Tone = .normal

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(tone == .normal ? Color.accentColor : Color.secondary)
                .frame(width: 15)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone == .normal ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

struct AssistantDetailsContent: View {
    @ObservedObject var model: AppModel
    private var l10n: L10n { model.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AssistantDetailCard(title: l10n.projects, systemImage: "folder") {
                if let repository = model.assistantRepository {
                    AssistantDetailLine(
                        title: URL(fileURLWithPath: repository.path).lastPathComponent,
                        meta: repository.path,
                        detail: branchDetail(repository),
                        tone: model.assistantRepositoryAligned ? .secondary : .orange
                    )
                    if model.assistantDirtyState != .unknown {
                        AssistantDetailLine(
                            title: model.assistantDirtyState == .clean
                                ? l10n.cleanWorkingTree : l10n.modifiedWorkingTree,
                            meta: nil,
                            detail: nil,
                            tone: model.assistantDirtyState == .clean ? .secondary : .orange
                        )
                    }
                } else {
                    AssistantEmptyLine(l10n.noProjectConnectedSentence)
                }
            }

            AssistantDetailCard(
                title: model.hasAssistantContextPack ? l10n.assistantPreviewContextPackTitle : l10n.handoffTitle,
                systemImage: model.hasAssistantContextPack ? "checklist.checked" : "text.alignleft"
            ) {
                if model.hasAssistantRecoveryContext {
                    Text(model.hasAssistantContextPack ? model.assistantContextPackBrief : model.assistantHandoffNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(6)
                        .textSelection(.enabled)
                } else {
                    AssistantEmptyLine(l10n.noHandoffNoteYet)
                }
            }

            AssistantDetailCard(title: l10n.assistantReadableTitle, systemImage: "checkmark.circle") {
                if model.assistantReadableFiles.isEmpty, model.assistantVisibleNotes.isEmpty {
                    AssistantEmptyLine(l10n.noReadableMaterialsShort)
                } else {
                    ForEach(model.assistantVisibleNotes) { material in
                        AssistantMaterialSummary(
                            title: material.title,
                            kind: l10n.textKind,
                            detail: material.body,
                            systemImage: "text.page"
                        )
                    }
                    ForEach(model.assistantReadableFiles, id: \.id) { file in
                        AssistantMaterialSummary(
                            title: file.name,
                            kind: file.type,
                            detail: file.path,
                            systemImage: "doc.text"
                        )
                    }
                }
            }

            AssistantDetailCard(title: l10n.hiddenFromAssistant, systemImage: "eye.slash") {
                if model.assistantHiddenFiles.isEmpty, model.assistantHiddenNoteCount == 0 {
                    AssistantEmptyLine(l10n.noneHidden)
                } else {
                    if model.assistantHiddenNoteCount > 0 {
                        AssistantMaterialSummary(
                            title: l10n.hiddenTextMaterials(model.assistantHiddenNoteCount),
                            kind: l10n.notReadable,
                            detail: l10n.hiddenMaterialDetail,
                            systemImage: "text.page"
                        )
                    }
                    ForEach(model.assistantHiddenFiles, id: \.id) { file in
                        AssistantMaterialSummary(
                            title: file.name,
                            kind: "\(l10n.notReadable) · \(file.type)",
                            detail: file.path,
                            systemImage: "doc.text"
                        )
                    }
                }
            }
        }
    }

    private func branchDetail(_ repository: TaskRepositoryRecord) -> String {
        l10n.linkedBranchDetail(linked: repository.branch, current: model.assistantCurrentBranch)
    }
}

struct AssistantDetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AssistantDetailLine: View {
    let title: String
    let meta: String?
    let detail: String?
    var tone: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let meta, !meta.isEmpty {
                Text(meta)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(meta)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct AssistantMaterialSummary: View {
    let title: String
    let kind: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(kind)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct AssistantEmptyLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}

struct AssistantConnectionPopover: View {
    @ObservedObject var model: AppModel
    @State private var showDoctor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .fill(statusTint.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: model.assistantConnectionIconName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.assistantConnectionStatus)
                        .font(.title3.weight(.semibold))
                    Text(model.assistantConnectionDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusTint.opacity(model.assistantExposureEnabled ? 0.06 : 0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(statusTint.opacity(0.14), lineWidth: 1)
            )

            HStack(spacing: 8) {
                connectionTile(model.l10n.activeWorkTile, model.activeTitle ?? model.l10n.none)
                connectionTile(
                    model.l10n.helperTile, model.assistantHelperInstalled ? model.l10n.installed : model.l10n.missing)
            }

            HStack(spacing: 8) {
                Button {
                    model.toggleAssistantExposure()
                } label: {
                    Label(
                        model.assistantExposureEnabled ? model.l10n.pause : model.l10n.enable,
                        systemImage: model.assistantExposureEnabled ? "pause.fill" : "play.fill")
                }
                Button {
                    model.testAssistantConnection()
                } label: {
                    Label(model.l10n.testConnection, systemImage: "checkmark.circle")
                }
                Button {
                    model.copyMCPConfig()
                } label: {
                    Label(model.l10n.copyConfig, systemImage: "doc.on.doc")
                }
            }
            .controlSize(.small)
            .labelStyle(.titleAndIcon)

            DisclosureGroup(isExpanded: $showDoctor) {
                Text(
                    model.assistantConnectionDoctor.isEmpty
                        ? model.l10n.noDoctorOutput : model.assistantConnectionDoctor
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Color.secondary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 7)
            } label: {
                AssistantDisclosureLabel(title: model.l10n.diagnostics)
            }
        }
        .frame(width: 328)
        .onAppear {
            model.refreshAssistantConnectionSnapshot()
        }
    }

    private var statusTint: Color {
        if !model.assistantExposureEnabled {
            return .secondary
        }
        return model.assistantConnectionReady ? .green : .secondary
    }

    private func connectionTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .help(value)
    }
}

struct AssistantPill: View {
    enum Tone {
        case normal
        case muted
    }

    let text: String
    var tone: Tone = .normal

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tone == .normal ? Color.secondary : Color.secondary.opacity(0.72))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(tone == .normal ? 0.08 : 0.045))
            .clipShape(Capsule())
    }
}

struct AssistantDisclosureLabel: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.09))
                    .clipShape(Capsule())
            }
        }
        .frame(minHeight: 24)
    }
}

struct AssistantIssueRow: View {
    let issue: AssistantContextIssue

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: issue.systemImage)
                .font(.caption)
                .foregroundStyle(issue.tone == .warning ? Color.orange : Color.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.caption.weight(.semibold))
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(issue.tone == .warning ? Color.orange.opacity(0.07) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
