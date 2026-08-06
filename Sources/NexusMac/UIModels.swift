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

struct ContextPreparationUIState {
    var phase: ContextPreparationPhase = .preflight
    var input: ContextPreparationInput?
    var selectedSourceIDs: Set<String> = []
    var draft: ContextDraft?
    var draftBaseline: ContextPackContent?
    var draftBrief = ""
    var questionAnswers: [String: String] = [:]
    var error = ""
    var apiKeyInput = ""
    var apiKeyStatus = ""
    var hasAPIKey = false
    var modelProvider = storedContextModelProvider()
    var modelOverride: String?
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
