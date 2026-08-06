import XCTest

@testable import NexusCore

final class ContextReviewServiceTests: XCTestCase {
    func testWhitespaceOnlyChangesAreIgnored() {
        let source = makeSource(id: "source:one", hash: "one")
        let baseline = makePack(
            content: makeContent(
                objective: "Migrate the API",
                facts: [ContextClaim(text: "Keep old clients working", sourceIDs: [source.id])]
            ),
            sources: [source]
        )
        let candidate = makeContent(
            objective: "  Migrate   the API ",
            facts: [ContextClaim(text: "Keep  old clients\nworking", sourceIDs: [source.id])]
        )

        let diff = ContextReviewService.compare(
            candidate: candidate,
            candidateSources: [source],
            baseline: baseline
        )

        XCTAssertFalse(diff.hasChanges)
    }

    func testUniqueClaimWithSameSourcesIsModified() {
        let source = makeSource(id: "source:contract", hash: "one")
        let baseline = makePack(
            content: makeContent(
                facts: [ContextClaim(text: "Timeout is 30 seconds", sourceIDs: [source.id])]
            ),
            sources: [source]
        )
        let candidate = makeContent(
            facts: [ContextClaim(text: "Timeout is 45 seconds", sourceIDs: [source.id])]
        )

        let diff = ContextReviewService.compare(
            candidate: candidate,
            candidateSources: [source],
            baseline: baseline
        )

        XCTAssertEqual(diff.modifiedCount, 1)
        XCTAssertEqual(diff.addedCount, 0)
        XCTAssertEqual(diff.removedCount, 0)
        XCTAssertEqual(diff.changes.first?.section, .confirmedFacts)
    }

    func testObjectiveAdditionAndRemovalAreNotReportedAsModifications() {
        let added = ContextReviewService.compare(
            candidate: makeContent(objective: "Ship safely"),
            candidateSources: [],
            baseline: makePack(content: makeContent(objective: ""), sources: [])
        )
        let removed = ContextReviewService.compare(
            candidate: makeContent(objective: ""),
            candidateSources: [],
            baseline: makePack(content: makeContent(objective: "Ship safely"), sources: [])
        )

        XCTAssertEqual(added.changes.first?.kind, .added)
        XCTAssertEqual(removed.changes.first?.kind, .removed)
    }

    func testEquivalentQuestionIgnoresModelGeneratedIDChanges() {
        var baselineContent = makeContent()
        baselineContent.questions = [
            ContextQuestion(
                id: "old-id",
                question: "Is cancellation idempotent?",
                whyItMatters: "It changes retry behavior.",
                sourceIDs: []
            )
        ]
        var candidate = baselineContent
        candidate.questions = [
            ContextQuestion(
                id: "new-id",
                question: "Is cancellation idempotent?",
                whyItMatters: "It changes retry behavior.",
                sourceIDs: []
            )
        ]

        let diff = ContextReviewService.compare(
            candidate: candidate,
            candidateSources: [],
            baseline: makePack(content: baselineContent, sources: [])
        )

        XCTAssertFalse(diff.hasChanges)
    }

    func testAmbiguousClaimsAreReportedAsAddedAndRemoved() {
        let source = makeSource(id: "source:contract", hash: "one")
        let baseline = makePack(
            content: makeContent(
                facts: [
                    ContextClaim(text: "Old statement A", sourceIDs: [source.id]),
                    ContextClaim(text: "Old statement B", sourceIDs: [source.id]),
                ]
            ),
            sources: [source]
        )
        let candidate = makeContent(
            facts: [
                ContextClaim(text: "New statement A", sourceIDs: [source.id]),
                ContextClaim(text: "New statement B", sourceIDs: [source.id]),
            ]
        )

        let diff = ContextReviewService.compare(
            candidate: candidate,
            candidateSources: [source],
            baseline: baseline
        )

        XCTAssertEqual(diff.modifiedCount, 0)
        XCTAssertEqual(diff.addedCount, 2)
        XCTAssertEqual(diff.removedCount, 2)
    }

    func testSourceChangesUseStableIDsAndHashes() {
        let retained = makeSource(id: "source:retained", hash: "old")
        let removed = makeSource(id: "source:removed", hash: "old")
        let changed = makeSource(id: retained.id, hash: "new")
        let added = makeSource(id: "source:added", hash: "new")

        let changes = ContextReviewService.sourceChanges(
            baseline: [retained, removed],
            candidate: [changed, added]
        )

        XCTAssertEqual(changes.map(\.id), ["source:added", "source:removed", "source:retained"])
        XCTAssertEqual(changes.map(\.kind), [.added, .removed, .changed])
    }

    func testLegacyRepositoryFingerprintUsesPathIdentity() {
        let baseline = makeRepositorySource(hash: "legacy-dynamic-state", fingerprintVersion: nil)
        let current = makeRepositorySource(
            hash: "stable-identity",
            fingerprintVersion: ContextMaterialExtractor.repositoryFingerprintVersion
        )

        XCTAssertTrue(
            ContextReviewService.sourceChanges(baseline: [baseline], candidate: [current]).isEmpty
        )
    }

    func testCurrentRepositoryFingerprintDetectsIdentityChanges() {
        let baseline = makeRepositorySource(
            hash: "main-identity",
            fingerprintVersion: ContextMaterialExtractor.repositoryFingerprintVersion
        )
        let current = makeRepositorySource(
            hash: "feature-identity",
            fingerprintVersion: ContextMaterialExtractor.repositoryFingerprintVersion
        )

        XCTAssertEqual(
            ContextReviewService.sourceChanges(baseline: [baseline], candidate: [current]).map(\.kind),
            [.changed]
        )
    }

    func testFindingsSurfaceQuestionsAssumptionsAndTruncatedEvidence() {
        let source = makeSource(id: "source:long", hash: "one", truncated: true)
        var content = makeContent(
            facts: [ContextClaim(text: "Confirmed", sourceIDs: [source.id])]
        )
        content.assumptions = [ContextClaim(text: "Likely compatible", sourceIDs: [])]
        content.questions = [
            ContextQuestion(
                id: "question-one",
                question: "Is cancellation idempotent?",
                whyItMatters: "It changes retry behavior.",
                sourceIDs: [source.id]
            )
        ]

        let findings = ContextReviewService.findings(
            content: content,
            sources: [source],
            sourceChanges: []
        )

        XCTAssertEqual(
            findings.map(\.kind),
            [.unresolvedQuestions, .assumptions, .truncatedSources]
        )
    }

    private func makeContent(
        objective: String = "Ship safely",
        facts: [ContextClaim] = []
    ) -> ContextPackContent {
        ContextPackContent(
            objective: objective,
            scopeIn: [],
            scopeOut: [],
            confirmedFacts: facts,
            constraints: [],
            acceptanceCriteria: [],
            assumptions: [],
            questions: [],
            brief: "Concise brief",
            recommendedSourceIDs: facts.flatMap(\.sourceIDs)
        )
    }

    private func makePack(
        content: ContextPackContent,
        sources: [ContextSourceRef]
    ) -> ContextPack {
        ContextPack(
            id: "pack",
            taskID: "task",
            revision: 10,
            content: content,
            sourceManifest: sources,
            freshness: "fresh",
            staleReason: nil,
            createdAt: "2026-07-27T00:00:00Z"
        )
    }

    private func makeSource(
        id: String,
        hash: String,
        truncated: Bool = false
    ) -> ContextSourceRef {
        ContextSourceRef(
            id: id,
            kind: "note",
            title: id,
            path: nil,
            updatedAt: "2026-07-27T00:00:00Z",
            contentHash: hash,
            characterCount: truncated ? 50_000 : 10,
            includedCharacterCount: truncated ? 40_000 : 10,
            truncated: truncated
        )
    }

    private func makeRepositorySource(hash: String, fingerprintVersion: Int?) -> ContextSourceRef {
        ContextSourceRef(
            id: "repository:task",
            kind: "repository",
            title: "Nexus",
            path: "/tmp/nexus",
            updatedAt: "2026-07-27T00:00:00Z",
            contentHash: hash,
            characterCount: 10,
            includedCharacterCount: 10,
            truncated: false,
            fingerprintVersion: fingerprintVersion
        )
    }
}
