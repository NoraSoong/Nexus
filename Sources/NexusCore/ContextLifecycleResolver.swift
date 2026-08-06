public enum ContextLifecycleResolver {
    public static func resolve(
        hasConfirmedContext: Bool,
        materialsChanged: Bool,
        gitActivity: GitActivitySnapshot?,
        workingTreeState: GitWorkingTreeState
    ) -> ContextLifecycleState {
        guard hasConfirmedContext else { return .noConfirmedContext }

        switch gitActivity?.state {
        case .branchMismatch, .historyRewritten:
            return .needsConfirmation
        case .unavailable:
            return .workspaceUnavailable
        default:
            break
        }

        let codeChanged =
            gitActivity?.hasCodeChanges == true
            || workingTreeState == .modified
        switch (materialsChanged, codeChanged) {
        case (true, true):
            return .materialsAndCodeChanged
        case (true, false):
            return .materialsChanged
        case (false, true):
            return .codeChanged
        case (false, false):
            return .confirmed
        }
    }
}
