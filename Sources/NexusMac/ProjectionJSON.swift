import Foundation
import NexusCore

enum ProjectionJSON {
    static func filePreview(from file: TaskFileRecord) -> AgentFilePreview {
        AgentFilePreview(
            id: file.id,
            name: file.displayName,
            path: file.path,
            type: ReadableFileType.label(for: file),
            visibility: file.isVisibleToAgent ? "readable" : "hidden"
        )
    }

    static func brief(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let brief = object["brief"] as? String
        else {
            return nil
        }
        return brief
    }

    static func string(from raw: String, key: String) -> String? {
        guard let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object[key] as? String
    }

    static func nestedString(from raw: String, objectKey: String, key: String) -> String? {
        guard let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let nested = object[objectKey] as? [String: Any]
        else {
            return nil
        }
        return nested[key] as? String
    }

    static func files(from raw: String, key: String) -> [AgentFilePreview] {
        guard let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object[key] as? [[String: Any]]
        else {
            return []
        }
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return AgentFilePreview(
                id: id,
                name: row["display_name"] as? String ?? id,
                path: row["path"] as? String ?? "",
                type: ReadableFileType.label(
                    identifier: row["file_type"] as? String ?? "",
                    path: row["path"] as? String ?? ""
                ),
                visibility: row["visibility"] as? String ?? (key == "hidden_files" ? "hidden" : "readable")
            )
        }
    }

    static func prettyString(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return text
    }
}
