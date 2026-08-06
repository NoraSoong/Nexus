import Foundation

enum GitActivityContextFormatter {
    static func committedContent(_ activity: GitActivitySnapshot) -> String {
        var sections = [
            "Evidence type: committed code changes",
            "Workspace: \(activity.workspacePath)",
            "Linked branch: \(activity.linkedBranch)",
            "Current branch: \(activity.currentBranch)",
            "Baseline HEAD: \(activity.baselineHeadSHA ?? "none")",
            "Current HEAD: \(activity.currentHeadSHA ?? "unavailable")",
            "Activity state: \(activity.state.rawValue)",
            "Important: this evidence proves code changes, not requirement completion or test success.",
        ]

        if !activity.commits.isEmpty {
            sections.append(
                """
                Commits:
                \(activity.commits.map(commitLine).joined(separator: "\n"))
                """
            )
        }
        if !activity.committedPaths.isEmpty {
            sections.append(
                """
                Changed paths:
                \(activity.committedPaths.map(pathLine).joined(separator: "\n"))
                """
            )
        }
        if let diff = activity.committedDiff, !diff.isEmpty {
            sections.append(
                """
                Diff:
                \(diff)
                """
            )
        }
        return sections.joined(separator: "\n\n")
    }

    static func uncommittedContent(_ activity: GitActivitySnapshot) -> String {
        var sections = [
            "Evidence type: uncommitted workspace changes",
            "Workspace: \(activity.workspacePath)",
            "Current branch: \(activity.currentBranch)",
            "Current HEAD: \(activity.currentHeadSHA ?? "unavailable")",
            "Important: these changes may be temporary. Do not treat them as confirmed progress or completion.",
        ]

        if !activity.dirtyPaths.isEmpty {
            sections.append(
                """
                Working tree paths:
                \(activity.dirtyPaths.map(pathLine).joined(separator: "\n"))
                """
            )
        }
        if let diff = activity.uncommittedDiff, !diff.isEmpty {
            sections.append(
                """
                Working tree diff:
                \(diff)
                """
            )
        }
        return sections.joined(separator: "\n\n")
    }

    private static func commitLine(_ commit: GitCommitSummary) -> String {
        "- \(String(commit.sha.prefix(10))) \(commit.subject) (\(commit.committedAt))"
    }

    private static func pathLine(_ path: GitChangedPath) -> String {
        let route =
            if let previousPath = path.previousPath {
                "\(previousPath) -> \(path.path)"
            } else {
                path.path
            }
        let stats: String
        if path.isBinary {
            stats = "binary"
        } else if let additions = path.additions, let deletions = path.deletions {
            stats = "+\(additions) -\(deletions)"
        } else {
            stats = ""
        }
        return ["- \(path.status) \(route)", stats]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
