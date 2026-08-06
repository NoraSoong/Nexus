import Foundation
import XCTest

@testable import NexusCore

final class GitActivityTests: XCTestCase {
    func testRepositoryAnchorTracksCommitsAndWorkingTreeSeparately() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(
            title: "Booking",
            goal: "Add scheduled delivery",
            workspacePath: fixture.repository.path
        )

        let initial = try XCTUnwrap(fixture.store.gitActivity(taskID: task.id))
        XCTAssertEqual(initial.state, .current)
        XCTAssertTrue(initial.commits.isEmpty)
        XCTAssertTrue(initial.dirtyPaths.isEmpty)

        let sourceURL = fixture.repository.appendingPathComponent("Feature.swift")
        try "let value = 1\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        let dirty = try XCTUnwrap(fixture.store.gitActivity(taskID: task.id))
        XCTAssertEqual(dirty.state, .current)
        XCTAssertEqual(dirty.dirtyPaths.map(\.path), ["Feature.swift"])
        XCTAssertTrue(dirty.hasCodeChanges)

        try runGit(["add", "Feature.swift"], at: fixture.repository)
        try runGit(["commit", "-m", "Add scheduled delivery"], at: fixture.repository)
        let committed = try XCTUnwrap(
            fixture.store.gitActivity(taskID: task.id, includeCommittedDiff: true)
        )
        XCTAssertEqual(committed.state, .commitsAvailable)
        XCTAssertEqual(committed.commits.map(\.subject), ["Add scheduled delivery"])
        XCTAssertEqual(committed.committedPaths.map(\.path), ["Feature.swift"])
        XCTAssertTrue(committed.dirtyPaths.isEmpty)
        XCTAssertTrue(committed.committedDiff?.contains("let value = 1") == true)
    }

    func testPathStateSignatureChangesWhenDirtyPathSetChanges() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try "let first = true\n".write(
            to: fixture.repository.appendingPathComponent("First.swift"),
            atomically: true,
            encoding: .utf8
        )
        let firstState = try XCTUnwrap(
            ProjectionStore.gitPathStates(at: [fixture.repository.path]).first
        )

        try "let second = true\n".write(
            to: fixture.repository.appendingPathComponent("Second.swift"),
            atomically: true,
            encoding: .utf8
        )
        let secondState = try XCTUnwrap(
            ProjectionStore.gitPathStates(at: [fixture.repository.path]).first
        )

        XCTAssertEqual(firstState.dirtyState, .modified)
        XCTAssertEqual(secondState.dirtyState, .modified)
        XCTAssertNotEqual(firstState.workingTreeSignature, secondState.workingTreeSignature)
    }

    func testWorkspaceActivityRefreshAdvancesBoundProjectionAfterCommit() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(
            title: "Search",
            goal: "Improve search",
            workspacePath: fixture.repository.path
        )
        let initialRevision = try fixture.store.latestProjectionRevision(taskID: task.id)

        try "let indexed = true\n".write(
            to: fixture.repository.appendingPathComponent("Search.swift"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "Search.swift"], at: fixture.repository)
        try runGit(["commit", "-m", "Index search results"], at: fixture.repository)

        XCTAssertEqual(
            try fixture.store.refreshWorkspaceActivity(taskIDs: [task.id]),
            [task.id]
        )
        XCTAssertGreaterThan(
            try fixture.store.latestProjectionRevision(taskID: task.id),
            initialRevision
        )
        let projection = try XCTUnwrap(fixture.store.projectionSnapshot(taskID: task.id))
        XCTAssertTrue(projection.manifestJSON.contains("Index search results"))
        XCTAssertTrue(projection.manifestJSON.contains("\"state\":\"commits_available\""))
    }

    func testApprovingContextPackAdvancesGitBaseline() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(
            title: "Inventory",
            goal: "Migrate inventory",
            workspacePath: fixture.repository.path
        )
        let sourceURL = fixture.repository.appendingPathComponent("Inventory.swift")
        try "let migrated = true\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Inventory.swift"], at: fixture.repository)
        try runGit(["commit", "-m", "Migrate inventory"], at: fixture.repository)
        XCTAssertEqual(
            try fixture.store.gitActivity(taskID: task.id)?.state,
            .commitsAvailable
        )

        let input = try preparationInput(store: fixture.store, taskID: task.id)
        let workSourceID = try XCTUnwrap(input.sources.first(where: { $0.reference.kind == "work" })?.id)
        let draft = try fixture.store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: workSourceID),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        let pack = try fixture.store.approveContextDraft(id: draft.id, currentInput: input)

        let baseline = try XCTUnwrap(fixture.store.gitBaseline(taskID: task.id))
        XCTAssertEqual(baseline.contextPackID, pack.id)
        XCTAssertEqual(
            try fixture.store.gitActivity(taskID: task.id)?.state,
            .current
        )
    }

    func testWorkingTreeChangesDoNotMakeConfirmedMaterialsStale() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(
            title: "Inventory",
            goal: "Migrate inventory",
            workspacePath: fixture.repository.path
        )
        let input = try preparationInput(store: fixture.store, taskID: task.id, includeGitActivity: true)
        let workSourceID = try XCTUnwrap(input.sources.first(where: { $0.reference.kind == "work" })?.id)
        let draft = try fixture.store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: workSourceID),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        _ = try fixture.store.approveContextDraft(id: draft.id, currentInput: input)

        try "uncommitted\n".write(
            to: fixture.repository.appendingPathComponent("Scratch.swift"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.store.refreshActiveContextFreshness()

        let pack = try XCTUnwrap(fixture.store.currentContextPack(taskID: task.id))
        XCTAssertEqual(pack.freshness, "fresh")
        XCTAssertNil(pack.staleReason)
        XCTAssertTrue(try XCTUnwrap(fixture.store.gitActivity(taskID: task.id)).hasCodeChanges)
    }

    func testSelectedGitActivityChangeRejectsPendingDraft() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(
            title: "Checkout",
            goal: "Update checkout",
            workspacePath: fixture.repository.path
        )
        let originalInput = try preparationInput(
            store: fixture.store,
            taskID: task.id,
            includeGitActivity: true
        )
        let workSource = try XCTUnwrap(
            originalInput.sources.first(where: { $0.reference.kind == "work" })
        )
        let gitSource = try XCTUnwrap(
            originalInput.sources.first(where: {
                $0.reference.kind == ContextMaterialExtractor.committedGitActivityKind
            })
        )
        let selectedSourceIDs = Set([workSource.id, gitSource.id])
        let selectedOriginalSources = originalInput.sources.filter { selectedSourceIDs.contains($0.id) }
        let draft = try fixture.store.saveContextDraft(
            taskID: task.id,
            baseRevision: originalInput.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: workSource.id),
            sourceManifest: selectedOriginalSources.map(\.reference),
            answers: [:]
        )

        try "let updated = true\n".write(
            to: fixture.repository.appendingPathComponent("Checkout.swift"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "Checkout.swift"], at: fixture.repository)
        try runGit(["commit", "-m", "Update checkout"], at: fixture.repository)

        let changedInput = try preparationInput(
            store: fixture.store,
            taskID: task.id,
            includeGitActivity: true
        )
        let selectedChangedSources = changedInput.sources.filter { selectedSourceIDs.contains($0.id) }
        let selectedChangedInput = ContextPreparationInput(
            taskID: changedInput.taskID,
            baseRevision: changedInput.baseRevision,
            sources: selectedChangedSources,
            excludedSources: changedInput.excludedSources,
            totalIncludedCharacters: selectedChangedSources.reduce(0) {
                $0 + $1.reference.includedCharacterCount
            }
        )

        XCTAssertThrowsError(
            try fixture.store.approveContextDraft(id: draft.id, currentInput: selectedChangedInput)
        ) { error in
            XCTAssertEqual(error as? ContextPreparationError, .staleDraft)
        }
    }

    func testActivityPreservesRenameDeleteAndBinaryEvidence() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let oldFile = fixture.repository.appendingPathComponent("OldName.swift")
        let binaryFile = fixture.repository.appendingPathComponent("asset.bin")
        try "let value = 1\n".write(to: oldFile, atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: binaryFile)
        try runGit(["add", "OldName.swift", "asset.bin"], at: fixture.repository)
        try runGit(["commit", "-m", "Seed tracked files"], at: fixture.repository)

        let task = try fixture.store.createTask(
            title: "Refactor",
            goal: "Rename the implementation",
            workspacePath: fixture.repository.path
        )
        try runGit(["mv", "OldName.swift", "NewName.swift"], at: fixture.repository)
        try runGit(["rm", "README.md"], at: fixture.repository)
        try Data([0x00, 0x01, 0x03]).write(to: binaryFile)
        try runGit(["add", "asset.bin"], at: fixture.repository)
        try runGit(["commit", "-m", "Reshape tracked files"], at: fixture.repository)

        let activity = try XCTUnwrap(
            fixture.store.gitActivity(taskID: task.id, includeCommittedDiff: true)
        )
        let rename = try XCTUnwrap(activity.committedPaths.first(where: { $0.status.hasPrefix("R") }))
        let deletion = try XCTUnwrap(activity.committedPaths.first(where: { $0.status == "D" }))
        let binary = try XCTUnwrap(activity.committedPaths.first(where: { $0.path == "asset.bin" }))

        XCTAssertEqual(rename.previousPath, "OldName.swift")
        XCTAssertEqual(rename.path, "NewName.swift")
        XCTAssertEqual(deletion.path, "README.md")
        XCTAssertTrue(binary.isBinary)
        XCTAssertFalse(activity.committedDiff?.contains("\u{0}") == true)
    }

    func testCommittedDiffIsBounded() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(
            title: "Large change",
            goal: "Keep Git evidence bounded",
            workspacePath: fixture.repository.path
        )
        let lines = (0..<8_000).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        try lines.write(
            to: fixture.repository.appendingPathComponent("Generated.swift"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "Generated.swift"], at: fixture.repository)
        try runGit(["commit", "-m", "Add generated source"], at: fixture.repository)

        let activity = try XCTUnwrap(
            fixture.store.gitActivity(taskID: task.id, includeCommittedDiff: true)
        )
        let diff = try XCTUnwrap(activity.committedDiff)
        XCTAssertLessThanOrEqual(diff.count, GitRepositoryReader.diffCharacterLimit)
        XCTAssertTrue(diff.contains("Nexus omitted remaining diff"))
    }

    func testBranchMismatchAndRewrittenHistoryAreNotLinearProgress() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(
            title: "Search",
            goal: "Update search",
            workspacePath: fixture.repository.path
        )
        try runGit(["switch", "-c", "other"], at: fixture.repository)
        XCTAssertEqual(
            try fixture.store.gitActivity(taskID: task.id)?.state,
            .branchMismatch
        )

        try runGit(["switch", "main"], at: fixture.repository)
        let sourceURL = fixture.repository.appendingPathComponent("Search.swift")
        try "let changed = true\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Search.swift"], at: fixture.repository)
        try runGit(["commit", "-m", "Change search"], at: fixture.repository)
        let input = try preparationInput(store: fixture.store, taskID: task.id)
        let workSourceID = try XCTUnwrap(input.sources.first(where: { $0.reference.kind == "work" })?.id)
        let draft = try fixture.store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: workSourceID),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        _ = try fixture.store.approveContextDraft(id: draft.id, currentInput: input)
        let baseline = try XCTUnwrap(fixture.store.gitBaseline(taskID: task.id))
        let parent = try gitOutput(["rev-parse", "\(baseline.headSHA)^"], at: fixture.repository)

        try runGit(["reset", "--hard", parent], at: fixture.repository)
        try "let rewritten = true\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Search.swift"], at: fixture.repository)
        try runGit(["commit", "-m", "Rewrite search"], at: fixture.repository)

        let rewritten = try XCTUnwrap(fixture.store.gitActivity(taskID: task.id))
        XCTAssertEqual(rewritten.state, .historyRewritten)
    }

    private func makeFixture() throws -> (
        store: ProjectionStore, repository: URL, cleanup: () -> Void
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let repository = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "Nexus Test"], at: repository)
        try runGit(["config", "user.email", "nexus-test@example.invalid"], at: repository)
        try "Initial\n".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], at: repository)
        try runGit(["commit", "-m", "Initial"], at: repository)
        let store = ProjectionStore(databaseURL: directory.appendingPathComponent("Nexus.sqlite"))
        try store.bootstrap()
        return (store, repository, { try? FileManager.default.removeItem(at: directory) })
    }

    private func preparationInput(
        store: ProjectionStore,
        taskID: String,
        includeGitActivity: Bool = false
    ) throws -> ContextPreparationInput {
        let task = try XCTUnwrap(store.listTasks().first(where: { $0.id == taskID }))
        let repository = try store.repository(taskID: taskID)
        return try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: store.latestProjectionRevision(taskID: taskID),
            supplement: try store.supplement(taskID: taskID),
            notes: try store.listNotes(taskID: taskID),
            files: try store.listFiles(taskID: taskID),
            repository: repository,
            gitActivity: includeGitActivity
                ? try store.gitActivity(
                    taskID: taskID,
                    includeCommittedDiff: true,
                    includeUncommittedDiff: true
                )
                : nil
        )
    }

    private func content(sourceID: String) -> ContextPackContent {
        let claim = ContextClaim(text: "Keep compatibility", sourceIDs: [sourceID])
        return ContextPackContent(
            objective: "Migrate safely",
            scopeIn: [claim],
            scopeOut: [],
            confirmedFacts: [claim],
            constraints: [],
            acceptanceCriteria: [],
            assumptions: [],
            questions: [],
            brief: "Prepared context brief",
            recommendedSourceIDs: [sourceID]
        )
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

    private func gitOutput(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed")
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
