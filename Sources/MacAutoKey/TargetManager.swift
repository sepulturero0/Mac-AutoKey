import AppKit

@MainActor
final class TargetManager: NSObject, ObservableObject {
    @Published private(set) var foreground: TargetApplication?
    @Published private(set) var recentExternal: TargetApplication?
    var onFocusChanged: (() -> Void)?
    private var sessionActive = true
    private var displaysAwake = true
    private var systemAwake = true
    var sessionAvailable: Bool { sessionActive && displaysAwake && systemAwake }
    override init() {
        super.init()
        update()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed),
            name: NSWorkspace.willSleepNotification, object: nil)
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
    }
    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }
    @objc private func changed(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.sessionDidResignActiveNotification: sessionActive = false
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionActive = true
        case NSWorkspace.screensDidSleepNotification: displaysAwake = false
        case NSWorkspace.screensDidWakeNotification: displaysAwake = true
        case NSWorkspace.willSleepNotification: systemAwake = false
        case NSWorkspace.didWakeNotification: systemAwake = true
        default: break
        }
        update()
        onFocusChanged?()
    }
    private func update() {
        foreground = Self.metadata(NSWorkspace.shared.frontmostApplication)
        if let foreground, NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            recentExternal = foreground
        }
    }
    static func metadata(_ app: NSRunningApplication?) -> TargetApplication? {
        guard let app, let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
        return TargetApplication(bundleID: id, name: app.localizedName ?? id,
                                 path: url.resolvingSymlinksInPath().standardizedFileURL.path)
    }
    func currentPID(config: Configuration) throws -> pid_t {
        guard sessionAvailable,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let metadata = Self.metadata(app) else {
            throw AutoKeyError.message("Focus the application you want to automate. Manual runs give you 3 seconds to switch to it.")
        }
        if config.citrixOnly && !config.allowedTargets.contains(where: { $0.id == metadata.id }) {
            throw AutoKeyError.message("Citrix Only blocked ‘\(metadata.name)’. Focus the intended Citrix viewer, switch back, and add the recent application to Allowed Targets.")
        }
        return app.processIdentifier
    }
    func requireFocus(pid: pid_t, config: Configuration) throws {
        guard try currentPID(config: config) == pid else {
            throw AutoKeyError.message("Stopped because the target application lost focus.")
        }
    }
}
