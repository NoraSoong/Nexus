import XCTest

@testable import NexusCore

final class ContextLifecycleResolverTests: XCTestCase {
    func testLifecycleSeparatesMaterialAndCodeChanges() {
        XCTAssertEqual(resolve(hasContext: false), .noConfirmedContext)
        XCTAssertEqual(resolve(), .confirmed)
        XCTAssertEqual(resolve(materialsChanged: true), .materialsChanged)
        XCTAssertEqual(resolve(workingTreeState: .modified), .codeChanged)
        XCTAssertEqual(
            resolve(materialsChanged: true, workingTreeState: .modified),
            .materialsAndCodeChanged
        )
    }

    func testWorkspaceIntegrityTakesPriority() {
        XCTAssertEqual(
            resolve(activityState: .branchMismatch, materialsChanged: true),
            .needsConfirmation
        )
        XCTAssertEqual(
            resolve(activityState: .historyRewritten),
            .needsConfirmation
        )
        XCTAssertEqual(
            resolve(activityState: .unavailable, workingTreeState: .modified),
            .workspaceUnavailable
        )
    }

    private func resolve(
        hasContext: Bool = true,
        activityState: GitActivityState? = nil,
        materialsChanged: Bool = false,
        workingTreeState: GitWorkingTreeState = .clean
    ) -> ContextLifecycleState {
        ContextLifecycleResolver.resolve(
            hasConfirmedContext: hasContext,
            materialsChanged: materialsChanged,
            gitActivity: activityState.map(activity),
            workingTreeState: workingTreeState
        )
    }

    private func activity(state: GitActivityState) -> GitActivitySnapshot {
        GitActivitySnapshot(
            workspacePath: "/tmp/repo",
            linkedBranch: "main",
            currentBranch: "main",
            baselineHeadSHA: "baseline",
            currentHeadSHA: "head",
            state: state,
            commits: state == .commitsAvailable
                ? [GitCommitSummary(sha: "head", subject: "Change", committedAt: "2026-01-01")]
                : [],
            committedPaths: [],
            dirtyPaths: [],
            committedDiff: nil,
            uncommittedDiff: nil,
            capturedAt: "2026-01-01"
        )
    }
}
