import Foundation
import NexusCore

enum ReadableFileType {
    static func label(for file: TaskFileRecord) -> String {
        label(identifier: file.fileType, path: file.path)
    }

    static func label(identifier: String, path: String) -> String {
        let lowered = identifier.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let mapped: [String: String] = [
            "public.json": "JSON",
            "json": "JSON",
            "net.daringfireball.markdown": "Markdown",
            "public.markdown": "Markdown",
            "md": "Markdown",
            "markdown": "Markdown",
            "org.iso.sql": "SQL",
            "sql": "SQL",
            "public.plain-text": "Text",
            "txt": "Text",
            "public.source-code": "Code",
            "directory": "Folder",
        ]
        if let value = mapped[lowered] {
            return value
        }
        if !ext.isEmpty {
            return ext.uppercased()
        }
        if lowered.contains("json") { return "JSON" }
        if lowered.contains("markdown") { return "Markdown" }
        if lowered.contains("sql") { return "SQL" }
        if lowered.contains("text") { return "Text" }
        return "File"
    }

    static func shortDate(_ isoString: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: isoString) else {
            return isoString
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
