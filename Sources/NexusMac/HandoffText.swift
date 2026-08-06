import Foundation
import NexusCore

enum HandoffText {
    static func clean(_ body: String) -> String {
        var cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["验收补充：", "验收补充:"] where cleaned.hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    static func merge(supplement: String, nextTime: String) -> String {
        let cleanedSupplement = clean(supplement)
        let cleanedNext = clean(nextTime)
        if cleanedSupplement.isEmpty { return cleanedNext }
        if cleanedNext.isEmpty || cleanedNext == cleanedSupplement { return cleanedSupplement }
        return "\(cleanedSupplement)\n\nNext time: \(cleanedNext)"
    }

    static func deduplicatedHistory(_ checkpoints: [CheckpointRecord]) -> [CheckpointRecord] {
        var seen = Set<String>()
        var result: [CheckpointRecord] = []
        for checkpoint in checkpoints {
            let text = historyText(checkpoint)
            guard !text.isEmpty, !seen.contains(text) else { continue }
            seen.insert(text)
            result.append(checkpoint)
        }
        return result
    }

    private static func historyText(_ checkpoint: CheckpointRecord) -> String {
        if !checkpoint.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return checkpoint.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !checkpoint.currentState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return checkpoint.currentState.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return checkpoint.blockers.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
