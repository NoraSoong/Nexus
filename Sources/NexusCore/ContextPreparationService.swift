import CryptoKit
import Foundation

public enum ContextPreparationService {
    public static let clarificationAnswerKind = "clarification_answer"

    public static func modelRequest(
        input: ContextPreparationInput,
        selectedSourceIDs: Set<String>,
        language: String,
        previousDraft: ContextPackContent? = nil,
        answers: [String: String] = [:]
    ) throws -> ContextModelRequest {
        let selectedSources = input.sources.filter { selectedSourceIDs.contains($0.id) }
        guard !selectedSources.isEmpty else { throw ContextPreparationError.noReadableSources }
        let sources = selectedSources + clarificationAnswerSources(answers: answers)
        return ContextModelRequest(
            taskID: input.taskID,
            language: language,
            sources: sources,
            previousDraft: previousDraft,
            answers: answers
        )
    }

    public static func clarificationAnswerSources(
        answers: [String: String]
    ) -> [ContextSourceDocument] {
        answers
            .compactMap { questionID, rawAnswer -> (String, String)? in
                let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                return answer.isEmpty ? nil : (questionID, answer)
            }
            .sorted { $0.0 < $1.0 }
            .map { questionID, answer in
                let sourceID = clarificationAnswerSourceID(questionID: questionID)
                let compactAnswer = answer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let title =
                    compactAnswer.count > 80
                    ? "\(compactAnswer.prefix(77))..."
                    : compactAnswer
                return ContextSourceDocument(
                    reference: ContextSourceRef(
                        id: sourceID,
                        kind: clarificationAnswerKind,
                        title: title,
                        path: nil,
                        updatedAt: "user-confirmed",
                        contentHash: contentHash(answer),
                        characterCount: answer.count,
                        includedCharacterCount: answer.count,
                        truncated: false,
                        inlineContent: answer
                    ),
                    content: answer
                )
            }
    }

    public static func clarificationAnswerSourceID(questionID: String) -> String {
        "clarification:\(questionID)"
    }

    public static func clarificationAnswers(
        from references: [ContextSourceRef]
    ) -> [String: String] {
        var answers: [String: String] = [:]
        for reference in references {
            guard reference.kind == clarificationAnswerKind,
                reference.id.hasPrefix("clarification:")
            else {
                continue
            }
            let answer = (reference.inlineContent ?? reference.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { continue }
            let questionID = String(reference.id.dropFirst("clarification:".count))
            answers[questionID] = answer
        }
        return answers
    }

    public static func resolvingClarificationAnswers(
        in content: ContextPackContent,
        previousDraft: ContextPackContent?,
        answers: [String: String]
    ) -> ContextPackContent {
        guard let previousDraft, !answers.isEmpty else { return content }
        var resolved = content

        for (questionID, rawAnswer) in answers.sorted(by: { $0.key < $1.key }) {
            let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { continue }

            let sourceID = clarificationAnswerSourceID(questionID: questionID)
            preserveClaims(citing: sourceID, from: previousDraft, in: &resolved)

            let previousQuestion = previousDraft.questions.first { $0.id == questionID }
            if let previousQuestion {
                let normalizedPreviousQuestion = normalized(previousQuestion.question)
                resolved.questions.removeAll {
                    $0.id == previousQuestion.id
                        || normalized($0.question) == normalizedPreviousQuestion
                }
            }

            guard !allClaims(in: resolved).contains(where: { $0.sourceIDs.contains(sourceID) }) else {
                continue
            }
            guard let previousQuestion else { continue }
            resolved.confirmedFacts.insert(
                ContextClaim(
                    text: "\(previousQuestion.question) \(answer)",
                    sourceIDs: [sourceID]
                ),
                at: 0
            )
            resolved.confirmedFacts = Array(resolved.confirmedFacts.prefix(8))
        }
        return resolved
    }

    public static func validated(_ content: ContextPackContent, sourceIDs: Set<String>) throws -> ContextPackContent {
        guard !content.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContextPreparationError.invalidModelOutput("objective is empty")
        }
        guard !content.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContextPreparationError.invalidModelOutput("brief is empty")
        }
        guard content.questions.count <= 5 else {
            throw ContextPreparationError.invalidModelOutput("more than five clarification questions")
        }
        let sections = [
            content.scopeIn,
            content.scopeOut,
            content.confirmedFacts,
            content.constraints,
            content.acceptanceCriteria,
            content.assumptions,
        ]
        guard sections.allSatisfy({ $0.count <= 8 }) else {
            throw ContextPreparationError.invalidModelOutput("a context section contains more than eight items")
        }
        guard content.brief.count <= 3_000 else {
            throw ContextPreparationError.invalidModelOutput("brief exceeds the context budget")
        }
        let questionIDs = content.questions.map {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard Set(questionIDs).count == content.questions.count else {
            throw ContextPreparationError.invalidModelOutput("clarification question ids are not unique")
        }

        let sourcedClaims =
            content.scopeIn + content.scopeOut + content.confirmedFacts + content.constraints
            + content.acceptanceCriteria
        for claim in sourcedClaims {
            guard !claim.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContextPreparationError.invalidModelOutput("an empty claim was returned")
            }
            guard !claim.sourceIDs.isEmpty else {
                throw ContextPreparationError.invalidSourceCitation(.missingRequiredSource)
            }
            let unknownSourceIDs = Set(claim.sourceIDs).subtracting(sourceIDs).sorted()
            guard unknownSourceIDs.isEmpty else {
                throw ContextPreparationError.invalidSourceCitation(.unknownSources(unknownSourceIDs))
            }
        }
        for assumption in content.assumptions {
            guard !assumption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContextPreparationError.invalidModelOutput("an empty assumption was returned")
            }
            let unknownSourceIDs = Set(assumption.sourceIDs).subtracting(sourceIDs).sorted()
            guard unknownSourceIDs.isEmpty else {
                throw ContextPreparationError.invalidSourceCitation(.unknownSources(unknownSourceIDs))
            }
        }
        for question in content.questions {
            guard !question.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !question.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !question.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                Set(question.sourceIDs).isSubset(of: sourceIDs)
            else {
                let unknownSourceIDs = Set(question.sourceIDs).subtracting(sourceIDs).sorted()
                if !unknownSourceIDs.isEmpty {
                    throw ContextPreparationError.invalidSourceCitation(.unknownSources(unknownSourceIDs))
                }
                throw ContextPreparationError.invalidModelOutput(
                    "a clarification question is invalid or references an unknown source")
            }
        }
        let unknownRecommendedSourceIDs = Set(content.recommendedSourceIDs)
            .subtracting(sourceIDs)
            .sorted()
        guard unknownRecommendedSourceIDs.isEmpty else {
            throw ContextPreparationError.invalidSourceCitation(
                .unknownRecommendedSources(unknownRecommendedSourceIDs)
            )
        }
        return content
    }

    private static func allClaims(in content: ContextPackContent) -> [ContextClaim] {
        content.scopeIn
            + content.scopeOut
            + content.confirmedFacts
            + content.constraints
            + content.acceptanceCriteria
            + content.assumptions
    }

    private static func preserveClaims(
        citing sourceID: String,
        from previous: ContextPackContent,
        in current: inout ContextPackContent
    ) {
        current.scopeIn = mergingClaims(current.scopeIn, previous.scopeIn, citing: sourceID)
        current.scopeOut = mergingClaims(current.scopeOut, previous.scopeOut, citing: sourceID)
        current.confirmedFacts = mergingClaims(
            current.confirmedFacts,
            previous.confirmedFacts,
            citing: sourceID
        )
        current.constraints = mergingClaims(
            current.constraints,
            previous.constraints,
            citing: sourceID
        )
        current.acceptanceCriteria = mergingClaims(
            current.acceptanceCriteria,
            previous.acceptanceCriteria,
            citing: sourceID
        )
        current.assumptions = mergingClaims(
            current.assumptions,
            previous.assumptions,
            citing: sourceID
        )
    }

    private static func mergingClaims(
        _ current: [ContextClaim],
        _ previous: [ContextClaim],
        citing sourceID: String
    ) -> [ContextClaim] {
        let retained = previous.filter { $0.sourceIDs.contains(sourceID) }
        guard !retained.isEmpty else { return current }
        var merged = current
        for claim in retained.reversed() where !merged.contains(claim) {
            merged.insert(claim, at: 0)
        }
        return Array(merged.prefix(8))
    }

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func contentHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
