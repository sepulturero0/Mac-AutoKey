// Optional live test fixture. Never linked into Mac AutoKey.
// Build with Scripts/build-input-receiver.sh; receives normal AppKit input only.
import AppKit

@MainActor
final class InputReceiver: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var window: NSWindow!
    var text: NSTextView!
    var counter: NSButton!
    var clicks = 0
    var timestamps: [Double] = []
    var mouseEvents: [[String: Any]] = []
    var marker: NSImageView?
    var markerTimer: Timer?
    let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/MacAutoKey-input-receiver.json")
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Mac AutoKey — Input Test Receiver"
        window.center()
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        let physical = CommandLine.arguments.contains("--physical-check")
        let instruction: String
        if physical && CommandLine.arguments.contains("--click-test") {
            instruction = "F6 → wait 1 second → F6. Then F6 → ⌘⇧Escape."
        } else if physical {
            instruction = "Press Command + Up Arrow once, then release the keys."
        } else { instruction = "Disposable local input target · no business actions" }
        let label = NSTextField(labelWithString: instruction)
        label.frame = NSRect(x: 24, y: 396, width: 570, height: 24)
        content.addSubview(label)
        counter = NSButton(title: "Click counter: 0", target: self, action: #selector(count))
        counter.frame = NSRect(x: 24, y: 330, width: 570, height: 52)
        counter.bezelStyle = .rounded
        counter.setAccessibilityIdentifier("click-counter")
        content.addSubview(counter)
        let reset = NSButton(title: "Reset Test", target: self, action: #selector(resetTest))
        reset.frame = NSRect(x: 24, y: 286, width: 120, height: 32)
        content.addSubview(reset)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 24, width: 570, height: 246))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        text = NSTextView(frame: scroll.bounds)
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        text.delegate = self
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.setAccessibilityIdentifier("test-editor")
        scroll.documentView = text
        content.addSubview(scroll)
        if let index = CommandLine.arguments.firstIndex(of: "--image-reference"), CommandLine.arguments.indices.contains(index + 2) {
            let image = NSImageView(frame: NSRect(x: 254, y: 138, width: 112, height: 84))
            image.image = NSImage(contentsOfFile: CommandLine.arguments[index + 1])
            image.imageScaling = .scaleProportionallyUpOrDown
            image.isHidden = true
            content.addSubview(image)
            marker = image
            let controlURL = URL(fileURLWithPath: CommandLine.arguments[index + 2])
            markerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let visible = (try? String(contentsOf: controlURL, encoding: .utf8)) == "visible"
                    if self.marker?.isHidden != !visible { self.marker?.isHidden = !visible; self.writeResult() }
                }
            }
        }
        let menu = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit Input Receiver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--click-test") {
            let buttonRect = window.convertToScreen(counter.convert(counter.bounds, to: nil))
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: buttonRect.midX, y: mainHeight - buttonRect.midY))
        }
        writeResult()
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            self.mouseEvents.append(["type": event.type.rawValue, "window": event.windowNumber,
                "windowPoint": [event.locationInWindow.x, event.locationInWindow.y],
                "globalPoint": [event.cgEvent?.location.x ?? -1, event.cgEvent?.location.y ?? -1],
                "eventWindowFrame": event.window.map { [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height] } ?? []])
            self.mouseEvents = Array(self.mouseEvents.suffix(20))
            self.writeResult()
            return event
        }
    }
    @objc func count() {
        clicks += 1
        timestamps.append(ProcessInfo.processInfo.systemUptime)
        counter.title = "Click counter: \(clicks)"
        writeResult()
    }
    @objc func resetTest() { clicks = 0; timestamps = []; text.string = ""; counter.title = "Click counter: 0"; writeResult() }
    func textDidChange(_ notification: Notification) { writeResult() }
    func writeResult() {
        let rectangle = window.convertToScreen(counter.convert(counter.bounds, to: nil))
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        var result: [String: Any] = ["clicks": clicks, "clickTimes": timestamps, "text": text.string, "mouseEvents": mouseEvents,
            "markerVisible": marker?.isHidden == false,
            "windowNumber": window.windowNumber, "windowFrame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
            "clickRect": [rectangle.minX, mainHeight - rectangle.maxY, rectangle.width, rectangle.height]]
        if let marker {
            let markerRect = window.convertToScreen(marker.convert(marker.bounds, to: nil))
            result["markerRect"] = [markerRect.minX, mainHeight - markerRect.maxY, markerRect.width, markerRect.height]
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output, options: .atomic)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = InputReceiver()
app.delegate = delegate
app.run()
