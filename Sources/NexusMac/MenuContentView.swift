import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var l10n: L10n { model.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            assistantAccessSection
            Divider()
            activeWorkSection
            Divider()
            quickSwitchButton
            if !model.recentMenuTasks.isEmpty {
                Divider()
                recentWorkSection
            }
            Divider()
            languageMenu
            Button {
                openWindow(id: "main")
                activateNexusWindow()
            } label: {
                Label(l10n.openNexus, systemImage: "macwindow")
            }
            Button {
                model.showNewTaskSheet = true
                openWindow(id: "main")
                activateNexusWindow()
            } label: {
                Label(l10n.newWork, systemImage: "plus.circle")
            }
            Divider()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(l10n.quit, systemImage: "power")
            }
        }
        .padding()
    }

    private var assistantAccessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.toggleAssistantExposure()
            } label: {
                Label(
                    model.assistantExposureEnabled ? l10n.pauseAssistantAccess : l10n.enableAssistantAccess,
                    systemImage: model.assistantExposureEnabled ? "pause.circle.fill" : "play.circle.fill"
                )
            }
            Label(
                model.assistantExposureEnabled ? l10n.nexusContextAvailable : l10n.nexusContextPaused,
                systemImage: model.assistantExposureEnabled ? "checkmark.circle" : "pause.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var activeWorkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.activeWork)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.activeTitle == nil {
                Label(l10n.none, systemImage: "circle.dashed")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    model.openActiveWork()
                    openWindow(id: "main")
                    activateNexusWindow()
                } label: {
                    Label(model.activeTitle ?? model.l10n.none, systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    private var quickSwitchButton: some View {
        Button {
            model.openQuickSwitcher()
            openWindow(id: "main")
            activateNexusWindow()
        } label: {
            Label(l10n.openWork, systemImage: "magnifyingglass")
        }
    }

    private var recentWorkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.activateRecentWork)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.recentMenuTasks) { task in
                Button {
                    model.switchTo(task)
                } label: {
                    Label(task.title, systemImage: "arrow.right.circle")
                }
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    model.setAppLanguage(language)
                } label: {
                    Label(
                        l10n.languageName(language),
                        systemImage: model.appLanguage == language ? "checkmark" : "circle"
                    )
                }
            }
        } label: {
            Label("\(l10n.language): \(l10n.languageName(model.appLanguage))", systemImage: "globe")
        }
    }
}
