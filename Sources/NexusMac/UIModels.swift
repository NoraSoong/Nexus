import AppKit
import NexusCore
import SwiftUI

enum ContextPreparationPhase: Equatable {
    case loadingSources
    case preflight
    case preparing
    case review
}

enum SaveState: Equatable {
    case saved
    case failed
}

@MainActor
final class ContextPreparationModel {
    var phase: ContextPreparationPhase = .preflight
    var input: ContextPreparationInput?
    var selectedSourceIDs: Set<String> = []
    var draft: ContextDraft?
    var draftBaseline: ContextPackContent?
    var draftBrief = ""
    var questionAnswers: [String: String] = [:]
    var error = ""
    var diagnostic = ""
    var apiKeyInput = ""
    var apiKeyStatus = ""
    var hasAPIKey = false
    var modelProvider = storedContextModelProvider()
    var modelSelection = storedContextModel(for: storedContextModelProvider())

    func comparison(to currentPack: ContextPack?) -> ContextPackDiff? {
        guard let candidate = candidateContent else { return nil }
        return ContextReviewService.compare(
            candidate: candidate,
            candidateSources: draft?.sourceManifest ?? [],
            baseline: currentPack
        )
    }

    func findings(currentPack: ContextPack?) -> [ContextReviewFinding] {
        guard let candidate = candidateContent else { return [] }
        return ContextReviewService.findings(
            content: candidate,
            sources: draft?.sourceManifest ?? [],
            sourceChanges: comparison(to: currentPack)?.sourceChanges ?? []
        )
    }

    private var candidateContent: ContextPackContent? {
        guard var content = draft?.content else { return nil }
        content.brief = draftBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        return content
    }
}

struct AssistantConnectionUIState {
    var ready = false
    var status = ""
    var detail = ""
    var doctor = ""
}

enum ContextClaimSection {
    case scopeIn
    case scopeOut
    case confirmedFacts
    case constraints
    case acceptanceCriteria
    case assumptions
}

struct ConfirmationRequest: Identifiable {
    enum Kind {
        case archive(String)
        case delete(String)
        case removeTextMaterial(String, String)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let confirmTitle: String
}

struct AssistantContextIssue: Identifiable, Equatable {
    enum Tone {
        case warning
        case info
    }

    let id: String
    let title: String
    let message: String
    let systemImage: String
    let tone: Tone
}
