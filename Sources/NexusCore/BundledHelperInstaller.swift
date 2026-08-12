import Foundation

public struct BundledHelperInstallation: Sendable {
    public let helperVersion: String
    public let nodeVersion: String
    public let helperDirectory: URL
    public let stableShim: URL

    public init(helperVersion: String, nodeVersion: String, helperDirectory: URL, stableShim: URL) {
        self.helperVersion = helperVersion
        self.nodeVersion = nodeVersion
        self.helperDirectory = helperDirectory
        self.stableShim = stableShim
    }
}

public enum BundledHelperInstallError: LocalizedError, Sendable {
    case resourceMissing(URL)
    case manifestInvalid(String)
    case helperNotExecutable(URL)
    case entrypointMissing(URL)
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing(let url):
            return "Bundled MCP Helper resource is missing: \(url.path)"
        case .manifestInvalid(let reason):
            return "Bundled MCP Helper manifest is invalid: \(reason)"
        case .helperNotExecutable(let url):
            return "Bundled Node Runtime is not executable: \(url.path)"
        case .entrypointMissing(let url):
            return "Bundled MCP Helper entrypoint is missing: \(url.path)"
        case .installationFailed(let reason):
            return "Could not install the bundled MCP Helper: \(reason)"
        }
    }
}

public enum BundledHelperInstaller {
    private struct Manifest: Decodable {
        let helperVersion: String
        let nodeVersion: String
        let entrypoint: String
    }

    public static func install(
        from resourceDirectory: URL,
        applicationSupportDirectory: URL = NexusPaths.applicationSupportDirectory
    ) throws -> BundledHelperInstallation {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resourceDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw BundledHelperInstallError.resourceMissing(resourceDirectory)
        }

        let manifestURL = resourceDirectory.appendingPathComponent("manifest.json")
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw BundledHelperInstallError.manifestInvalid(error.localizedDescription)
        }

        let resourceNode = resourceDirectory.appendingPathComponent("node")
        guard fileManager.isExecutableFile(atPath: resourceNode.path) else {
            throw BundledHelperInstallError.helperNotExecutable(resourceNode)
        }
        let resourceEntrypoint = resourceDirectory.appendingPathComponent(manifest.entrypoint)
        guard fileManager.fileExists(atPath: resourceEntrypoint.path) else {
            throw BundledHelperInstallError.entrypointMissing(resourceEntrypoint)
        }

        let helpersDirectory = applicationSupportDirectory.appendingPathComponent("helpers", isDirectory: true)
        let installedDirectory = helpersDirectory.appendingPathComponent(manifest.helperVersion, isDirectory: true)
        let stableBinDirectory = applicationSupportDirectory.appendingPathComponent("bin", isDirectory: true)
        let stableShim = stableBinDirectory.appendingPathComponent("nexus-mcp")
        do {
            try fileManager.createDirectory(at: helpersDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: stableBinDirectory, withIntermediateDirectories: true)

            if !isValidInstalledHelper(installedDirectory, entrypoint: manifest.entrypoint) {
                let stagingDirectory = helpersDirectory.appendingPathComponent(".install-\(UUID().uuidString)")
                try? fileManager.removeItem(at: stagingDirectory)
                try fileManager.copyItem(at: resourceDirectory, to: stagingDirectory)
                try? fileManager.removeItem(at: installedDirectory)
                try fileManager.moveItem(at: stagingDirectory, to: installedDirectory)
            }

            let installedNode = installedDirectory.appendingPathComponent("node")
            let installedEntrypoint = installedDirectory.appendingPathComponent(manifest.entrypoint)
            try writeStableShim(
                at: stableShim,
                node: installedNode,
                entrypoint: installedEntrypoint,
                applicationSupportDirectory: applicationSupportDirectory
            )
            return BundledHelperInstallation(
                helperVersion: manifest.helperVersion,
                nodeVersion: manifest.nodeVersion,
                helperDirectory: installedDirectory,
                stableShim: stableShim
            )
        } catch let error as BundledHelperInstallError {
            throw error
        } catch {
            throw BundledHelperInstallError.installationFailed(error.localizedDescription)
        }
    }

    private static func isValidInstalledHelper(_ directory: URL, entrypoint: String) -> Bool {
        let fileManager = FileManager.default
        return fileManager.isExecutableFile(atPath: directory.appendingPathComponent("node").path)
            && fileManager.fileExists(atPath: directory.appendingPathComponent(entrypoint).path)
    }

    private static func writeStableShim(
        at url: URL,
        node: URL,
        entrypoint: URL,
        applicationSupportDirectory: URL
    ) throws {
        let script = """
            #!/bin/sh
            set -eu
            if [ -z "${NEXUS_HOME:-}" ]; then
              NEXUS_HOME=\(shellQuote(applicationSupportDirectory.path))
            fi
            export NEXUS_HOME
            exec \(shellQuote(node.path)) \(shellQuote(entrypoint.path)) "$@"
            """
        try Data(script.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
