import AppKit
import NexusCore
import SwiftUI

@main
struct NexusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Nexus", systemImage: model.menuBarSystemImage) {
            MenuContentView(model: model)
                .onAppear {
                    model.writeRuntimeHeartbeat()
                }
                .task { model.bootstrap() }
        }

        Window("Nexus", id: "main") {
            NexusMainView(model: model)
                .background(WindowActivator())
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refresh()
                }
                .onAppear {
                    model.writeRuntimeHeartbeat()
                }
                .task { model.bootstrap() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(model.l10n.switchWork) {
                    model.openQuickSwitcher()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtimeHeartbeatTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installApplicationIcon()
        publishRuntimeHeartbeatFromDefaults()
        runtimeHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            publishRuntimeHeartbeatFromDefaults()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtimeHeartbeatTimer?.invalidate()
        runtimeHeartbeatTimer = nil
        try? NexusRuntime.markAppStopped()
    }

    private func installApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "Nexus", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        NSApp.applicationIconImage = icon
    }
}
