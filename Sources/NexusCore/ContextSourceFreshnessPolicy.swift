import Foundation

enum ContextSourceFreshnessPolicy {
    static func participatesInFreshness(_ source: ContextSourceRef) -> Bool {
        !ContextMaterialExtractor.isGitActivityKind(source.kind)
    }

    static func hasChanged(baseline: ContextSourceRef, current: ContextSourceRef) -> Bool {
        guard baseline.kind == "repository",
            baseline.fingerprintVersion != ContextMaterialExtractor.repositoryFingerprintVersion
        else {
            return baseline.contentHash != current.contentHash
        }

        guard let baselinePath = baseline.path, let currentPath = current.path else {
            return baseline.contentHash != current.contentHash
        }
        return WorkspacePath.normalize(baselinePath) != WorkspacePath.normalize(currentPath)
    }
}
