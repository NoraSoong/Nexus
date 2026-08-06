import Foundation

public enum NexusRuntime {
    public static func markAppRunning(exposureEnabled: Bool = true) throws {
        try NexusPaths.ensureApplicationSupportDirectory()
        let payload: [String: Any] = [
            "schema_version": 1,
            "state": exposureEnabled ? "running" : "paused",
            "exposure_enabled": exposureEnabled,
            "app_pid": Int(ProcessInfo.processInfo.processIdentifier),
            "last_seen_at": timestamp(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: NexusPaths.runtimeStatusURL, options: [.atomic])
    }

    public static func markAppStopped() throws {
        try NexusPaths.ensureApplicationSupportDirectory()
        let payload: [String: Any] = [
            "schema_version": 1,
            "state": "stopped",
            "app_pid": Int(ProcessInfo.processInfo.processIdentifier),
            "last_seen_at": timestamp(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: NexusPaths.runtimeStatusURL, options: [.atomic])
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
