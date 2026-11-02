import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let model = Self.model {
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--permission-report"), args.indices.contains(index + 1) {
                model.permissions.refresh()
                let report: [String: Any] = [
                    "appPath": Bundle.main.bundlePath,
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    "accessibilityTrusted": model.permissions.trusted, "eventPostAllowed": model.permissions.canPost,
                    "clickerShortcut": model.config.clickShortcut.label,
                    "commandCount": model.config.commands.count, "citrixOnly": model.config.citrixOnly
                ]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic)
                }
                NSApp.terminate(nil)
            } else { LocalVerification.runIfRequested(model: model) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { Self.model?.shutdown() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.model?.shutdown()
        return .terminateNow
    }
}

@main
@MainActor
struct MacAutoKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel
    init() {
        let verification = ProcessInfo.processInfo.arguments.contains("--verify-local-input")
        let store: ConfigurationStore
        if verification {
            // Test runs never overwrite the user's saved settings.
            store = ConfigurationStore(defaults: UserDefaults(suiteName: "MacAutoKey.LocalVerification")!)
        } else {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
                let defaults = UserDefaults(suiteName: "MacAutoKey.UIPreview")!
                defaults.removePersistentDomain(forName: "MacAutoKey.UIPreview")
                var preview = Configuration()
                if ProcessInfo.processInfo.arguments.contains("--fixed-position-preview") {
                    preview.fixedClickEnabled = true
                    preview.fixedClickX = 640
                    preview.fixedClickY = 480
                }
                preview.commands = ProcessInfo.processInfo.arguments.contains("--preview-empty") ? [] : [
                    KeyboardCommand(name: "Enter amounts", actions: [
                        .init(kind: .text, text: "25"), .init(kind: .delay, delayMS: 500), .init(kind: .key),
                        .init(kind: .text, text: "10"), .init(kind: .key)
                    ]),
                    KeyboardCommand(name: "Next field", shortcut: .init(keyCode: 101, option: true, control: true), actions: [.init(kind: .key, keyCode: 48)]),
                    KeyboardCommand(name: "Quick note", shortcut: .init(keyCode: 109, option: true, control: true), actions: [.init(kind: .text, text: "Sample text")])
                ]
                store = ConfigurationStore(defaults: defaults)
                try? store.save(preview)
            } else { store = ConfigurationStore() }
            #else
            store = ConfigurationStore()
            #endif
        }
        let reporting = ProcessInfo.processInfo.arguments.contains("--permission-report")
        #if DEBUG
        let model = AppModel(store: store, registerGlobalHotkeys: !reporting && !ProcessInfo.processInfo.arguments.contains("--diagnostics"))
        #else
        let model = AppModel(store: store, registerGlobalHotkeys: !reporting)
        #endif
        _model = StateObject(wrappedValue: model)
        AppDelegate.model = model
    }
    var body: some Scene {
        Window("Mac AutoKey", id: "main") {
            MainView(model: model)
                .onAppear {
                    LocalVerification.runIfRequested(model: model)
                    #if DEBUG
                    DebugDiagnostics.captureIfRequested(model: model)
                    #endif
                }
        }
        .defaultSize(width: 940, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) { SettingsMenuItem() }
            CommandGroup(after: .appInfo) {
                Button("Stop All Automation") { model.stopAll() }
            }
        }
        Window("Settings", id: "settings") {
            AppSettingsView(model: model)
        }.windowResizability(.contentSize)
        MenuBarExtra {
            MenuContents(model: model)
        } label: {
            StatusItemLabel(model: model)
        }
    }
}

private struct StatusItemLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var didPresentWindow = false
    var body: some View {
        Label {
            Text("Mac AutoKey · \(model.automationState.statusTitle)")
        } icon: {
            Image(systemName: model.isPaused ? "pause.circle.fill" : (model.isActive ? "play.circle.fill" : "stop.circle.fill"))
                .renderingMode(.original).foregroundStyle(model.automationState.statusColor)
        }
            .onAppear {
                guard !didPresentWindow else { return }
                didPresentWindow = true
                openWindow(id: "main")
                // The status item is created even if macOS restored a closed window.
                LocalVerification.runIfRequested(model: model)
            }
    }
}

private struct MenuContents: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Mac AutoKey") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Text("\(model.automationState.statusTitle) · \(model.summary)")
        Button(model.isPaused ? "Resume" : "Pause") {
            if model.isPaused { model.resumeActive() } else { model.pauseActive() }
        }.disabled(model.resumePending || (!model.isPaused && !model.canPause))
        Divider()
        Button("Stop All    ⌘⇧Escape") { model.stopAll() }
        Divider()
        Button("Quit Mac AutoKey") { model.shutdown(); NSApp.terminate(nil) }
    }
}

private struct SettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") { openWindow(id: "settings") }
            .keyboardShortcut(",", modifiers: .command)
    }
}
