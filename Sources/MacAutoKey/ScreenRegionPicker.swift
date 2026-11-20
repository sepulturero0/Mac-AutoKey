import AppKit
import ScreenCaptureKit

enum ScreenCropGeometry {
    static func pixelRect(selection: CGRect, pointSize: CGSize, pixelSize: CGSize) -> CGRect? {
        guard pointSize.width > 0, pointSize.height > 0, pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let selected = selection.standardized.intersection(CGRect(origin: .zero, size: pointSize))
        guard !selected.isNull, selected.width >= 8, selected.height >= 8,
              selected.width <= 4000, selected.height <= 4000 else { return nil }
        let sx = pixelSize.width / pointSize.width, sy = pixelSize.height / pointSize.height
        let minX = floor(selected.minX * sx), minY = floor(selected.minY * sy)
        return CGRect(x: minX, y: minY, width: ceil(selected.maxX * sx) - minX, height: ceil(selected.maxY * sy) - minY)
            .intersection(CGRect(origin: .zero, size: pixelSize))
    }
}

/// Freezes the visible screens, lets the user drag a crop, and keeps only that crop.
@MainActor
final class ScreenRegionPicker {
    private var panels: [NSPanel] = []
    private var task: Task<Void, Never>?
    private var completion: ((Result<ImageReference?, any Error>) -> Void)?
    private var deactivationObserver: (any NSObjectProtocol)?

    func begin(_ completion: @escaping (Result<ImageReference?, any Error>) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        task = Task { [weak self] in
            do {
                guard CGPreflightScreenCaptureAccess() else {
                    throw AutoKeyError.message("Allow Screen Recording before capturing a reference area.")
                }
                // The configuration window disappears before the snapshot is taken.
                NSApp.hide(nil)
                try await Task.sleep(for: .milliseconds(300))
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                var snapshots: [(NSRect, CGImage)] = []
                for screen in NSScreen.screens {
                    try Task.checkCancellation()
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                          let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                    let config = SCStreamConfiguration()
                    let scale = min(screen.backingScaleFactor, 4096 / max(screen.frame.width, screen.frame.height))
                    config.width = max(1, Int(screen.frame.width * scale))
                    config.height = max(1, Int(screen.frame.height * scale))
                    config.showsCursor = false
                    config.capturesAudio = false
                    let frame = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
                    snapshots.append((screen.frame, frame))
                }
                try Task.checkCancellation()
                guard let self else { return }
                guard !snapshots.isEmpty else { throw AutoKeyError.message("No screen is available to capture.") }
                NSApp.unhide(nil)
                // Keep other app windows hidden until selection is complete.
                for window in NSApp.windows where window.title == "Mac AutoKey" || window.title == "Settings" { window.orderOut(nil) }
                for (frame, image) in snapshots {
                    let panel = CropPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.title = "Capture reference area"
                    panel.level = .screenSaver
                    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                    panel.backgroundColor = .clear
                    panel.isOpaque = false
                    panel.hasShadow = false
                    panel.hidesOnDeactivate = false
                    panel.acceptsMouseMovedEvents = true
                    let view = CropSelectionView(frame: NSRect(origin: .zero, size: frame.size), snapshot: image)
                    view.onCancel = { [weak self] in self?.cancel() }
                    view.onSelection = { [weak self] selected in
                        guard let self else { return }
                        do {
                            guard let rect = ScreenCropGeometry.pixelRect(selection: selected, pointSize: frame.size,
                                pixelSize: CGSize(width: image.width, height: image.height)), let cropped = image.cropping(to: rect) else {
                                throw AutoKeyError.message("Select an area from 8 to 4,000 screen points on one display.")
                            }
                            let bitmap = NSBitmapImageRep(cgImage: cropped)
                            bitmap.size = selected.size
                            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                                throw AutoKeyError.message("Could not create the reference image. Try capturing again.")
                            }
                            var reference = try ImageReference.load(data: data, name: "Captured screen area")
                            reference.widthPoints = selected.width
                            reference.heightPoints = selected.height
                            self.finish(.success(reference))
                        } catch { self.finish(.failure(error)) }
                    }
                    panel.contentView = view
                    self.panels.append(panel)
                    panel.makeKeyAndOrderFront(nil)
                    panel.makeFirstResponder(view)
                }
                NSApp.activate(ignoringOtherApps: true)
                self.deactivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancel() }
                }
            } catch {
                guard !(error is CancellationError) else { return }
                self?.finish(.failure(error))
            }
        }
    }

    func cancel() { finish(.success(nil)) }

    private func finish(_ result: Result<ImageReference?, any Error>) {
        guard let callback = completion else { return }
        completion = nil
        task?.cancel(); task = nil
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels = []
        callback(result)
    }
}

@MainActor
private final class CropPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class CropSelectionView: NSView {
    private let snapshot: NSImage
    private var anchor: CGPoint?
    private var selection: CGRect?
    private var message = "Drag to capture a reference image · Esc or right-click to cancel"
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, snapshot: CGImage) {
        self.snapshot = NSImage(cgImage: snapshot, size: frame.size)
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Capture reference area. Drag a rectangle on this screen. Press Escape to cancel.")
    }
    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill(); shade.fill()
        if let selection {
            let outline = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            NSColor.white.setStroke(); outline.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white]
        let label = NSAttributedString(string: message, attributes: attributes)
        let labelSize = label.size()
        let origin = NSPoint(x: max(12, (bounds.width - labelSize.width) / 2), y: min(60, bounds.height / 5))
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: CGRect(origin: origin, size: labelSize).insetBy(dx: -12, dy: -8), xRadius: 8, yRadius: 8).fill()
        label.draw(at: origin)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selection, selection.width >= 8, selection.height >= 8 else {
            message = "Select at least 8 × 8 screen points · Esc to cancel"
            needsDisplay = true
            return
        }
        onSelection?(selection.integral)
    }
    override func rightMouseUp(with event: NSEvent) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
