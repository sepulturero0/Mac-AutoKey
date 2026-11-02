#if DEBUG
import AppKit
import ScreenCaptureKit

/// Opt-in development evidence from this app's own view hierarchy. No other
/// application's windows or user data are read. Not included in release builds.
@MainActor
enum DebugDiagnostics {
    private static var started = false
    static func captureIfRequested(model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard !started, let option = args.firstIndex(of: "--diagnostics"), args.indices.contains(option + 1) else { return }
        started = true
        let base = URL(fileURLWithPath: args[option + 1])
        NSApp.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
        if args.contains("--preview-running") || args.contains("--preview-paused") {
            model.showStatusPreview(paused: args.contains("--preview-paused"))
        }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard let mainWindow = NSApp.windows.first(where: { $0.title == "Mac AutoKey" }) else { return }
            let window = args.contains("--settings-panel") ? (NSApp.windows.first { $0.title == "Settings" } ?? mainWindow) : mainWindow
            if window === mainWindow {
                let size: NSSize = if args.contains("--minimum-window") {
                    NSSize(width: 860, height: 650)
                } else if args.contains("--wide-window") {
                    NSSize(width: 1920, height: 1080)
                } else {
                    NSSize(width: 940, height: 760)
                }
                window.setContentSize(size)
                if args.contains("--fullscreen-preview") {
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    window.toggleFullScreen(nil)
                    try? await Task.sleep(for: .milliseconds(1600))
                }
            }
            // Allow SwiftUI to lay out after resizing before capturing evidence.
            try? await Task.sleep(for: .milliseconds(350))
            var captureError: String?
            do {
                if #available(macOS 14.4, *) {
                    // This API returns only content already capturable by this process
                    // without a TCC grant. Additionally restrict to our exact window.
                    let content = try await SCShareableContent.currentProcess
                    guard let ownWindow = content.windows.first(where: {
                        $0.windowID == CGWindowID(window.windowNumber) &&
                        $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                    }) else { throw AutoKeyError.message("Own preview window unavailable.") }
                    let filter = SCContentFilter(desktopIndependentWindow: ownWindow)
                    let config = SCStreamConfiguration()
                    config.width = Int(ownWindow.frame.width * 2)
                    config.height = Int(ownWindow.frame.height * 2)
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let bitmap = NSBitmapImageRep(cgImage: cgImage)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try data.write(to: base.appendingPathExtension("png"))
                    }
                } else {
                    throw AutoKeyError.message("Debug window capture needs macOS 14.4 or newer.")
                }
            } catch { captureError = error.localizedDescription }
            var report: [String: Any] = [
                "accessibilityTrusted": model.permissions.trusted,
                "eventPostAllowed": model.permissions.canPost,
                "automationActive": model.isActive,
                "hotkeysDisabledForPreview": true,
                "configurationValid": model.configurationError == nil,
                "windowWidth": window.frame.width, "windowHeight": window.frame.height,
                "nativeFullscreen": window.styleMask.contains(.fullScreen),
                "sampleSteps": model.config.actions.count,
                "commandCount": model.config.commands.count,
                "isolatedPreviewSettings": true,
                "automationState": model.automationState.statusTitle
            ]
            if let captureError { report["captureError"] = captureError }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: base.appendingPathExtension("json"))
            }
            if args.contains("--exit-after-diagnostics") {
                if let sheet = mainWindow.attachedSheet { mainWindow.endSheet(sheet) }
                if mainWindow.styleMask.contains(.fullScreen) {
                    mainWindow.toggleFullScreen(nil)
                    try? await Task.sleep(for: .milliseconds(1200))
                }
                NSApp.terminate(nil)
            }
        }
    }
}
#endif
