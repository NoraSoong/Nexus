import Foundation
import XCTest

@testable import NexusCore

final class ProjectionPayloadBuilderTests: XCTestCase {
    func testFallbackBriefDeduplicatesLegacyCheckpointAndAdditionalNote() throws {
        let task = TaskRecord(
            id: "work-1",
            title: "Delivery",
            goal: "Implement scheduled delivery",
            status: "active",
            createdAt: "2026-07-30T00:00:00Z",
            updatedAt: "2026-07-30T00:00:00Z"
        )
        let repeatedText = "Confirm the delivery window and idempotency rule."
        let supplement = TaskSupplementRecord(
            taskID: task.id,
            body: repeatedText,
            updatedAt: "2026-07-30T00:00:00Z"
        )
        let checkpoint = CheckpointRecord(
            id: "checkpoint-1",
            taskID: task.id,
            currentState: "",
            nextStep: repeatedText,
            blockers: "",
            createdAt: "2026-07-30T00:00:00Z"
        )

        let payloads = try ProjectionPayloadBuilder.build(
            task: task,
            checkpoint: checkpoint,
            notes: [],
            visibleFiles: [],
            hiddenFiles: [],
            repository: nil,
            supplement: supplement,
            contextPack: nil,
            now: "2026-07-30T00:00:00Z"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payloads.briefPayload.utf8)) as? [String: Any]
        )
        let brief = try XCTUnwrap(object["brief"] as? String)

        XCTAssertEqual(brief.components(separatedBy: repeatedText).count - 1, 1)
        XCTAssertTrue(brief.contains("Additional note:"))
        XCTAssertFalse(brief.contains("Next:"))
    }

    func testManifestIncludesBoundedWorkspaceActivityWithoutDiffBodies() throws {
        let task = TaskRecord(
            id: "work-1",
            title: "Delivery",
            goal: "Implement scheduled delivery",
            status: "active",
            createdAt: "2026-07-30T00:00:00Z",
            updatedAt: "2026-07-30T00:00:00Z"
        )
        let repository = TaskRepositoryRecord(
            taskID: task.id,
            path: "/tmp/delivery",
            branch: "feature/delivery",
            updatedAt: "2026-07-30T00:00:00Z"
        )
        let activity = GitActivitySnapshot(
            workspacePath: repository.path,
            linkedBranch: repository.branch,
            currentBranch: repository.branch,
            baselineHeadSHA: "base",
            currentHeadSHA: "head",
            state: .commitsAvailable,
            commits: (0..<12).map {
                GitCommitSummary(
                    sha: "sha-\($0)",
                    subject: "Commit \($0)",
                    committedAt: "2026-07-30T00:00:00Z"
                )
            },
            committedPaths: (0..<24).map {
                GitChangedPath(status: "M", path: "Sources/File\($0).swift")
            },
            dirtyPaths: [
                GitChangedPath(status: "M", path: "Sources/Pending.swift")
            ],
            committedDiff: "must not be projected",
            uncommittedDiff: "must not be projected",
            capturedAt: "2026-07-30T00:00:00Z"
        )

        let payloads = try ProjectionPayloadBuilder.build(
            task: task,
            checkpoint: nil,
            notes: [],
            visibleFiles: [],
            hiddenFiles: [],
            repository: repository,
            supplement: nil,
            contextPack: nil,
            gitActivity: activity,
            now: "2026-07-30T00:00:00Z"
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payloads.manifestPayload.utf8)) as? [String: Any]
        )
        let workspaceActivity = try XCTUnwrap(manifest["workspace_activity"] as? [String: Any])

        XCTAssertEqual(workspaceActivity["commit_count"] as? Int, 12)
        XCTAssertEqual((workspaceActivity["commits"] as? [[String: Any]])?.count, 10)
        XCTAssertEqual((workspaceActivity["committed_paths"] as? [[String: Any]])?.count, 20)
        XCTAssertEqual((workspaceActivity["uncommitted_paths"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(workspaceActivity["committed_diff"])
        XCTAssertNil(workspaceActivity["uncommitted_diff"])
        XCTAssertFalse(payloads.manifestPayload.contains("must not be projected"))
    }
}
