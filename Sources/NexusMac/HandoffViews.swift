import AppKit
import NexusCore
import SwiftUI

struct HandoffHistoryView: View {
    let entries: [CheckpointRecord]
    let l10n: L10n
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries.prefix(5)) { entry in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ReadableFileType.shortDate(entry.createdAt))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(handoffText(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text(l10n.recentHandoffs)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func handoffText(_ checkpoint: CheckpointRecord) -> String {
        if !checkpoint.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return checkpoint.nextStep
        }
        if !checkpoint.currentState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return checkpoint.currentState
        }
        return checkpoint.blockers
    }
}

struct WorkCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NexusPanel {
            content
        }
    }
}
