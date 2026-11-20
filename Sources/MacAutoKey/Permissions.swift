import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var trusted = false
    @Published private(set) var canPost = false
    @Published private(set) var canCaptureScreen = false
    init() { refresh() }
    func refresh() {
        trusted = AXIsProcessTrusted()
        canPost = CGPreflightPostEventAccess()
        canCaptureScreen = CGPreflightScreenCaptureAccess()
    }
    func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func requireAccess() throws {
        refresh()
        guard trusted && canPost else {
            throw AutoKeyError.message("Allow Mac AutoKey in System Settings → Privacy & Security → Accessibility, then click Check Again. If needed, quit and reopen the app.")
        }
    }
    func requestScreenAccess() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }
    func openScreenSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
}
