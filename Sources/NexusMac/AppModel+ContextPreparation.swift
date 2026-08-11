import Foundation
import NexusCore

@MainActor
extension AppModel {
    func beginContextPreparation() {
        guard let taskID = selectedTaskID,
            let task = tasks.first(where: { $0.id == taskID })
        else {
            showToast(l10n.contextPreparationFailed)
            return
        }
        contextPreparationTask?.cancel()
        contextPreparationModelOverride = nil
        contextPreparationError = ""
        contextPreparationDiagnostic = ""
        contextPreparationPhase = .loadingSources
        showContextPreparationSheet = true
        contextPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (input, pendingDraft) = try await performStoreOperation { store in
                    let input = try Self.makeContextPreparationInput(
                        task: task,
                        taskID: taskID,
                        store: store
                    )
                    return (input, try store.latestContextDraft(taskID: taskID))
                }
                guard !Task.isCancelled, selectedTaskID == taskID else { return }
                contextPreparationInput = input
                contextDraft = pendingDraft
                configureContextPreparation(input: input, pendingDraft: pendingDraft)
                contextAPIKeyStatus = ""
                hasContextAPIKey = try !(keychainCredentialStore.loadKey(for: contextModelProvider) ?? "").isEmpty
            } catch is CancellationError {
                showContextPreparationSheet = false
            } catch {
                contextPreparationDiagnostic = error.localizedDescription
                contextPreparationError = l10n.contextPreparationErrorMessage(error)
                contextPreparationPhase = .preflight
            }
        }
    }

    private func configureContextPreparation(input: ContextPreparationInput, pendingDraft: ContextDraft?) {
        if let pendingDraft {
            let draftMaterialSourceIDs = Set(
                pendingDraft.sourceManifest
                    .filter { $0.kind != ContextPreparationService.clarificationAnswerKind }
                    .map(\.id)
            )
            let currentDraftSources =
                input.sources
                .filter { draftMaterialSourceIDs.contains($0.id) }
                .map(\.reference)
                + ContextPreparationService.clarificationAnswerSources(
                    answers: pendingDraft.answers
                ).map(\.reference)
            let confirmedPackIsCurrent =
                currentContextPack.map { $0.revision <= pendingDraft.baseRevision }
                ?? true
            let draftIsCurrent =
                confirmedPackIsCurrent
                && currentDraftSources.count == pendingDraft.sourceManifest.count
                && ContextMaterialExtractor.manifestFingerprint(currentDraftSources)
                    == ContextMaterialExtractor.manifestFingerprint(pendingDraft.sourceManifest)
            selectedContextSourceIDs =
                draftIsCurrent
                ? draftMaterialSourceIDs
                : Self.defaultSelectedContextSourceIDs(input)
            contextPreparationError = draftIsCurrent ? "" : l10n.contextDraftOutdated
            contextPreparationPhase = draftIsCurrent ? .review : .preflight
        } else {
            selectedContextSourceIDs = Self.defaultSelectedContextSourceIDs(input)
            contextPreparationError = ""
            contextPreparationPhase = .preflight
        }
        contextDraftBrief = contextDraft?.content.brief ?? ""
        contextDraftBaseline = contextDraft?.content
        contextQuestionAnswers =
            contextDraft?.answers
            ?? currentContextPack.map {
                ContextPreparationService.clarificationAnswers(from: $0.sourceManifest)
            }
            ?? [:]
    }

    var contextModelConfiguration: ContextModelConfiguration {
        ContextModelConfiguration(
            provider: contextModelProvider,
            model: contextPreparationModelOverride
        )
    }

    var canPrepareWithDeepSeekPro: Bool {
        contextModelProvider == .deepSeek
            && contextModelConfiguration.model != DeepSeekContextModelClient.proModel
            && hasContextAPIKey
    }

    func selectContextModelProvider(_ provider: ContextModelProvider) {
        guard contextModelProvider != provider else { return }
        contextPreparationTask?.cancel()
        contextModelProvider = provider
        contextPreparationModelOverride = nil
        isReplacingContextModelKey = false
        UserDefaults.standard.set(provider.rawValue, forKey: contextModelProviderDefaultsKey)
        contextAPIKeyInput = ""
        contextAPIKeyStatus = ""
        hasContextAPIKey = ((try? keychainCredentialStore.loadKey(for: provider)) ?? nil)?.isEmpty == false
    }

    func connectContextModel() {
        let key = contextAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            contextAPIKeyStatus = l10n.contextAPIKeyRequired
            return
        }
        let provider = contextModelProvider
        let client = ContextModelClientFactory.make(configuration: contextModelConfiguration)
        contextAPIKeyStatus = l10n.verifying
        contextPreparationTask?.cancel()
        contextPreparationTask = Task { @MainActor in
            do {
                try await client.validateConnection(apiKey: key)
                guard !Task.isCancelled, contextModelProvider == provider else { return }
                try keychainCredentialStore.saveKey(key, for: provider)
                contextAPIKeyInput = ""
                hasContextAPIKey = true
                isReplacingContextModelKey = false
                contextAPIKeyStatus = l10n.connectionVerified
                UserDefaults.standard.set(provider.rawValue, forKey: contextModelProviderDefaultsKey)
            } catch is CancellationError {
                return
            } catch {
                if (error as? URLError)?.code == .cancelled { return }
                guard contextModelProvider == provider else { return }
                contextAPIKeyStatus = l10n.contextPreparationErrorMessage(error)
            }
        }
    }

    func beginContextModelKeyReplacement() {
        contextPreparationTask?.cancel()
        contextAPIKeyInput = ""
        contextAPIKeyStatus = ""
        isReplacingContextModelKey = true
    }

    func cancelContextModelKeyReplacement() {
        guard isReplacingContextModelKey else { return }
        isReplacingContextModelKey = false
        contextAPIKeyInput = ""
        contextAPIKeyStatus = ""
        hasContextAPIKey = ((try? keychainCredentialStore.loadKey(for: contextModelProvider)) ?? nil)?.isEmpty == false
    }

    func removeContextAPIKey() {
        do {
            try keychainCredentialStore.deleteKey(for: contextModelProvider)
            contextAPIKeyInput = ""
            hasContextAPIKey = false
            isReplacingContextModelKey = false
            contextAPIKeyStatus = l10n.contextAPIKeyRemoved
        } catch {
            contextAPIKeyStatus = error.localizedDescription
        }
    }

    func verifyContextAPIKey() {
        guard let key = loadedContextAPIKey() else {
            contextAPIKeyStatus = l10n.contextAPIKeyRequired
            return
        }
        contextAPIKeyStatus = l10n.verifying
        let provider = contextModelProvider
        let client = ContextModelClientFactory.make(configuration: contextModelConfiguration)
        contextPreparationTask?.cancel()
        contextPreparationTask = Task { @MainActor in
            do {
                try await client.validateConnection(apiKey: key)
                guard !Task.isCancelled, contextModelProvider == provider else { return }
                contextAPIKeyStatus = l10n.connectionVerified
            } catch is CancellationError {
                return
            } catch {
                if (error as? URLError)?.code == .cancelled { return }
                contextAPIKeyStatus = l10n.contextPreparationErrorMessage(error)
            }
        }
    }

    func generateContextDraft() {
        guard let input = contextPreparationInput else { return }
        guard let key = loadedContextAPIKey() else {
            hasContextAPIKey = false
            contextPreparationError = l10n.contextAPIKeyRequired
            return
        }
        do {
            let request = try ContextPreparationService.modelRequest(
                input: input,
                selectedSourceIDs: selectedContextSourceIDs,
                language: contextOutputLanguage,
                previousDraft: contextDraft?.content ?? currentContextPack?.content,
                answers: contextQuestionAnswers
            )
            contextPreparationError = ""
            contextPreparationDiagnostic = ""
            contextPreparationPhase = .preparing
            let client = ContextModelClientFactory.make(configuration: contextModelConfiguration)
            let oldDraftID = contextDraft?.id
            let answers = contextQuestionAnswers
            contextPreparationTask?.cancel()
            contextPreparationTask = Task { @MainActor in
                do {
                    let content = try await client.generate(request: request, apiKey: key)
                    guard !Task.isCancelled else { return }
                    let draft = try await performStoreOperation { store in
                        if let oldDraftID {
                            try? store.discardContextDraft(id: oldDraftID)
                        }
                        return try store.saveContextDraft(
                            taskID: input.taskID,
                            baseRevision: input.baseRevision,
                            provider: client.configuration.provider.rawValue,
                            model: client.configuration.model,
                            content: content,
                            sourceManifest: request.sources.map(\.reference),
                            answers: answers
                        )
                    }
                    guard !Task.isCancelled else { return }
                    contextDraft = draft
                    contextDraftBaseline = draft.content
                    contextDraftBrief = draft.content.brief
                    contextPreparationPhase = .review
                } catch is CancellationError {
                    contextPreparationPhase = .preflight
                } catch {
                    if (error as? URLError)?.code == .cancelled {
                        contextPreparationPhase = contextDraft == nil ? .preflight : .review
                        return
                    }
                    contextPreparationDiagnostic = error.localizedDescription
                    contextPreparationError = l10n.contextPreparationErrorMessage(error)
                    contextPreparationPhase = .preflight
                }
            }
        } catch {
            contextPreparationDiagnostic = error.localizedDescription
            contextPreparationError = l10n.contextPreparationErrorMessage(error)
        }
    }

    func generateContextDraftWithDeepSeekPro() {
        guard contextModelProvider == .deepSeek else { return }
        contextPreparationModelOverride = DeepSeekContextModelClient.proModel
        generateContextDraft()
    }

    func cancelContextPreparationRequest() {
        contextPreparationTask?.cancel()
        contextPreparationTask = nil
        contextPreparationPhase = contextDraft == nil ? .preflight : .review
    }

    func approvePreparedContext() {
        guard var draft = contextDraft,
            let task = tasks.first(where: { $0.id == draft.taskID })
        else { return }
        do {
            draft.content.brief = contextDraftBrief.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.content = try ContextPreparationService.validated(
                draft.content,
                sourceIDs: Set(draft.sourceManifest.map(\.id))
            )
            let answers = contextQuestionAnswers
            let selectedSourceIDs = selectedContextSourceIDs
            let draftID = draft.id
            let draftTaskID = draft.taskID
            let draftContent = draft.content
            contextPreparationTask?.cancel()
            contextPreparationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let pack = try await performStoreOperation { store in
                        try store.updateContextDraft(id: draftID, content: draftContent, answers: answers)
                        let currentInput = try Self.makeContextPreparationInput(
                            task: task,
                            taskID: draftTaskID,
                            store: store
                        )
                        let selectedSources =
                            currentInput.sources.filter { selectedSourceIDs.contains($0.id) }
                            + ContextPreparationService.clarificationAnswerSources(answers: answers)
                        let selectedInput = ContextPreparationInput(
                            taskID: currentInput.taskID,
                            baseRevision: currentInput.baseRevision,
                            sources: selectedSources,
                            excludedSources: currentInput.excludedSources,
                            totalIncludedCharacters: selectedSources.reduce(0) {
                                $0 + $1.reference.includedCharacterCount
                            }
                        )
                        return try store.approveContextDraft(id: draftID, currentInput: selectedInput)
                    }
                    guard !Task.isCancelled else { return }
                    currentContextPack = pack
                    showContextPreparationSheet = false
                    showToast(l10n.contextPackApplied)
                    refresh()
                } catch is CancellationError {
                    return
                } catch {
                    contextPreparationDiagnostic = error.localizedDescription
                    contextPreparationError = l10n.contextPreparationErrorMessage(error)
                }
            }
        } catch {
            contextPreparationDiagnostic = error.localizedDescription
            contextPreparationError = l10n.contextPreparationErrorMessage(error)
        }
    }

    func discardPreparedContext() {
        contextPreparationTask?.cancel()
        if let draft = contextDraft {
            Task {
                try? await performStoreOperation { store in
                    try store.discardContextDraft(id: draft.id)
                }
            }
        }
        contextDraft = nil
        contextDraftBaseline = nil
        contextDraftBrief = ""
        contextQuestionAnswers = [:]
        showContextPreparationSheet = false
    }

    func sourceTitle(for id: String) -> String {
        contextPreparationInput?.sources.first(where: { $0.id == id })?.reference.title
            ?? contextDraft?.sourceManifest.first(where: { $0.id == id })?.title
            ?? currentContextPack?.sourceManifest.first(where: { $0.id == id })?.title
            ?? id
    }

    func refreshCurrentContextSourceChanges() {
        guard let taskID = selectedTaskID, currentContextPack != nil else {
            currentContextSourceChanges = []
            return
        }
        contextSourceRefreshTask?.cancel()
        contextSourceRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let changes = try await performStoreOperation(priority: .utility) { store in
                    try store.currentContextSourceChanges(taskID: taskID)
                }
                guard !Task.isCancelled, selectedTaskID == taskID else { return }
                currentContextSourceChanges = changes
            } catch is CancellationError {
                return
            } catch {
                currentContextSourceChanges = []
                message = "Context source review error: \(error)"
            }
        }
    }

    func updateContextObjective(_ objective: String) {
        guard var draft = contextDraft else { return }
        draft.content.objective = objective
        contextDraft = draft
    }

    func updateContextClaim(section: ContextClaimSection, index: Int, text: String) {
        guard var draft = contextDraft else { return }
        switch section {
        case .scopeIn:
            guard draft.content.scopeIn.indices.contains(index) else { return }
            draft.content.scopeIn[index].text = text
        case .scopeOut:
            guard draft.content.scopeOut.indices.contains(index) else { return }
            draft.content.scopeOut[index].text = text
        case .confirmedFacts:
            guard draft.content.confirmedFacts.indices.contains(index) else { return }
            draft.content.confirmedFacts[index].text = text
        case .constraints:
            guard draft.content.constraints.indices.contains(index) else { return }
            draft.content.constraints[index].text = text
        case .acceptanceCriteria:
            guard draft.content.acceptanceCriteria.indices.contains(index) else { return }
            draft.content.acceptanceCriteria[index].text = text
        case .assumptions:
            guard draft.content.assumptions.indices.contains(index) else { return }
            draft.content.assumptions[index].text = text
        }
        contextDraft = draft
    }

    private var contextOutputLanguage: String {
        appLanguage.usesChinese ? "Simplified Chinese" : "English"
    }

    private func loadedContextAPIKey() -> String? {
        guard let key = try? keychainCredentialStore.loadKey(for: contextModelProvider),
            !key.isEmpty
        else {
            return nil
        }
        return key
    }

    nonisolated private static func makeContextPreparationInput(
        task: TaskRecord,
        taskID: String,
        store: ProjectionStore
    ) throws -> ContextPreparationInput {
        let repository = try store.repository(taskID: taskID)
        return try ContextMaterialExtractor.prepare(
            task: task,
            baseRevision: store.latestProjectionRevision(taskID: taskID),
            supplement: try store.supplement(taskID: taskID),
            notes: try store.listNotes(taskID: taskID),
            files: try store.listFiles(taskID: taskID),
            repository: repository,
            gitActivity: repository == nil
                ? nil
                : try store.gitActivity(
                    taskID: taskID,
                    includeCommittedDiff: true,
                    includeUncommittedDiff: true
                )
        )
    }

    nonisolated private static func defaultSelectedContextSourceIDs(
        _ input: ContextPreparationInput
    ) -> Set<String> {
        Set(
            input.sources
                .filter { $0.reference.kind != ContextMaterialExtractor.uncommittedGitActivityKind }
                .map(\.id)
        )
    }
}
