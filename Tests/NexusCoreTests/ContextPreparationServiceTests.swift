import Foundation
import XCTest

@testable import NexusCore

final class ContextPreparationServiceTests: XCTestCase {
    func testLegacySourceReferenceDecodesWithoutInlineContent() throws {
        let data = Data(
            """
            {
              "id": "work:legacy",
              "kind": "work",
              "title": "Legacy",
              "path": null,
              "updatedAt": "2026-01-01",
              "contentHash": "hash",
              "characterCount": 6,
              "includedCharacterCount": 6,
              "truncated": false
            }
            """.utf8
        )

        let reference = try JSONDecoder().decode(ContextSourceRef.self, from: data)

        XCTAssertNil(reference.inlineContent)
    }

    func testClarificationAnswerBecomesStableSource() {
        let sources = ContextPreparationService.clarificationAnswerSources(
            answers: [
                "cancel-idempotency": "  要求幂等  ",
                "empty": "   ",
            ]
        )

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].id, "clarification:cancel-idempotency")
        XCTAssertEqual(sources[0].reference.kind, "clarification_answer")
        XCTAssertEqual(sources[0].content, "要求幂等")
        XCTAssertEqual(sources[0].reference.includedCharacterCount, 4)
        XCTAssertFalse(sources[0].reference.contentHash.contains("要求幂等"))
        XCTAssertEqual(
            sources,
            ContextPreparationService.clarificationAnswerSources(
                answers: ["cancel-idempotency": "要求幂等"]
            )
        )
        XCTAssertEqual(
            ContextPreparationService.clarificationAnswers(
                from: sources.map(\.reference)
            ),
            ["cancel-idempotency": "要求幂等"]
        )
    }

    func testAnsweredQuestionIsResolvedIntoConfirmedFact() throws {
        let question = ContextQuestion(
            id: "cancel-idempotency",
            question: "取消预约是否要求幂等？",
            whyItMatters: "Affects API behavior",
            sourceIDs: ["source"]
        )
        let previous = makeContent(questions: [question])
        let repeated = makeContent(questions: [question])

        let resolved = ContextPreparationService.resolvingClarificationAnswers(
            in: repeated,
            previousDraft: previous,
            answers: [question.id: "要求幂等"]
        )

        XCTAssertTrue(resolved.questions.isEmpty)
        XCTAssertEqual(resolved.confirmedFacts.count, 1)
        XCTAssertEqual(
            resolved.confirmedFacts[0].sourceIDs,
            ["clarification:cancel-idempotency"]
        )
        XCTAssertTrue(resolved.confirmedFacts[0].text.contains("要求幂等"))
        XCTAssertNoThrow(
            try ContextPreparationService.validated(
                resolved,
                sourceIDs: ["source", "clarification:cancel-idempotency"]
            )
        )
    }

    func testApprovedConfirmationIsPreservedInNextDraft() {
        let sourceID = "clarification:cancel-idempotency"
        var previous = makeContent()
        previous.constraints = [
            ContextClaim(text: "Cancellation must be idempotent", sourceIDs: [sourceID])
        ]

        let resolved = ContextPreparationService.resolvingClarificationAnswers(
            in: makeContent(),
            previousDraft: previous,
            answers: ["cancel-idempotency": "Cancellation must be idempotent"]
        )

        XCTAssertEqual(resolved.constraints, previous.constraints)
    }

    func testRejectsOversizedStructuredSection() {
        let claims = (1...9).map {
            ContextClaim(text: "Claim \($0)", sourceIDs: ["source"])
        }
        let content = makeContent(scopeIn: claims)

        XCTAssertThrowsError(
            try ContextPreparationService.validated(content, sourceIDs: ["source"])
        ) { error in
            XCTAssertEqual(
                error as? ContextPreparationError,
                .invalidModelOutput("a context section contains more than eight items")
            )
        }
    }

    func testRejectsBriefBeyondOutputBudget() {
        let content = makeContent(brief: String(repeating: "a", count: 3_001))

        XCTAssertThrowsError(
            try ContextPreparationService.validated(content, sourceIDs: ["source"])
        ) { error in
            XCTAssertEqual(
                error as? ContextPreparationError,
                .invalidModelOutput("brief exceeds the context budget")
            )
        }
    }

    private func makeContent(
        scopeIn: [ContextClaim] = [],
        questions: [ContextQuestion] = [],
        brief: String = "Brief"
    ) -> ContextPackContent {
        ContextPackContent(
            objective: "Objective",
            scopeIn: scopeIn,
            scopeOut: [],
            confirmedFacts: [],
            constraints: [],
            acceptanceCriteria: [],
            assumptions: [],
            questions: questions,
            brief: brief,
            recommendedSourceIDs: []
        )
    }
}
