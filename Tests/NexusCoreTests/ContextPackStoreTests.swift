import Foundation
import XCTest

@testable import NexusCore

final class ContextPackStoreTests: XCTestCase {
    func testDraftDoesNotChangeProjectionUntilApproved() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "API migration", goal: "Keep old clients working")
        try store.switchTask(taskID: task.id)
        _ = try store.addNote(
            taskID: task.id,
            title: "Contract",
            body: "The old field remains readable.",
            exposed: true
        )
        let before = try XCTUnwrap(store.projectionSnapshot(taskID: task.id))
        XCTAssertFalse(before.resumeBriefJSON.contains("context_pack_id"))

        let input = try preparationInput(store: store, taskID: task.id)
        let draft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "note:\(try XCTUnwrap(store.listNotes(taskID: task.id).first).id)"),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        let pending = try XCTUnwrap(store.latestContextDraft(taskID: task.id))
        XCTAssertEqual(pending.id, draft.id)
        XCTAssertFalse(
            try XCTUnwrap(store.projectionSnapshot(taskID: task.id))
                .resumeBriefJSON
                .contains("context_pack_id")
        )

        let pack = try store.approveContextDraft(id: draft.id, currentInput: input)
        XCTAssertEqual(try store.currentContextPack(taskID: task.id)?.id, pack.id)
        let after = try XCTUnwrap(store.projectionSnapshot(taskID: task.id))
        XCTAssertTrue(after.resumeBriefJSON.contains(pack.id))
        XCTAssertTrue(after.resumeBriefJSON.contains("Prepared context brief"))
    }

    func testChangedSourceRejectsPendingDraft() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "Timeout", goal: "Diagnose timeout")
        try store.switchTask(taskID: task.id)
        let note = try store.addNote(taskID: task.id, title: "Evidence", body: "Timeout is 30s", exposed: true)
        let input = try preparationInput(store: store, taskID: task.id)
        let draft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "note:\(note.id)"),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )

        try store.updateNote(id: note.id, taskID: task.id, title: note.title, body: "Timeout is 45s", exposed: true)
        let changedInput = try preparationInput(store: store, taskID: task.id)
        XCTAssertThrowsError(try store.approveContextDraft(id: draft.id, currentInput: changedInput)) { error in
            XCTAssertEqual(error as? ContextPreparationError, .staleDraft)
        }
    }

    func testUnrelatedProjectionRevisionDoesNotInvalidatePendingDraft() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "Checkout", goal: "Keep checkout compatible")
        try store.switchTask(taskID: task.id)
        let evidence = try store.addNote(
            taskID: task.id,
            title: "Contract",
            body: "The old field remains readable.",
            exposed: true
        )
        let originalInput = try preparationInput(store: store, taskID: task.id)
        let selectedIDs = Set(["work:\(task.id)", "note:\(evidence.id)"])
        let originalSources = originalInput.sources.filter { selectedIDs.contains($0.id) }
        let draft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: originalInput.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "note:\(evidence.id)"),
            sourceManifest: originalSources.map(\.reference),
            answers: [:]
        )

        _ = try store.addNote(
            taskID: task.id,
            title: "Unselected note",
            body: "This source was not used by the draft.",
            exposed: true
        )
        let refreshedInput = try preparationInput(store: store, taskID: task.id)
        XCTAssertNotEqual(refreshedInput.baseRevision, originalInput.baseRevision)
        let selectedSources = refreshedInput.sources.filter { selectedIDs.contains($0.id) }
        let selectedInput = ContextPreparationInput(
            taskID: refreshedInput.taskID,
            baseRevision: refreshedInput.baseRevision,
            sources: selectedSources,
            excludedSources: refreshedInput.excludedSources,
            totalIncludedCharacters: selectedSources.reduce(0) {
                $0 + $1.reference.includedCharacterCount
            }
        )

        let pack = try store.approveContextDraft(id: draft.id, currentInput: selectedInput)
        XCTAssertEqual(try store.currentContextPack(taskID: task.id)?.id, pack.id)
    }

    func testNewerConfirmedPackInvalidatesOlderPendingDraft() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "Orders", goal: "Keep order behavior explicit")
        try store.switchTask(taskID: task.id)
        let evidence = try store.addNote(
            taskID: task.id,
            title: "Contract",
            body: "Order creation is idempotent.",
            exposed: true
        )
        let input = try preparationInput(store: store, taskID: task.id)
        let sourceID = "note:\(evidence.id)"
        let olderDraft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: sourceID),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        let newerDraft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: sourceID),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )

        _ = try store.approveContextDraft(id: newerDraft.id, currentInput: input)
        let currentInput = try preparationInput(store: store, taskID: task.id)

        XCTAssertThrowsError(
            try store.approveContextDraft(id: olderDraft.id, currentInput: currentInput)
        ) { error in
            XCTAssertEqual(error as? ContextPreparationError, .staleDraft)
        }
    }

    func testHidingPackSourceRemovesPackFromProjection() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "Inventory", goal: "Migrate inventory API")
        try store.switchTask(taskID: task.id)
        let note = try store.addNote(taskID: task.id, title: "Contract", body: "Keep error code 5004", exposed: true)
        let input = try preparationInput(store: store, taskID: task.id)
        let draft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "note:\(note.id)"),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        _ = try store.approveContextDraft(id: draft.id, currentInput: input)

        try store.updateNote(id: note.id, taskID: task.id, title: note.title, body: note.body, exposed: false)
        let snapshot = try XCTUnwrap(store.projectionSnapshot(taskID: task.id))
        XCTAssertFalse(snapshot.resumeBriefJSON.contains("context_pack_id"))
        XCTAssertEqual(try store.currentContextPack(taskID: task.id)?.freshness, "stale")
        XCTAssertEqual(
            try store.currentContextSourceChanges(taskID: task.id).map(\.kind),
            [.removed]
        )
    }

    func testUnrelatedLargeMaterialDoesNotInvalidateApprovedPack() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "Context budget", goal: "Keep selected evidence stable")
        try store.switchTask(taskID: task.id)
        let evidence = try store.addNote(
            taskID: task.id,
            title: "Z evidence",
            body: "Confirmed contract",
            exposed: true
        )
        let input = try preparationInput(store: store, taskID: task.id)
        let draft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "note:\(evidence.id)"),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        let pack = try store.approveContextDraft(id: draft.id, currentInput: input)

        _ = try store.addNote(
            taskID: task.id,
            title: "A unrelated noise",
            body: String(repeating: "n", count: 130_000),
            exposed: true
        )

        XCTAssertEqual(try store.currentContextPack(taskID: task.id)?.freshness, "fresh")
        XCTAssertTrue(try XCTUnwrap(store.projectionSnapshot(taskID: task.id)).resumeBriefJSON.contains(pack.id))
    }

    func testClarificationAnswerRemainsFreshAfterApproval() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "Booking", goal: "Define cancellation")
        try store.switchTask(taskID: task.id)
        let baseInput = try preparationInput(store: store, taskID: task.id)
        let answerSources = ContextPreparationService.clarificationAnswerSources(
            answers: ["cancel-idempotency": "Cancellation must be idempotent"]
        )
        let sources = baseInput.sources + answerSources
        let input = ContextPreparationInput(
            taskID: task.id,
            baseRevision: baseInput.baseRevision,
            sources: sources,
            excludedSources: baseInput.excludedSources,
            totalIncludedCharacters: sources.reduce(0) {
                $0 + $1.reference.includedCharacterCount
            }
        )
        let answerSourceID = try XCTUnwrap(answerSources.first?.id)
        let draft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "deepseek",
            model: "test-model",
            content: content(sourceID: answerSourceID),
            sourceManifest: input.sources.map(\.reference),
            answers: ["cancel-idempotency": "Cancellation must be idempotent"]
        )

        let pack = try store.approveContextDraft(id: draft.id, currentInput: input)
        try store.refreshActiveContextFreshness()

        XCTAssertEqual(try store.currentContextPack(taskID: task.id)?.freshness, "fresh")
        XCTAssertTrue(
            try XCTUnwrap(store.projectionSnapshot(taskID: task.id))
                .resumeBriefJSON
                .contains(pack.id)
        )
        XCTAssertTrue(try store.currentContextSourceChanges(taskID: task.id).isEmpty)
    }

    func testExternalFileChangeMarksPackPossiblyStaleOnRefresh() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "File freshness", goal: "Track evidence changes")
        try store.switchTask(taskID: task.id)
        let fileURL = fixture.directory.appendingPathComponent("contract.md")
        try "Original contract".write(to: fileURL, atomically: true, encoding: .utf8)
        let file = try store.addFile(taskID: task.id, fileURL: fileURL)
        let input = try preparationInput(store: store, taskID: task.id)
        let draft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: input.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "file:\(file.id)"),
            sourceManifest: input.sources.map(\.reference),
            answers: [:]
        )
        let pack = try store.approveContextDraft(id: draft.id, currentInput: input)

        try "Changed contract".write(to: fileURL, atomically: true, encoding: .utf8)
        try store.refreshActiveContextFreshness()

        let refreshed = try XCTUnwrap(store.currentContextPack(taskID: task.id))
        XCTAssertEqual(refreshed.freshness, "possibly_stale")
        XCTAssertEqual(refreshed.staleReason, "source_changed")
        let snapshot = try XCTUnwrap(store.projectionSnapshot(taskID: task.id))
        XCTAssertTrue(snapshot.resumeBriefJSON.contains(pack.id))
        XCTAssertTrue(snapshot.resumeBriefJSON.contains("possibly_stale"))
        XCTAssertEqual(
            try store.currentContextSourceChanges(taskID: task.id).map(\.kind),
            [.changed]
        )
    }

    func testContextPackHistoryReturnsPreviousApprovedVersion() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let task = try store.createTask(title: "History", goal: "Keep reviewed versions")
        try store.switchTask(taskID: task.id)
        let note = try store.addNote(taskID: task.id, title: "Evidence", body: "Version one", exposed: true)

        let firstInput = try preparationInput(store: store, taskID: task.id)
        let firstDraft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: firstInput.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "note:\(note.id)"),
            sourceManifest: firstInput.sources.map(\.reference),
            answers: [:]
        )
        let firstPack = try store.approveContextDraft(id: firstDraft.id, currentInput: firstInput)

        try store.updateNote(
            id: note.id,
            taskID: task.id,
            title: note.title,
            body: "Version two",
            exposed: true
        )
        let secondInput = try preparationInput(store: store, taskID: task.id)
        let secondDraft = try store.saveContextDraft(
            taskID: task.id,
            baseRevision: secondInput.baseRevision,
            provider: "openai",
            model: "test-model",
            content: content(sourceID: "note:\(note.id)"),
            sourceManifest: secondInput.sources.map(\.reference),
            answers: [:]
        )
        let secondPack = try store.approveContextDraft(id: secondDraft.id, currentInput: secondInput)

        let history = try store.contextPackHistory(taskID: task.id)
        XCTAssertEqual(history.map(\.id), [secondPack.id, firstPack.id])
        XCTAssertEqual(
            try store.previousContextPack(taskID: task.id, beforeRevision: secondPack.revision)?.id,
            firstPack.id
        )
    }

    private func preparationInput(store: ProjectionStore, taskID: String) throws -> ContextPreparationInput {
        let task = try XCTUnwrap(store.listTasks().first(where: { $0.id == taskID }))
        return try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: store.latestProjectionRevision(taskID: taskID),
            supplement: try store.supplement(taskID: taskID),
            notes: try store.listNotes(taskID: taskID),
            files: try store.listFiles(taskID: taskID),
            repository: try store.repository(taskID: taskID)
        )
    }

    private func content(sourceID: String) -> ContextPackContent {
        let claim = ContextClaim(text: "Keep compatibility", sourceIDs: [sourceID])
        return ContextPackContent(
            objective: "Migrate safely",
            scopeIn: [claim],
            scopeOut: [],
            confirmedFacts: [claim],
            constraints: [claim],
            acceptanceCriteria: [claim],
            assumptions: [],
            questions: [],
            brief: "Prepared context brief",
            recommendedSourceIDs: [sourceID]
        )
    }

    private func makeFixture() throws -> (store: ProjectionStore, directory: URL, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let store = ProjectionStore(databaseURL: directory.appendingPathComponent("Nexus.sqlite"))
        try store.bootstrap()
        return (store, directory, { try? FileManager.default.removeItem(at: directory) })
    }
}
