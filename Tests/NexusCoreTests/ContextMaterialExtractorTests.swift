import Foundation
import XCTest

@testable import NexusCore

final class ContextMaterialExtractorTests: XCTestCase {
    func testPrepareIncludesVisibleTextAndExcludesHiddenAndBinarySources() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textURL = directory.appendingPathComponent("requirements.md")
        let binaryURL = directory.appendingPathComponent("binary.txt")
        try Data("# Requirement\nKeep the API compatible.".utf8).write(to: textURL)
        try Data([0, 1, 2, 3]).write(to: binaryURL)

        let task = taskRecord()
        let notes = [
            TaskNoteRecord(
                id: "visible", taskID: task.id, title: "Visible", body: "Confirmed behavior", isExposedToMCP: true,
                createdAt: "2026-01-01", updatedAt: "2026-01-01"),
            TaskNoteRecord(
                id: "hidden", taskID: task.id, title: "Hidden", body: "Secret", isExposedToMCP: false,
                createdAt: "2026-01-01", updatedAt: "2026-01-01"),
        ]
        let files = [
            fileRecord(id: "text", taskID: task.id, url: textURL),
            fileRecord(id: "binary", taskID: task.id, url: binaryURL),
        ]

        let input = try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: 4,
            supplement: nil,
            notes: notes,
            files: files,
            repository: nil
        )

        XCTAssertEqual(input.baseRevision, 4)
        XCTAssertTrue(input.sources.contains(where: { $0.id == "note:visible" }))
        XCTAssertTrue(input.sources.contains(where: { $0.id == "file:text" }))
        XCTAssertFalse(input.sources.contains(where: { $0.id == "note:hidden" }))
        XCTAssertEqual(input.excludedSources.first(where: { $0.id == "note:hidden" })?.reason, .hidden)
        XCTAssertEqual(input.excludedSources.first(where: { $0.id == "file:binary" })?.reason, .unreadable)
    }

    func testLargeSourceKeepsHeadAndTailWithinPerSourceBudget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.log")
        let body = "HEAD" + String(repeating: "x", count: 49_990) + "TAIL"
        try body.write(to: url, atomically: true, encoding: .utf8)
        let task = taskRecord()

        let input = try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: 1,
            supplement: nil,
            notes: [],
            files: [fileRecord(id: "large", taskID: task.id, url: url)],
            repository: nil
        )
        let source = try XCTUnwrap(input.sources.first(where: { $0.id == "file:large" }))
        XCTAssertTrue(source.reference.truncated)
        XCTAssertEqual(source.content.count, ContextMaterialExtractor.perSourceCharacterLimit)
        XCTAssertTrue(source.content.hasPrefix("HEAD"))
        XCTAssertTrue(source.content.hasSuffix("TAIL"))
        XCTAssertTrue(source.content.contains("[... Nexus omitted middle content ...]"))
        XCTAssertEqual(source.content.prefix(20_000), body.prefix(20_000))
        XCTAssertEqual(source.content.suffix(10_000), body.suffix(10_000))
    }

    func testTotalBudgetExcludesSourcesAfterLimit() throws {
        let task = taskRecord()
        let notes = (0..<4).map { index in
            TaskNoteRecord(
                id: "note-\(index)",
                taskID: task.id,
                title: "Note \(index)",
                body: String(repeating: "\(index)", count: 50_000),
                isExposedToMCP: true,
                createdAt: "2026-01-01",
                updatedAt: "2026-01-01"
            )
        }

        let input = try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: 1,
            supplement: nil,
            notes: notes,
            files: [],
            repository: nil
        )

        XCTAssertLessThanOrEqual(input.totalIncludedCharacters, ContextMaterialExtractor.totalCharacterLimit)
        XCTAssertTrue(input.excludedSources.contains(where: { $0.reason == .budgetExceeded }))
    }

    func testRepositorySourceContainsStableIdentityOnly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try runGit(["init", "-b", "main"], at: directory)
        try runGit(["config", "user.name", "Nexus Test"], at: directory)
        try runGit(["config", "user.email", "nexus-test@example.invalid"], at: directory)
        let readmeURL = directory.appendingPathComponent("README.md")
        try "Initial".write(to: readmeURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: directory)
        try runGit(["commit", "-m", "Initial"], at: directory)

        let task = taskRecord()
        let repository = TaskRepositoryRecord(
            taskID: task.id,
            path: directory.path,
            branch: "main",
            updatedAt: "2026-01-01"
        )
        let original = try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: 1,
            supplement: nil,
            notes: [],
            files: [],
            repository: repository
        )
        try "Changed".write(to: readmeURL, atomically: true, encoding: .utf8)
        try runGit(["switch", "-c", "feature"], at: directory)
        let changedWorkspace = try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: 1,
            supplement: nil,
            notes: [],
            files: [],
            repository: repository
        )

        let originalSource = try XCTUnwrap(original.sources.first(where: { $0.reference.kind == "repository" }))
        let changedSource = try XCTUnwrap(
            changedWorkspace.sources.first(where: { $0.reference.kind == "repository" })
        )
        XCTAssertEqual(originalSource.reference.contentHash, changedSource.reference.contentHash)
        XCTAssertEqual(
            originalSource.reference.fingerprintVersion,
            ContextMaterialExtractor.repositoryFingerprintVersion
        )
        XCTAssertFalse(originalSource.content.contains("Current branch"))
        XCTAssertFalse(originalSource.content.contains("Working tree"))
    }

    func testGitActivityHasASeparateThirtyThousandCharacterBudget() throws {
        let task = taskRecord()
        let activity = GitActivitySnapshot(
            workspacePath: "/tmp/repo",
            linkedBranch: "main",
            currentBranch: "main",
            baselineHeadSHA: "baseline",
            currentHeadSHA: "head",
            state: .commitsAvailable,
            commits: [
                GitCommitSummary(
                    sha: "1234567890abcdef",
                    subject: "Implement checkout migration",
                    committedAt: "2026-01-01T00:00:00Z"
                )
            ],
            committedPaths: [
                GitChangedPath(status: "M", path: "Sources/Checkout.swift", additions: 10, deletions: 2)
            ],
            dirtyPaths: [
                GitChangedPath(status: "M", path: "Sources/Scratch.swift")
            ],
            committedDiff: String(repeating: "committed diff\n", count: 3_000),
            uncommittedDiff: String(repeating: "working tree diff\n", count: 3_000),
            capturedAt: "2026-01-01T00:00:00Z"
        )

        let input = try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: 1,
            supplement: nil,
            notes: [],
            files: [],
            repository: nil,
            gitActivity: activity
        )
        let gitSources = input.sources.filter {
            ContextMaterialExtractor.isGitActivityKind($0.reference.kind)
        }

        XCTAssertEqual(gitSources.count, 2)
        XCTAssertLessThanOrEqual(
            gitSources.reduce(0) { $0 + $1.reference.includedCharacterCount },
            ContextMaterialExtractor.gitActivityCharacterLimit
        )
        XCTAssertTrue(
            gitSources.first(where: {
                $0.reference.kind == ContextMaterialExtractor.committedGitActivityKind
            })?.content.contains("not requirement completion") == true
        )
        XCTAssertTrue(
            gitSources.first(where: {
                $0.reference.kind == ContextMaterialExtractor.uncommittedGitActivityKind
            })?.content.contains("may be temporary") == true
        )
    }

    private func taskRecord() -> TaskRecord {
        TaskRecord(
            id: "task", title: "Checkout migration", goal: "Keep compatibility", status: "active",
            createdAt: "2026-01-01", updatedAt: "2026-01-01")
    }

    private func fileRecord(id: String, taskID: String, url: URL) -> TaskFileRecord {
        TaskFileRecord(
            id: id,
            taskID: taskID,
            displayName: url.lastPathComponent,
            path: url.path,
            fileType: url.pathExtension,
            modifiedAt: "2026-01-01",
            isVisibleToAgent: true,
            createdAt: "2026-01-01",
            updatedAt: "2026-01-01"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed")
    }
}
