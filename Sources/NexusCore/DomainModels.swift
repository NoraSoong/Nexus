import Foundation

public enum GitWorkingTreeState: String, Codable, Equatable, Sendable {
    case clean
    case modified
    case unknown
}

public enum GitActivityState: String, Codable, Equatable, Sendable {
    case noBaseline = "no_baseline"
    case current
    case commitsAvailable = "commits_available"
    case branchMismatch = "branch_mismatch"
    case historyRewritten = "history_rewritten"
    case unavailable
}

public enum ContextLifecycleState: String, Codable, Equatable, Sendable {
    case noConfirmedContext = "no_confirmed_context"
    case confirmed
    case materialsChanged = "materials_changed"
    case codeChanged = "code_changed"
    case materialsAndCodeChanged = "materials_and_code_changed"
    case needsConfirmation = "needs_confirmation"
    case workspaceUnavailable = "workspace_unavailable"
}

public struct TaskRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var goal: String
    public var status: String
    public let createdAt: String
    public let updatedAt: String
}

public struct TaskNoteRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let taskID: String
    public var title: String
    public var body: String
    public var isExposedToMCP: Bool
    public let createdAt: String
    public let updatedAt: String
}

public struct CheckpointRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let taskID: String
    public var currentState: String
    public var nextStep: String
    public var blockers: String
    public let createdAt: String
}

public struct TaskFileRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let taskID: String
    public var displayName: String
    public let path: String
    public let fileType: String
    public let modifiedAt: String
    public var isVisibleToAgent: Bool
    public let createdAt: String
    public let updatedAt: String
}

public struct TaskRepositoryRecord: Equatable, Sendable {
    public let taskID: String
    public var path: String
    public var branch: String
    public let anchorHeadSHA: String?
    public let anchorBranch: String?
    public let anchorCapturedAt: String?
    public let updatedAt: String

    public init(
        taskID: String,
        path: String,
        branch: String,
        anchorHeadSHA: String? = nil,
        anchorBranch: String? = nil,
        anchorCapturedAt: String? = nil,
        updatedAt: String
    ) {
        self.taskID = taskID
        self.path = path
        self.branch = branch
        self.anchorHeadSHA = anchorHeadSHA
        self.anchorBranch = anchorBranch
        self.anchorCapturedAt = anchorCapturedAt
        self.updatedAt = updatedAt
    }
}

public struct ContextBindingRecord: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let scopeType: String
    public let scopeKey: String
    public let mode: String
    public let taskID: String
    public let activeRevision: Int64
    public let updatedAt: String

    public var workspacePath: String? {
        scopeType == "workspace" ? scopeKey : nil
    }
}

public struct GitWorkspaceInfo: Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let branch: String
    public let repositoryRoot: String
    public let commonDirectory: String
    public let kind: String
}

public struct GitPathState: Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let branch: String
    public let headSHA: String?
    public let dirtyState: GitWorkingTreeState
    public let workingTreeSignature: String?

    public init(
        path: String,
        branch: String,
        headSHA: String? = nil,
        dirtyState: GitWorkingTreeState,
        workingTreeSignature: String? = nil
    ) {
        self.path = path
        self.branch = branch
        self.headSHA = headSHA
        self.dirtyState = dirtyState
        self.workingTreeSignature = workingTreeSignature
    }
}

public struct GitContextBaseline: Codable, Equatable, Sendable {
    public let contextPackID: String?
    public let taskID: String
    public let workspacePath: String
    public let branch: String
    public let headSHA: String
    public let capturedAt: String

    public init(
        contextPackID: String?,
        taskID: String,
        workspacePath: String,
        branch: String,
        headSHA: String,
        capturedAt: String
    ) {
        self.contextPackID = contextPackID
        self.taskID = taskID
        self.workspacePath = workspacePath
        self.branch = branch
        self.headSHA = headSHA
        self.capturedAt = capturedAt
    }
}

public struct GitCommitSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sha }
    public let sha: String
    public let subject: String
    public let committedAt: String

    public init(sha: String, subject: String, committedAt: String) {
        self.sha = sha
        self.subject = subject
        self.committedAt = committedAt
    }
}

public struct GitChangedPath: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(status):\(previousPath ?? ""):\(path)" }
    public let status: String
    public let path: String
    public let previousPath: String?
    public let additions: Int?
    public let deletions: Int?
    public let isBinary: Bool

    public init(
        status: String,
        path: String,
        previousPath: String? = nil,
        additions: Int? = nil,
        deletions: Int? = nil,
        isBinary: Bool = false
    ) {
        self.status = status
        self.path = path
        self.previousPath = previousPath
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
    }
}

public struct GitActivitySnapshot: Codable, Equatable, Sendable {
    public let workspacePath: String
    public let linkedBranch: String
    public let currentBranch: String
    public let baselineHeadSHA: String?
    public let currentHeadSHA: String?
    public let state: GitActivityState
    public let commits: [GitCommitSummary]
    public let committedPaths: [GitChangedPath]
    public let dirtyPaths: [GitChangedPath]
    public let committedDiff: String?
    public let uncommittedDiff: String?
    public let capturedAt: String

    public var hasCodeChanges: Bool {
        state == .commitsAvailable || !dirtyPaths.isEmpty
    }

    public init(
        workspacePath: String,
        linkedBranch: String,
        currentBranch: String,
        baselineHeadSHA: String?,
        currentHeadSHA: String?,
        state: GitActivityState,
        commits: [GitCommitSummary],
        committedPaths: [GitChangedPath],
        dirtyPaths: [GitChangedPath],
        committedDiff: String?,
        uncommittedDiff: String?,
        capturedAt: String
    ) {
        self.workspacePath = workspacePath
        self.linkedBranch = linkedBranch
        self.currentBranch = currentBranch
        self.baselineHeadSHA = baselineHeadSHA
        self.currentHeadSHA = currentHeadSHA
        self.state = state
        self.commits = commits
        self.committedPaths = committedPaths
        self.dirtyPaths = dirtyPaths
        self.committedDiff = committedDiff
        self.uncommittedDiff = uncommittedDiff
        self.capturedAt = capturedAt
    }
}

public struct TaskSupplementRecord: Equatable, Sendable {
    public let taskID: String
    public var body: String
    public let updatedAt: String
}

public struct ActiveTaskProjection: Equatable, Sendable {
    public let taskID: String
    public let title: String
    public let revision: Int64
    public let freshness: String
    public let payloadJSON: String
}

public struct ProjectionSnapshot: Equatable, Sendable {
    public let activeTaskJSON: String
    public let manifestJSON: String
    public let resumeBriefJSON: String
}
