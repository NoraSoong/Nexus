import AppKit
import NexusCore
import SwiftUI

struct ContextPreparationView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var l10n: L10n { model.l10n }

    var body: some View {
        VStack(spacing: 0) {
            switch model.contextPreparationPhase {
            case .loadingSources:
                loadingSources
            case .preflight:
                preflight
            case .preparing:
                preparing
            case .review:
                review
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            if model.contextPreparationPhase == .loadingSources
                || model.contextPreparationPhase == .preparing
            {
                model.cancelContextPreparationRequest()
            }
        }
        .sheet(isPresented: $model.showContextModelSettings) {
            ContextModelSettingsView(model: model)
                .frame(width: 480, height: 380)
        }
    }

    private var loadingSources: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(l10n.loadingContextMaterials)
                .font(.headline)
            Spacer()
        }
    }

    private var preflight: some View {
        VStack(spacing: 0) {
            sheetHeader(title: l10n.contextPreparationTitle, description: l10n.contextPreparationDescription)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                modelConnectionSummary
                errorMessage
                sourceSelectionHeader
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sourceSelection
                    if let input = model.contextPreparationInput, !input.excludedSources.isEmpty {
                        excludedSources(input.excludedSources)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
            .id(preflightScrollIdentity)
            Divider()
            HStack {
                Button(l10n.cancel) { dismiss() }
                Spacer()
                Button(l10n.startPreparation) {
                    model.generateContextDraft()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasContextAPIKey || model.selectedContextSourceIDs.isEmpty)
            }
            .padding(18)
        }
    }

    private var preparing: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text(l10n.preparingContext)
                    .font(.title2.weight(.semibold))
                Text(l10n.preparingContextHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(l10n.cancelPreparation) {
                model.cancelContextPreparationRequest()
            }
            Spacer()
        }
        .padding(28)
    }

    private var review: some View {
        VStack(spacing: 0) {
            sheetHeader(
                title: l10n.contextReview,
                description: ""
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let draft = model.contextDraft {
                        briefEditor
                        clarificationQuestions(draft.content.questions)
                        reviewFindings
                        reviewComparison
                        contextDetails(draft.content)
                    }
                    errorMessage
                }
                .padding(22)
            }
            Divider()
            HStack {
                Button(l10n.discardContextDraft, role: .destructive) {
                    model.discardPreparedContext()
                    dismiss()
                }
                Spacer()
                if model.canPrepareWithDeepSeekPro {
                    Menu {
                        Button {
                            model.generateContextDraftWithDeepSeekPro()
                        } label: {
                            Label(l10n.prepareWithDeepSeekPro, systemImage: "sparkles")
                        }
                    } label: {
                        Text(l10n.regenerateContext)
                    } primaryAction: {
                        model.generateContextDraft()
                    }
                } else {
                    Button(l10n.regenerateContext) {
                        model.generateContextDraft()
                    }
                }
                Button(hasEditedDraft ? l10n.applyEditedContextPack : l10n.applyContextPack) {
                    model.approvePreparedContext()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.contextDraftBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || hasQuestionAnswers
                )
                .help(hasQuestionAnswers ? l10n.regenerateAnsweredQuestionsHint : "")
            }
            .padding(18)
        }
    }

    private func sheetHeader(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
            if !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }

    private var modelConnectionSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: model.hasContextAPIKey ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(model.hasContextAPIKey ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    model.hasContextAPIKey
                        ? l10n.contextModelConnection(model.contextModelConfiguration)
                        : l10n.contextModelNotConnected
                )
                .font(.callout.weight(.semibold))
                Text(l10n.contextModelDataNotice(model.contextModelProvider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(model.hasContextAPIKey ? l10n.manageContextModel : l10n.connectContextModel) {
                model.showContextModelSettings = true
            }
            .buttonStyle(.bordered)
        }
        .padding(13)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var sourceSelectionHeader: some View {
        if let input = model.contextPreparationInput {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(l10n.preparationSources)
                    .font(.headline)
                Spacer()
                Text(
                    l10n.preparationSelectionSummary(
                        count: selectedSourceCount(input),
                        characterCount: selectedCharacterCount(input),
                        characterBudget: ContextMaterialExtractor.totalCharacterLimit,
                        truncatedCount: selectedTruncatedSourceCount(input)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    private var sourceSelection: some View {
        Group {
            if let input = model.contextPreparationInput {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(input.sources) { source in
                        sourceSelectionRow(source)
                        if source.id != input.sources.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sourceSelectionRow(_ source: ContextSourceDocument) -> some View {
        if source.reference.kind == "work" {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 16)
                sourceLabel(source)
                Spacer(minLength: 12)
                Text(l10n.alwaysIncluded)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        } else {
            Toggle(isOn: sourceSelectionBinding(source.id)) {
                sourceLabel(source)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }

    private func sourceLabel(_ source: ContextSourceDocument) -> some View {
        HStack(spacing: 10) {
            Image(systemName: sourceIcon(source.reference.kind))
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(sourceDisplayTitle(source.reference))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(l10n.preparationCharacterCount(source.reference.includedCharacterCount))
                    if source.reference.truncated {
                        Text(l10n.truncatedSource)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func excludedSources(_ sources: [ContextSourceExclusion]) -> some View {
        DisclosureGroup(l10n.excludedSources) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(source.title)
                            .lineLimit(1)
                        Spacer()
                        Text(l10n.contextSourceExclusion(source.reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 34)
                    .help(source.path ?? source.title)
                }
            }
            .padding(.top, 6)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var briefEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.preparedBrief)
                .font(.headline)
            TextEditor(text: $model.contextDraftBrief)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.16)))
                .frame(minHeight: 190)
        }
    }

    @ViewBuilder
    private var reviewComparison: some View {
        if let diff = model.preparedContextDiff,
            !diff.isInitial,
            diff.hasChanges
        {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(diff.changes) { change in
                        contextChangeRow(change)
                    }
                    ForEach(diff.sourceChanges) { change in
                        sourceChangeRow(change)
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Label(l10n.reviewContextChanges, systemImage: "arrow.left.arrow.right")
                    Spacer()
                    Text(
                        l10n.contextChangeSummary(
                            added: diff.addedCount,
                            modified: diff.modifiedCount,
                            removed: diff.removedCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .font(.callout.weight(.medium))
            .padding(13)
            .background(Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var reviewFindings: some View {
        let findings = model.preparedContextFindings
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Label(l10n.contextReviewFindingsTitle, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Color.orange.opacity(0.85))
                            .frame(width: 12, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.contextReviewFinding(finding))
                                .font(.callout)
                            if !finding.sourceIDs.isEmpty {
                                Text(finding.sourceIDs.map(model.sourceTitle).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func contextChangeRow(_ change: ContextClaimChange) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: changeIcon(change.kind))
                .font(.caption)
                .foregroundStyle(changeColor(change.kind))
                .frame(width: 14, height: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(l10n.contextSectionName(change.section))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(l10n.contextChangeKind(change.kind))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(changeColor(change.kind))
                }
                if let before = change.beforeText, change.kind != .added {
                    Text(before)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough(change.kind != .modified ? true : false)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let after = change.afterText, change.kind != .removed {
                    Text(after)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !change.sourceIDs.isEmpty {
                    Text(change.sourceIDs.map(model.sourceTitle).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func sourceChangeRow(_ change: ContextSourceDelta) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(change.kind == .changed ? Color.orange : Color.secondary)
                .frame(width: 14)
            Text(change.current?.title ?? change.previous?.title ?? change.id)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Text(l10n.contextSourceChangeKind(change.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func changeIcon(_ kind: ContextChangeKind) -> String {
        switch kind {
        case .added: return "plus"
        case .removed: return "minus"
        case .modified: return "arrow.right"
        }
    }

    private func changeColor(_ kind: ContextChangeKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }

    @ViewBuilder
    private func clarificationQuestions(_ questions: [ContextQuestion]) -> some View {
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(l10n.clarificationQuestions)
                    .font(.headline)
                ForEach(questions.prefix(5)) { question in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(question.question)
                            .font(.callout.weight(.semibold))
                        if !question.whyItMatters.isEmpty {
                            Text("\(l10n.whyItMatters): \(question.whyItMatters)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !question.sourceIDs.isEmpty {
                            Text(
                                "\(l10n.citedSources): \(question.sourceIDs.map(model.sourceTitle).joined(separator: ", "))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        TextField(
                            l10n.questionAnswerPlaceholder,
                            text: Binding(
                                get: { model.contextQuestionAnswers[question.id] ?? "" },
                                set: { model.contextQuestionAnswers[question.id] = $0 }
                            ),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func contextDetails(_ content: ContextPackContent) -> some View {
        DisclosureGroup(l10n.contextDetails) {
            VStack(alignment: .leading, spacing: 14) {
                Text(l10n.editPreparedDetailsHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.contextObjective)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        l10n.contextObjective,
                        text: Binding(
                            get: { model.contextDraft?.content.objective ?? "" },
                            set: { model.updateContextObjective($0) }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                }
                claimSection(l10n.contextScopeIn, content.scopeIn, section: .scopeIn)
                claimSection(l10n.contextScopeOut, content.scopeOut, section: .scopeOut)
                claimSection(l10n.contextConfirmedFacts, content.confirmedFacts, section: .confirmedFacts)
                claimSection(l10n.contextConstraints, content.constraints, section: .constraints)
                claimSection(l10n.contextAcceptanceCriteria, content.acceptanceCriteria, section: .acceptanceCriteria)
                claimSection(l10n.contextAssumptions, content.assumptions, section: .assumptions)
            }
            .padding(.top, 10)
        }
        .font(.callout.weight(.medium))
    }

    @ViewBuilder
    private func claimSection(_ title: String, _ claims: [ContextClaim], section: ContextClaimSection) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(claims.enumerated()), id: \.offset) { index, claim in
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(
                            title,
                            text: Binding(
                                get: { claims[index].text },
                                set: { model.updateContextClaim(section: section, index: index, text: $0) }
                            ),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        if !claim.sourceIDs.isEmpty {
                            Text(
                                "\(l10n.citedSources): \(claim.sourceIDs.map(model.sourceTitle).joined(separator: ", "))"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if !model.contextPreparationError.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.contextPreparationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if model.canPrepareWithDeepSeekPro {
                    HStack(spacing: 8) {
                        Button(l10n.retryWithDeepSeekPro) {
                            model.generateContextDraftWithDeepSeekPro()
                        }
                        .buttonStyle(.bordered)
                        Text(l10n.deepSeekProOneTimeHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func sourceSelectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedContextSourceIDs.contains(id) },
            set: { selected in
                if selected {
                    model.selectedContextSourceIDs.insert(id)
                } else {
                    model.selectedContextSourceIDs.remove(id)
                }
            }
        )
    }

    private func selectedCharacterCount(_ input: ContextPreparationInput) -> Int {
        input.sources
            .filter { model.selectedContextSourceIDs.contains($0.id) }
            .reduce(0) { $0 + $1.reference.includedCharacterCount }
    }

    private func selectedSourceCount(_ input: ContextPreparationInput) -> Int {
        input.sources.filter { model.selectedContextSourceIDs.contains($0.id) }.count
    }

    private func selectedTruncatedSourceCount(_ input: ContextPreparationInput) -> Int {
        input.sources.filter {
            model.selectedContextSourceIDs.contains($0.id) && $0.reference.truncated
        }.count
    }

    private var preflightScrollIdentity: String {
        guard let input = model.contextPreparationInput else { return "preflight-empty" }
        return "preflight-\(input.taskID)-\(input.baseRevision)"
    }

    private var hasEditedDraft: Bool {
        guard let draft = model.contextDraft else { return false }
        let briefChanged =
            model.contextDraftBrief.trimmingCharacters(in: .whitespacesAndNewlines)
            != (model.contextDraftBaseline?.brief ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return briefChanged || draft.content != model.contextDraftBaseline
    }

    private var hasQuestionAnswers: Bool {
        let currentQuestionIDs = Set(model.contextDraft?.content.questions.map(\.id) ?? [])
        return model.contextQuestionAnswers.contains { questionID, answer in
            currentQuestionIDs.contains(questionID)
                && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func sourceIcon(_ kind: String) -> String {
        switch kind {
        case "work": return "scope"
        case "handoff": return "text.alignleft"
        case "repository": return "folder"
        case ContextMaterialExtractor.committedGitActivityKind:
            return "point.bottomleft.forward.to.point.topright.scurvepath"
        case ContextMaterialExtractor.uncommittedGitActivityKind:
            return "pencil.line"
        case "note": return "note.text"
        default: return "doc.text"
        }
    }

    private func sourceDisplayTitle(_ source: ContextSourceRef) -> String {
        switch source.kind {
        case ContextMaterialExtractor.committedGitActivityKind:
            return l10n.committedCodeChanges
        case ContextMaterialExtractor.uncommittedGitActivityKind:
            return l10n.uncommittedCodeChanges
        default:
            return source.title
        }
    }
}
