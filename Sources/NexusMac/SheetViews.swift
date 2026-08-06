import AppKit
import NexusCore
import SwiftUI

struct NewTaskView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var l10n: L10n { model.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.newWork)
                .font(.title2.weight(.semibold))
            TextField(l10n.titlePlaceholder, text: $model.newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if model.canCreateNewTask {
                        model.createTask()
                        dismiss()
                    }
                }
            HStack {
                Spacer()
                Button(l10n.cancel) { dismiss() }
                Button(l10n.create) {
                    model.createTask()
                    dismiss()
                }
                .disabled(!model.canCreateNewTask)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }
}

struct QuickSwitchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var highlightedIndex = 0
    @State private var keyMonitor: Any?

    private var results: [TaskRecord] {
        model.quickSwitchResults
    }

    private var l10n: L10n {
        model.l10n
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.switchWork)
                .font(.title2.weight(.semibold))
            TextField(l10n.searchWork, text: $model.quickSwitchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { openHighlighted() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, task in
                        TaskNavigationRow(
                            task: task,
                            isActive: task.id == model.activeTaskID,
                            isSelected: index == highlightedIndex,
                            isPlaceholder: model.isPlaceholderTask(task),
                            l10n: l10n
                        ) {
                            model.selectTask(task)
                            dismiss()
                        } hoverAction: { hovering in
                            if hovering {
                                highlightedIndex = index
                            }
                        }
                    }
                    if results.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: l10n.noMatchingWork,
                            message: l10n.noMatchingWorkMessage
                        )
                        .padding(.vertical, 20)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text(l10n.quickSwitchKeyboardHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(18)
        .onAppear {
            highlightedIndex = 0
            DispatchQueue.main.async {
                searchFocused = true
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 125:
                    moveHighlight(1)
                    return nil
                case 126:
                    moveHighlight(-1)
                    return nil
                case 36:
                    openHighlighted()
                    return nil
                case 53:
                    dismiss()
                    return nil
                default:
                    return event
                }
            }
        }
        .onChange(of: model.quickSwitchQuery) { _, _ in
            highlightedIndex = 0
        }
        .onMoveCommand { direction in
            guard !results.isEmpty else { return }
            switch direction {
            case .down:
                moveHighlight(1)
            case .up:
                moveHighlight(-1)
            default:
                break
            }
        }
        .onExitCommand {
            dismiss()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }

    private func openHighlighted() {
        guard results.indices.contains(highlightedIndex) else { return }
        model.selectTask(results[highlightedIndex])
        dismiss()
    }

    private func moveHighlight(_ delta: Int) {
        guard !results.isEmpty else { return }
        highlightedIndex = min(max(highlightedIndex + delta, 0), results.count - 1)
    }
}

struct AddTextMaterialView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var bodyFocused: Bool
    private var l10n: L10n { model.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.addTextMaterial)
                .font(.title2.weight(.semibold))
            Text(l10n.addTextMaterialDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(l10n.materialTitleOptional, text: $model.newTextMaterialTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $model.newTextMaterialBody)
                .font(.body)
                .focused($bodyFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .frame(minHeight: 220)
            Toggle(l10n.visibleToAssistant, isOn: $model.newTextMaterialVisible)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(l10n.cancel) { dismiss() }
                Button(l10n.add) {
                    model.addTextMaterial()
                    dismiss()
                }
                .disabled(!model.canAddTextMaterial)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .onAppear {
            DispatchQueue.main.async {
                bodyFocused = true
            }
        }
    }
}

struct ArchivedTasksView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var l10n: L10n { model.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l10n.archivedTasks)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(l10n.done) { dismiss() }
            }
            if model.archivedTasks.isEmpty {
                Text(l10n.noArchivedWork)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(model.archivedTasks) { task in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(task.title)
                            if !task.goal.isEmpty {
                                Text(task.goal)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button(l10n.restore) {
                            model.restoreTask(task)
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding(18)
    }
}
