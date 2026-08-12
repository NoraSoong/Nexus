import Foundation
import XCTest

@testable import NexusCore

final class BundledHelperInstallerTests: XCTestCase {
    func testInstallsVersionedHelperAndStableShim() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-helper-\(UUID().uuidString)", isDirectory: true)
        let resource = root.appendingPathComponent("resource", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: resource.appendingPathComponent("dist", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: resource.appendingPathComponent("node"))
        try Data("console.log('test')\n".utf8).write(to: resource.appendingPathComponent("dist/index.js"))
        try Data(
            """
            {"helperVersion":"0.1.0","nodeVersion":"v26.5.0","entrypoint":"dist/index.js"}
            """.utf8
        ).write(to: resource.appendingPathComponent("manifest.json"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: resource.appendingPathComponent("node").path
        )

        let first = try BundledHelperInstaller.install(
            from: resource,
            applicationSupportDirectory: support
        )
        let second = try BundledHelperInstaller.install(
            from: resource,
            applicationSupportDirectory: support
        )

        XCTAssertEqual(first.helperVersion, "0.1.0")
        XCTAssertEqual(first.nodeVersion, "v26.5.0")
        XCTAssertEqual(first.helperDirectory, second.helperDirectory)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: first.stableShim.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: first.helperDirectory.appendingPathComponent("dist/index.js").path))
        let shim = try String(contentsOf: first.stableShim, encoding: .utf8)
        XCTAssertTrue(shim.contains("NEXUS_HOME"))
        XCTAssertTrue(shim.contains("NEXUS_HOME='/"))
        XCTAssertFalse(shim.contains("NEXUS_HOME=\"${NEXUS_HOME:-'/"))
        XCTAssertTrue(shim.contains("node"))
    }
}
