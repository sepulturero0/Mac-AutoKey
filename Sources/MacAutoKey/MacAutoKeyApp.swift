import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: AppModel?
    private var statusItem: ClickerStatusItem?
    var openWindow: OpenWindowAction?
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
            } else {
                let statusItem = ClickerStatusItem(model: model) { [weak self] id in
                    self?.openWindow?(id: id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                self.statusItem = statusItem
                LocalVerification.runIfRequested(model: model, statusItem: statusItem)
            }
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
            MainWindowContent(model: model, delegate: delegate)
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
    }
}

private struct MainWindowContent: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MainView(model: model)
            .onAppear {
                delegate.openWindow = openWindow
                #if DEBUG
                DebugDiagnostics.captureIfRequested(model: model)
                #endif
            }
    }
}

private struct SettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") { openWindow(id: "settings") }
            .keyboardShortcut(",", modifiers: .command)
    }
}
