import Foundation

public enum NexusPaths {
    public static let applicationSupportDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["NEXUS_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nexus", isDirectory: true)
    }()

    public static let databaseURL: URL = {
        applicationSupportDirectory.appendingPathComponent("Nexus.sqlite")
    }()

    public static let runtimeStatusURL: URL = {
        applicationSupportDirectory.appendingPathComponent("Nexus.runtime.json")
    }()

    public static func ensureApplicationSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
    }
}
