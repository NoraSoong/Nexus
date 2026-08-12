import AppKit
import NexusCore
import SwiftUI

struct ResumeField: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ResumeFileList: View {
    let files: [AgentFilePreview]
    let l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(l10n.assistantReadableTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(files) { file in
                HStack(spacing: 6) {
                    Text(file.name)
                        .lineLimit(1)
                    Text(file.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FileRow: View {
    @Binding var file: TaskFileRecord
    let l10n: L10n
    let save: () -> Void
    let remove: () -> Void
    let reveal: () -> Void
    @State private var isRenaming = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if isRenaming {
                        TextField(l10n.fileName, text: $file.displayName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                save()
                                isRenaming = false
                            }
                    } else {
                        Text(file.displayName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 7) {
                        Text(ReadableFileType.label(for: file))
                        Text("\(l10n.updatedPrefix) \(ReadableFileType.shortDate(file.modifiedAt))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(l10n.visibleToAssistant, isOn: $file.isVisibleToAgent)
                    .toggleStyle(.checkbox)
                    .onChange(of: file.isVisibleToAgent) { _, _ in save() }
                    .help(file.isVisibleToAgent ? l10n.fileMaterialIncludedStatus : l10n.materialExcludedStatus)
                Menu {
                    Button(l10n.rename) { isRenaming = true }
                    Button(l10n.revealInFinder) { reveal() }
                    Button(l10n.copyFullPath) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(file.path, forType: .string)
                    }
                    Divider()
                    Button(l10n.removeReference, role: .destructive) { remove() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            Text(file.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(file.path)
        }
        .padding(10)
        .background(isHovered ? Color.secondary.opacity(0.075) : Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .onChange(of: isRenaming) { oldValue, newValue in
            if oldValue && !newValue {
                save()
            }
        }
    }
}

struct TextMaterialRow: View {
    @Binding var material: TaskNoteRecord
    let l10n: L10n
    let save: () -> Void
    let remove: () -> Void
    @State private var isRenaming = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.page")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if isRenaming {
                        TextField(l10n.materialTitle, text: $material.title)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                save()
                                isRenaming = false
                            }
                    } else {
                        Text(material.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 7) {
                        Text(l10n.textKind)
                        Text("\(l10n.updatedPrefix) \(ReadableFileType.shortDate(material.updatedAt))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(l10n.visibleToAssistant, isOn: $material.isExposedToMCP)
                    .toggleStyle(.checkbox)
                    .onChange(of: material.isExposedToMCP) { _, _ in save() }
                    .help(material.isExposedToMCP ? l10n.textMaterialIncludedStatus : l10n.materialExcludedStatus)
                Menu {
                    Button(l10n.rename) { isRenaming = true }
                    Button(l10n.copyBody) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(material.body, forType: .string)
                    }
                    Divider()
                    Button(l10n.removeTextMaterial, role: .destructive) { remove() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            Text(material.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(isHovered ? Color.secondary.opacity(0.075) : Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .onChange(of: isRenaming) { oldValue, newValue in
            if oldValue && !newValue {
                save()
            }
        }
    }
}

struct SupplementEditor: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool
    private let contentInsets = EdgeInsets(top: 14, leading: 12, bottom: 10, trailing: 12)

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .focused($isFocused)
            .scrollContentBackground(.hidden)
            .padding(contentInsets)
            .overlay(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isFocused {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(contentInsets)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct AgentFilePreview: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let type: String
    let visibility: String
}

struct AgentFilePreviewRow: View {
    let file: AgentFilePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.name)
                .lineLimit(1)
            Text(file.type)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(file.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct TextMaterialPreviewRow: View {
    let material: TaskNoteRecord
    let l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(material.title)
                .lineLimit(1)
            Text(l10n.textKind)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(material.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}
