import Foundation

enum TaskFileFactory {
    static func make(
        taskID: String, fileURL: URL, visibleToAgent: Bool, now: String, isoFormatter: ISO8601DateFormatter
    ) throws -> TaskFileRecord {
        let normalizedURL = normalizedFileURL(fileURL)
        let values = try normalizedURL.resourceValues(forKeys: [
            .contentModificationDateKey, .typeIdentifierKey, .isDirectoryKey,
        ])
        let modified = values.contentModificationDate.map { isoFormatter.string(from: $0) } ?? now
        let fileType =
            values.isDirectory == true
            ? "directory" : (values.typeIdentifier ?? normalizedURL.pathExtension.lowercased())
        return TaskFileRecord(
            id: UUID().uuidString.lowercased(),
            taskID: taskID,
            displayName: normalizedURL.lastPathComponent,
            path: normalizedURL.path,
            fileType: fileType.isEmpty ? "file" : fileType,
            modifiedAt: modified,
            isVisibleToAgent: visibleToAgent,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func normalizedFileURL(_ url: URL) -> URL {
        let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
        return fileURL.standardizedFileURL.resolvingSymlinksInPath()
    }
}
