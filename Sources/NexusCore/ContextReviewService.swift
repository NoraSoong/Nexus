import Foundation

public enum ContextContentSection: String, CaseIterable, Equatable, Sendable {
    case objective
    case scopeIn = "scope_in"
    case scopeOut = "scope_out"
    case confirmedFacts = "confirmed_facts"
    case constraints
    case acceptanceCriteria = "acceptance_criteria"
    case assumptions
    case questions
}

public enum ContextChangeKind: String, Equatable, Sendable {
    case added
    case removed
    case modified
}

public struct ContextClaimChange: Equatable, Identifiable, Sendable {
    public let id: String
    public let section: ContextContentSection
    public let kind: ContextChangeKind
    public let beforeText: String?
    public let afterText: String?
    public let sourceIDs: [String]

    public init(
        id: String,
        section: ContextContentSection,
        kind: ContextChangeKind,
        beforeText: String?,
        afterText: String?,
        sourceIDs: [String]
    ) {
        self.id = id
        self.section = section
        self.kind = kind
        self.beforeText = beforeText
        self.afterText = afterText
        self.sourceIDs = sourceIDs
    }
}

public enum ContextSourceChangeKind: String, Equatable, Sendable {
    case added
    case removed
    case changed
}

public struct ContextSourceDelta: Equatable, Identifiable, Sendable {
    public var id: String { current?.id ?? previous?.id ?? "" }
    public let kind: ContextSourceChangeKind
    public let previous: ContextSourceRef?
    public let current: ContextSourceRef?

    public init(
        kind: ContextSourceChangeKind,
        previous: ContextSourceRef?,
        current: ContextSourceRef?
    ) {
        self.kind = kind
        self.previous = previous
        self.current = current
    }
}

public struct ContextPackDiff: Equatable, Sendable {
    public let isInitial: Bool
    public let changes: [ContextClaimChange]
    public let sourceChanges: [ContextSourceDelta]

    public init(
        isInitial: Bool,
        changes: [ContextClaimChange],
        sourceChanges: [ContextSourceDelta]
    ) {
        self.isInitial = isInitial
        self.changes = changes
        self.sourceChanges = sourceChanges
    }

    public var addedCount: Int {
        changes.filter { $0.kind == .added }.count
    }

    public var modifiedCount: Int {
        changes.filter { $0.kind == .modified }.count
    }

    public var removedCount: Int {
        changes.filter { $0.kind == .removed }.count
    }

    public var hasChanges: Bool {
        !changes.isEmpty || !sourceChanges.isEmpty
    }
}

public enum ContextReviewFindingKind: String, Equatable, Sendable {
    case unresolvedQuestions = "unresolved_questions"
    case assumptions
    case truncatedSources = "truncated_sources"
    case changedSources = "changed_sources"
    case removedSources = "removed_sources"
}

public struct ContextReviewFinding: Equatable, Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: ContextReviewFindingKind
    public let count: Int
    public let sourceIDs: [String]

    public init(kind: ContextReviewFindingKind, count: Int, sourceIDs: [String] = []) {
        self.kind = kind
        self.count = count
        self.sourceIDs = sourceIDs
    }
}

public enum ContextReviewService {
    public static func compare(
        candidate: ContextPackContent,
        candidateSources: [ContextSourceRef],
        baseline: ContextPack?
    ) -> ContextPackDiff {
        guard let baseline else {
            return ContextPackDiff(
                isInitial: true,
                changes: [],
                sourceChanges: sourceChanges(baseline: [], candidate: candidateSources)
            )
        }

        var changes: [ContextClaimChange] = []
        appendTextChange(
            section: .objective,
            previous: baseline.content.objective,
            current: candidate.objective,
            to: &changes
        )
        appendClaimChanges(
            section: .scopeIn,
            previous: baseline.content.scopeIn,
            current: candidate.scopeIn,
            to: &changes
        )
        appendClaimChanges(
            section: .scopeOut,
            previous: baseline.content.scopeOut,
            current: candidate.scopeOut,
            to: &changes
        )
        appendClaimChanges(
            section: .confirmedFacts,
            previous: baseline.content.confirmedFacts,
            current: candidate.confirmedFacts,
            to: &changes
        )
        appendClaimChanges(
            section: .constraints,
            previous: baseline.content.constraints,
            current: candidate.constraints,
            to: &changes
        )
        appendClaimChanges(
            section: .acceptanceCriteria,
            previous: baseline.content.acceptanceCriteria,
            current: candidate.acceptanceCriteria,
            to: &changes
        )
        appendClaimChanges(
            section: .assumptions,
            previous: baseline.content.assumptions,
            current: candidate.assumptions,
            to: &changes
        )
        appendQuestionChanges(
            previous: baseline.content.questions,
            current: candidate.questions,
            to: &changes
        )

        return ContextPackDiff(
            isInitial: false,
            changes: changes,
            sourceChanges: sourceChanges(
                baseline: baseline.sourceManifest,
                candidate: candidateSources
            )
        )
    }

    public static func sourceChanges(
        baseline: [ContextSourceRef],
        candidate: [ContextSourceRef]
    ) -> [ContextSourceDelta] {
        let previousByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: candidate.map { ($0.id, $0) })
        let ids = Set(previousByID.keys).union(currentByID.keys).sorted()

        return ids.compactMap { id in
            switch (previousByID[id], currentByID[id]) {
            case (nil, let current?):
                return ContextSourceDelta(kind: .added, previous: nil, current: current)
            case (let previous?, nil):
                return ContextSourceDelta(kind: .removed, previous: previous, current: nil)
            case (let previous?, let current?)
            where ContextSourceFreshnessPolicy.hasChanged(baseline: previous, current: current):
                return ContextSourceDelta(kind: .changed, previous: previous, current: current)
            default:
                return nil
            }
        }
    }

    public static func findings(
        content: ContextPackContent,
        sources: [ContextSourceRef],
        sourceChanges: [ContextSourceDelta]
    ) -> [ContextReviewFinding] {
        var findings: [ContextReviewFinding] = []
        if !content.questions.isEmpty {
            findings.append(
                ContextReviewFinding(
                    kind: .unresolvedQuestions,
                    count: content.questions.count,
                    sourceIDs: sortedUnique(content.questions.flatMap(\.sourceIDs))
                )
            )
        }
        if !content.assumptions.isEmpty {
            findings.append(
                ContextReviewFinding(
                    kind: .assumptions,
                    count: content.assumptions.count,
                    sourceIDs: sortedUnique(content.assumptions.flatMap(\.sourceIDs))
                )
            )
        }

        let citedSourceIDs = Set(allClaims(in: content).flatMap(\.sourceIDs))
            .union(content.questions.flatMap(\.sourceIDs))
        let truncated = sources.filter { $0.truncated && citedSourceIDs.contains($0.id) }
        if !truncated.isEmpty {
            findings.append(
                ContextReviewFinding(
                    kind: .truncatedSources,
                    count: truncated.count,
                    sourceIDs: truncated.map(\.id).sorted()
                )
            )
        }

        let changed = sourceChanges.filter { $0.kind == .changed }
        if !changed.isEmpty {
            findings.append(
                ContextReviewFinding(
                    kind: .changedSources,
                    count: changed.count,
                    sourceIDs: changed.map(\.id).sorted()
                )
            )
        }
        let removed = sourceChanges.filter { $0.kind == .removed }
        if !removed.isEmpty {
            findings.append(
                ContextReviewFinding(
                    kind: .removedSources,
                    count: removed.count,
                    sourceIDs: removed.map(\.id).sorted()
                )
            )
        }
        return findings
    }

    private static func appendTextChange(
        section: ContextContentSection,
        previous: String,
        current: String,
        to changes: inout [ContextClaimChange]
    ) {
        let normalizedPrevious = normalized(previous)
        let normalizedCurrent = normalized(current)
        guard normalizedPrevious != normalizedCurrent else { return }
        let kind: ContextChangeKind
        if normalizedPrevious.isEmpty {
            kind = .added
        } else if normalizedCurrent.isEmpty {
            kind = .removed
        } else {
            kind = .modified
        }
        changes.append(
            ContextClaimChange(
                id: changeID(section: section, kind: kind, index: changes.count),
                section: section,
                kind: kind,
                beforeText: normalizedPrevious.isEmpty ? nil : previous,
                afterText: normalizedCurrent.isEmpty ? nil : current,
                sourceIDs: []
            )
        )
    }

    private static func appendClaimChanges(
        section: ContextContentSection,
        previous: [ContextClaim],
        current: [ContextClaim],
        to changes: inout [ContextClaimChange]
    ) {
        var previousRemaining = Set(previous.indices)
        var currentRemaining = Set(current.indices)

        for oldIndex in previous.indices {
            guard
                let newIndex = current.indices.first(where: {
                    currentRemaining.contains($0) && claimKey(previous[oldIndex]) == claimKey(current[$0])
                })
            else {
                continue
            }
            previousRemaining.remove(oldIndex)
            currentRemaining.remove(newIndex)
        }

        let previousBySource = Dictionary(grouping: previousRemaining) {
            sourceKey(previous[$0].sourceIDs)
        }
        let currentBySource = Dictionary(grouping: currentRemaining) {
            sourceKey(current[$0].sourceIDs)
        }

        for key in Set(previousBySource.keys).intersection(currentBySource.keys).sorted()
        where !key.isEmpty {
            guard let oldIndexes = previousBySource[key],
                let newIndexes = currentBySource[key],
                oldIndexes.count == 1,
                newIndexes.count == 1,
                let oldIndex = oldIndexes.first,
                let newIndex = newIndexes.first
            else {
                continue
            }
            changes.append(
                ContextClaimChange(
                    id: changeID(section: section, kind: .modified, index: changes.count),
                    section: section,
                    kind: .modified,
                    beforeText: previous[oldIndex].text,
                    afterText: current[newIndex].text,
                    sourceIDs: sortedUnique(previous[oldIndex].sourceIDs + current[newIndex].sourceIDs)
                )
            )
            previousRemaining.remove(oldIndex)
            currentRemaining.remove(newIndex)
        }

        for index in previous.indices where previousRemaining.contains(index) {
            changes.append(
                ContextClaimChange(
                    id: changeID(section: section, kind: .removed, index: changes.count),
                    section: section,
                    kind: .removed,
                    beforeText: previous[index].text,
                    afterText: nil,
                    sourceIDs: sortedUnique(previous[index].sourceIDs)
                )
            )
        }
        for index in current.indices where currentRemaining.contains(index) {
            changes.append(
                ContextClaimChange(
                    id: changeID(section: section, kind: .added, index: changes.count),
                    section: section,
                    kind: .added,
                    beforeText: nil,
                    afterText: current[index].text,
                    sourceIDs: sortedUnique(current[index].sourceIDs)
                )
            )
        }
    }

    private static func appendQuestionChanges(
        previous: [ContextQuestion],
        current: [ContextQuestion],
        to changes: inout [ContextClaimChange]
    ) {
        var previousRemaining = Set(previous.indices)
        var currentRemaining = Set(current.indices)

        for oldIndex in previous.indices {
            guard
                let newIndex = current.indices.first(where: {
                    currentRemaining.contains($0) && questionKey(previous[oldIndex]) == questionKey(current[$0])
                })
            else {
                continue
            }
            previousRemaining.remove(oldIndex)
            currentRemaining.remove(newIndex)
        }

        for oldIndex in previous.indices where previousRemaining.contains(oldIndex) {
            guard
                let newIndex = current.indices.first(where: {
                    currentRemaining.contains($0) && previous[oldIndex].id == current[$0].id
                })
            else {
                continue
            }
            let old = previous[oldIndex]
            let new = current[newIndex]
            changes.append(
                ContextClaimChange(
                    id: changeID(section: .questions, kind: .modified, index: changes.count),
                    section: .questions,
                    kind: .modified,
                    beforeText: old.question,
                    afterText: new.question,
                    sourceIDs: sortedUnique(old.sourceIDs + new.sourceIDs)
                )
            )
            previousRemaining.remove(oldIndex)
            currentRemaining.remove(newIndex)
        }

        for index in previous.indices where previousRemaining.contains(index) {
            let question = previous[index]
            changes.append(
                ContextClaimChange(
                    id: changeID(section: .questions, kind: .removed, index: changes.count),
                    section: .questions,
                    kind: .removed,
                    beforeText: question.question,
                    afterText: nil,
                    sourceIDs: sortedUnique(question.sourceIDs)
                )
            )
        }
        for index in current.indices where currentRemaining.contains(index) {
            let question = current[index]
            changes.append(
                ContextClaimChange(
                    id: changeID(section: .questions, kind: .added, index: changes.count),
                    section: .questions,
                    kind: .added,
                    beforeText: nil,
                    afterText: question.question,
                    sourceIDs: sortedUnique(question.sourceIDs)
                )
            )
        }
    }

    private static func allClaims(in content: ContextPackContent) -> [ContextClaim] {
        content.scopeIn
            + content.scopeOut
            + content.confirmedFacts
            + content.constraints
            + content.acceptanceCriteria
            + content.assumptions
    }

    private static func claimKey(_ claim: ContextClaim) -> String {
        "\(normalized(claim.text))|\(sourceKey(claim.sourceIDs))"
    }

    private static func questionKey(_ question: ContextQuestion) -> String {
        [
            normalized(question.question),
            normalized(question.whyItMatters),
            sourceKey(question.sourceIDs),
        ].joined(separator: "|")
    }

    private static func sourceKey(_ sourceIDs: [String]) -> String {
        sortedUnique(sourceIDs).joined(separator: "\u{1f}")
    }

    private static func normalized(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private static func changeID(
        section: ContextContentSection,
        kind: ContextChangeKind,
        index: Int
    ) -> String {
        "\(section.rawValue):\(kind.rawValue):\(index)"
    }
}
