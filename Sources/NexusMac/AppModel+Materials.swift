import AppKit
import Foundation
import NexusCore
import UniformTypeIdentifiers

@MainActor
extension AppModel {
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let selectedTaskID else { return false }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    self.addFile(url: url, taskID: selectedTaskID)
                }
            }
        }
        return true
    }

    func addFile(url: URL, taskID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let wasDuplicate = try await performStoreOperation { store in
                    let before = try store.listFiles(taskID: taskID).count
                    _ = try store.addFile(taskID: taskID, fileURL: url, visibleToAgent: true)
                    return try store.listFiles(taskID: taskID).count == before
                }
                showToast(wasDuplicate ? l10n.fileAlreadyAdded : l10n.fileAdded)
                refresh()
            } catch {
                showToast(l10n.addFileFailed)
                message = "Add file error: \(error)"
            }
        }
    }

    func updateFile(_ file: TaskFileRecord) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.updateFile(
                        id: file.id,
                        taskID: file.taskID,
                        displayName: file.displayName,
                        visibleToAgent: file.isVisibleToAgent
                    )
                }
                showToast(file.isVisibleToAgent ? l10n.visibleToast : l10n.hiddenToast)
                refresh()
            } catch {
                showToast(l10n.updateFailed)
                message = "Update file error: \(error)"
            }
        }
    }

    func removeFile(_ file: TaskFileRecord) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.removeFileReference(id: file.id, taskID: file.taskID)
                }
                showToast(l10n.referenceRemoved)
                refresh()
            } catch {
                showToast(l10n.removeFailed)
                message = "Remove file error: \(error)"
            }
        }
    }

    func prepareTextMaterial() {
        newTextMaterialTitle = ""
        newTextMaterialBody = ""
        newTextMaterialVisible = true
        showAddTextMaterialSheet = true
    }

    func addTextMaterial() {
        guard let selectedTaskID else { return }
        let body = newTextMaterialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            showToast(l10n.addTitleAndBody)
            return
        }
        let title = textMaterialTitle(from: newTextMaterialTitle, body: body)
        addTextMaterial(
            taskID: selectedTaskID, title: title, body: body, exposed: newTextMaterialVisible,
            toast: l10n.textMaterialAdded)
    }

    func addClipboardTextMaterial() {
        guard let selectedTaskID else { return }
        let body = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else {
            showToast(l10n.clipboardEmpty)
            return
        }
        let title = textMaterialTitle(from: "", body: body)
        addTextMaterial(
            taskID: selectedTaskID, title: title, body: body, exposed: true, toast: l10n.clipboardMaterialAdded)
    }

    private func addTextMaterial(taskID: String, title: String, body: String, exposed: Bool, toast: String) {
        let normalizedBody = normalizedText(body)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await performStoreOperation { store -> TextMaterialAddOutcome in
                    if let existing = try store.listNotes(taskID: taskID).first(where: {
                        Self.normalizedTextValue($0.body) == normalizedBody
                    }) {
                        if existing.isExposedToMCP != exposed {
                            try store.updateNote(
                                id: existing.id,
                                taskID: taskID,
                                title: existing.title,
                                body: existing.body,
                                exposed: exposed
                            )
                            return .visibilityChanged
                        }
                        return .duplicate
                    }
                    _ = try store.addNote(taskID: taskID, title: title, body: body, exposed: exposed)
                    return .added
                }
                switch outcome {
                case .visibilityChanged:
                    showToast(exposed ? l10n.visibleToast : l10n.hiddenToast)
                case .duplicate:
                    showToast(l10n.textMaterialAlreadyAdded)
                case .added:
                    showToast(toast)
                }
                refresh()
            } catch {
                showToast(l10n.addTextFailed)
                message = "Add text material error: \(error)"
            }
        }
    }

    func updateTextMaterial(_ material: TaskNoteRecord) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.updateNote(
                        id: material.id,
                        taskID: material.taskID,
                        title: material.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Untitled text"
                            : material.title,
                        body: material.body,
                        exposed: material.isExposedToMCP
                    )
                }
                showToast(material.isExposedToMCP ? l10n.visibleToast : l10n.hiddenToast)
                refresh()
            } catch {
                showToast(l10n.updateFailed)
                message = "Update text material error: \(error)"
            }
        }
    }

    func requestRemoveTextMaterial(_ material: TaskNoteRecord) {
        confirmation = ConfirmationRequest(
            kind: .removeTextMaterial(material.id, material.taskID),
            title: l10n.removeMaterialTitle(material.title),
            message: l10n.removeTextMaterialMessage,
            confirmTitle: l10n.removeReference
        )
    }

    func removeTextMaterial(id: String, taskID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performStoreOperation { store in
                    try store.removeNote(id: id, taskID: taskID)
                }
                showToast(l10n.textMaterialRemoved)
                refresh()
            } catch {
                showToast(l10n.removeFailed)
                message = "Remove text material error: \(error)"
            }
        }
    }

    func revealFile(_ file: TaskFileRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    private func textMaterialTitle(from title: String, body: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let firstLine =
            body
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? l10n.textKind
        return String(firstLine.prefix(36))
    }

    private func normalizedText(_ text: String) -> String {
        Self.normalizedTextValue(text)
    }

    nonisolated private static func normalizedTextValue(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum TextMaterialAddOutcome: Sendable {
    case added
    case duplicate
    case visibilityChanged
}
