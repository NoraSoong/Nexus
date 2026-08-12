import Foundation

public enum WorkspaceAssociationError: LocalizedError, Equatable, Sendable {
    case notGitWorkspace(String)
    case alreadyBound(path: String, taskID: String)
    case alreadyLinked(path: String, taskID: String)
    case pathUnavailable(String)
    case taskNotFound(String)
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .notGitWorkspace(let path):
            return "The directory is not a Git workspace: \(path)"
        case .alreadyBound(let path, let taskID):
            return "The workspace is already bound to task \(taskID): \(path)"
        case .alreadyLinked(let path, let taskID):
            return "The workspace is already linked to task \(taskID): \(path)"
        case .pathUnavailable(let path):
            return "The workspace path is unavailable: \(path)"
        case .taskNotFound(let taskID):
            return "The work does not exist: \(taskID)"
        case .persistence(let detail):
            return "The workspace association could not be saved: \(detail)"
        }
    }
}
