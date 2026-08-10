import Foundation

public struct ContextSourceRef: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let path: String?
    public let updatedAt: String
    public let contentHash: String
    public let characterCount: Int
    public let includedCharacterCount: Int
    public let truncated: Bool
    public let inlineContent: String?
    public let fingerprintVersion: Int?

    public init(
        id: String,
        kind: String,
        title: String,
        path: String?,
        updatedAt: String,
        contentHash: String,
        characterCount: Int,
        includedCharacterCount: Int,
        truncated: Bool,
        inlineContent: String? = nil,
        fingerprintVersion: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.path = path
        self.updatedAt = updatedAt
        self.contentHash = contentHash
        self.characterCount = characterCount
        self.includedCharacterCount = includedCharacterCount
        self.truncated = truncated
        self.inlineContent = inlineContent
        self.fingerprintVersion = fingerprintVersion
    }
}

public struct ContextSourceDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: String { reference.id }
    public let reference: ContextSourceRef
    public let content: String

    public init(reference: ContextSourceRef, content: String) {
        self.reference = reference
        self.content = content
    }
}

public enum ContextSourceExclusionReason: String, Codable, Equatable, Sendable {
    case hidden
    case missing
    case directory
    case unsupportedType = "unsupported_type"
    case empty
    case binary
    case invalidEncoding = "invalid_encoding"
    case tooLarge = "too_large"
    case changedDuringRead = "changed_during_read"
    case unreadable
    case budgetExceeded = "budget_exceeded"
}

public struct ContextSourceExclusion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let path: String?
    public let reason: ContextSourceExclusionReason

    public init(id: String, title: String, path: String?, reason: ContextSourceExclusionReason) {
        self.id = id
        self.title = title
        self.path = path
        self.reason = reason
    }
}

public struct ContextPreparationInput: Codable, Equatable, Sendable {
    public let taskID: String
    public let baseRevision: Int64
    public let sources: [ContextSourceDocument]
    public let excludedSources: [ContextSourceExclusion]
    public let totalIncludedCharacters: Int

    public init(
        taskID: String,
        baseRevision: Int64,
        sources: [ContextSourceDocument],
        excludedSources: [ContextSourceExclusion],
        totalIncludedCharacters: Int
    ) {
        self.taskID = taskID
        self.baseRevision = baseRevision
        self.sources = sources
        self.excludedSources = excludedSources
        self.totalIncludedCharacters = totalIncludedCharacters
    }
}

public struct ContextClaim: Codable, Equatable, Sendable {
    public var text: String
    public var sourceIDs: [String]

    public init(text: String, sourceIDs: [String]) {
        self.text = text
        self.sourceIDs = sourceIDs
    }
}

public struct ContextQuestion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var question: String
    public var whyItMatters: String
    public var sourceIDs: [String]

    public init(id: String, question: String, whyItMatters: String, sourceIDs: [String]) {
        self.id = id
        self.question = question
        self.whyItMatters = whyItMatters
        self.sourceIDs = sourceIDs
    }
}

public struct ContextPackContent: Codable, Equatable, Sendable {
    public var objective: String
    public var scopeIn: [ContextClaim]
    public var scopeOut: [ContextClaim]
    public var confirmedFacts: [ContextClaim]
    public var constraints: [ContextClaim]
    public var acceptanceCriteria: [ContextClaim]
    public var assumptions: [ContextClaim]
    public var questions: [ContextQuestion]
    public var brief: String
    public var recommendedSourceIDs: [String]

    public init(
        objective: String,
        scopeIn: [ContextClaim],
        scopeOut: [ContextClaim],
        confirmedFacts: [ContextClaim],
        constraints: [ContextClaim],
        acceptanceCriteria: [ContextClaim],
        assumptions: [ContextClaim],
        questions: [ContextQuestion],
        brief: String,
        recommendedSourceIDs: [String]
    ) {
        self.objective = objective
        self.scopeIn = scopeIn
        self.scopeOut = scopeOut
        self.confirmedFacts = confirmedFacts
        self.constraints = constraints
        self.acceptanceCriteria = acceptanceCriteria
        self.assumptions = assumptions
        self.questions = questions
        self.brief = brief
        self.recommendedSourceIDs = recommendedSourceIDs
    }
}

public struct ContextModelRequest: Equatable, Sendable {
    public let taskID: String
    public let language: String
    public let sources: [ContextSourceDocument]
    public let previousDraft: ContextPackContent?
    public let answers: [String: String]

    public init(
        taskID: String,
        language: String,
        sources: [ContextSourceDocument],
        previousDraft: ContextPackContent? = nil,
        answers: [String: String] = [:]
    ) {
        self.taskID = taskID
        self.language = language
        self.sources = sources
        self.previousDraft = previousDraft
        self.answers = answers
    }
}

public enum ContextModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepSeek = "deepseek"
    case openAI = "openai"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .openAI: return "OpenAI"
        }
    }

    public var defaultModel: String {
        switch self {
        case .deepSeek: return DeepSeekContextModelClient.defaultModel
        case .openAI: return "gpt-5.4-mini"
        }
    }

    public var defaultModelDisplayName: String {
        switch self {
        case .deepSeek: return "V4 Flash"
        case .openAI: return "GPT-5.4 mini"
        }
    }

    public func displayName(for model: String) -> String {
        switch (self, model) {
        case (.deepSeek, DeepSeekContextModelClient.flashModel):
            return "V4 Flash"
        case (.deepSeek, DeepSeekContextModelClient.proModel):
            return "V4 Pro"
        case (.openAI, "gpt-5.4-mini"):
            return "GPT-5.4 mini"
        default:
            return model
        }
    }
}

public struct ContextModelConfiguration: Codable, Equatable, Sendable {
    public let provider: ContextModelProvider
    public let model: String

    public init(provider: ContextModelProvider, model: String? = nil) {
        self.provider = provider
        self.model = model ?? provider.defaultModel
    }
}

public protocol ContextModelClient: Sendable {
    var configuration: ContextModelConfiguration { get }
    func validateConnection(apiKey: String) async throws
    func generate(request: ContextModelRequest, apiKey: String) async throws -> ContextPackContent
}

public struct ContextDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let taskID: String
    public let baseRevision: Int64
    public let provider: String
    public let model: String
    public var content: ContextPackContent
    public let sourceManifest: [ContextSourceRef]
    public var answers: [String: String]
    public var status: String
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        taskID: String,
        baseRevision: Int64,
        provider: String,
        model: String,
        content: ContextPackContent,
        sourceManifest: [ContextSourceRef],
        answers: [String: String],
        status: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.taskID = taskID
        self.baseRevision = baseRevision
        self.provider = provider
        self.model = model
        self.content = content
        self.sourceManifest = sourceManifest
        self.answers = answers
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ContextPack: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let taskID: String
    public let revision: Int64
    public let content: ContextPackContent
    public let sourceManifest: [ContextSourceRef]
    public let freshness: String
    public let staleReason: String?
    public let createdAt: String

    public init(
        id: String,
        taskID: String,
        revision: Int64,
        content: ContextPackContent,
        sourceManifest: [ContextSourceRef],
        freshness: String,
        staleReason: String?,
        createdAt: String
    ) {
        self.id = id
        self.taskID = taskID
        self.revision = revision
        self.content = content
        self.sourceManifest = sourceManifest
        self.freshness = freshness
        self.staleReason = staleReason
        self.createdAt = createdAt
    }
}

public enum ContextPreparationError: LocalizedError, Equatable {
    case noReadableSources
    case invalidModelOutput(String)
    case staleDraft
    case draftNotFound

    public var errorDescription: String? {
        switch self {
        case .noReadableSources:
            return "No readable context sources are available."
        case .invalidModelOutput(let detail):
            return "The model returned an invalid context draft: \(detail)"
        case .staleDraft:
            return "The work changed after this draft was generated. Prepare it again before applying."
        case .draftNotFound:
            return "The context draft no longer exists."
        }
    }
}
