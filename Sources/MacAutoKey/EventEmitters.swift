import CoreGraphics
import ApplicationServices
import AppKit

struct ClickTargetWindow {
    var id: CGWindowID
    var bounds: CGRect
}

@MainActor
protocol InputEmitting: AnyObject {
    func click() throws
    func click(at point: CGPoint, targetPID: pid_t) throws
    func press(_ stroke: KeyStroke) throws
    func unicode(_ character: Character) throws
}

@MainActor
final class NativeEventEmitter: InputEmitting {
    private let source = CGEventSource(stateID: .privateState)
    private let deliver: (CGEvent) -> Void
    private let pointer: () -> CGPoint?
    private let deliverToPID: (CGEvent, pid_t) -> Void
    private let resolveTargetWindow: (CGPoint, pid_t) throws -> ClickTargetWindow
    static let eventTag: Int64 = 0x4D414B4559

    init(deliver: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
         pointer: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location },
         deliverToPID: @escaping (CGEvent, pid_t) -> Void = { $0.postToPid($1) },
         resolveTargetWindow: @escaping (CGPoint, pid_t) throws -> ClickTargetWindow = NativeEventEmitter.windowAtClickPosition) {
        self.deliver = deliver
        self.pointer = pointer
        self.deliverToPID = deliverToPID
        self.resolveTargetWindow = resolveTargetWindow
    }

    private func post(_ event: CGEvent, flags: CGEventFlags = []) {
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        deliver(event)
    }
    func click() throws {
        guard let location = pointer() else { throw AutoKeyError.message("macOS could not read the pointer position.") }
        try clickPair(at: location, targetPID: nil, window: nil)
    }
    func click(at point: CGPoint, targetPID: pid_t) throws {
        guard targetPID > 0, point.x.isFinite, point.y.isFinite else {
            throw AutoKeyError.message("The fixed click target is unavailable.")
        }
        let window = try resolveTargetWindow(point, targetPID)
        // Process-directed events bypass the hardware cursor stream. Never warp,
        // hide, or temporarily detach the user's physical pointer.
        try clickPair(at: point, targetPID: targetPID, window: window)
    }
    private func clickPair(at location: CGPoint, targetPID: pid_t?, window: ClickTargetWindow?) throws {
        guard let source else { throw AutoKeyError.message("macOS could not create a private mouse event source.") }
        let down: CGEvent?
        let up: CGEvent?
        if let window {
            // NSEvent's public factory includes the receiving window identity.
            // A bare process-directed CGEvent has window number 0 in AppKit.
            func event(_ type: NSEvent.EventType) -> CGEvent? {
                // Process-directed mouse events use flipped window coordinates.
                // The NSEvent factory flips Y against the main display when
                // producing its CGEvent, so compensate here. Do not overwrite
                // CGEvent.location afterward: that invalidates its window point.
                let local = NSPoint(x: location.x - window.bounds.minX,
                    y: CGDisplayBounds(CGMainDisplayID()).height - (location.y - window.bounds.minY))
                let result = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(window.id),
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)?.cgEvent
                result?.setSource(source)
                return result
            }
            down = event(.leftMouseDown)
            up = event(.leftMouseUp)
        } else {
            down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)
            up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
        }
        guard let down, let up else {
            throw AutoKeyError.message("macOS could not create a mouse event. Check Accessibility permission.")
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        // A pair is atomic on the main actor: cancellation cannot leave a held button.
        if let targetPID, let window {
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
                event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.id))
                event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.id))
                deliverToPID(event, targetPID)
            }
        } else {
            post(down)
            post(up)
        }
    }
    nonisolated static func windowAtClickPosition(_ point: CGPoint, targetPID: pid_t) throws -> ClickTargetWindow {
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 0, nil, &count) == .success, count > 0 else {
            throw AutoKeyError.message("The fixed click position is outside the connected displays. Pick a new position.")
        }
        // Hit-test the actual accessible target. Noninteractive screen overlays
        // can cover the display in the window list without receiving input.
        var element: AXUIElement?
        var owner: pid_t = 0
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
              let element, AXUIElementGetPid(element, &owner) == .success else {
            throw AutoKeyError.message("macOS could not verify the fixed click target. Check Accessibility access and pick the position again.")
        }
        guard owner == targetPID else {
            throw AutoKeyError.message("The fixed click position is not on the focused target window. Move the window back or pick a new position.")
        }
        // Read geometry/PIDs only, never window titles or screen contents.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw AutoKeyError.message("macOS could not locate the fixed click target.")
        }
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point),
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let owner = window[kCGWindowOwnerPID as String] as? Int, owner == targetPID,
                  let number = window[kCGWindowNumber as String] as? UInt32 else { continue }
            return ClickTargetWindow(id: number, bounds: rect)
        }
        throw AutoKeyError.message("No target window is at the fixed click position. Pick a new position.")
    }
    func press(_ stroke: KeyStroke) throws {
        guard let source,
              let down = CGEvent(keyboardEventSource: source, virtualKey: stroke.code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: stroke.code, keyDown: false) else {
            throw AutoKeyError.message("macOS could not create a keyboard event.")
        }
        // Prepare the whole pair before posting. Shift is released synchronously, even
        // if cancellation is requested. No Command/Option/Control events are generated.
        let flags: CGEventFlags = stroke.shift ? .maskShift : []
        var shiftDown: CGEvent?
        var shiftUp: CGEvent?
        if stroke.shift {
            shiftDown = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: true)
            shiftUp = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: false)
            guard shiftDown != nil, shiftUp != nil else { throw AutoKeyError.message("macOS could not create a Shift event.") }
        }
        if let shiftDown { post(shiftDown, flags: .maskShift) }
        post(down, flags: flags)
        post(up, flags: flags)
        if let shiftUp { post(shiftUp) }
    }
    func unicode(_ character: Character) throws {
        if character == "\n" || character == "\r" { try press(.init(code: 36, shift: false)); return }
        if character == "\t" { try press(.init(code: 48, shift: false)); return }
        guard let source,
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw AutoKeyError.message("macOS could not create a Unicode keyboard event.")
        }
        let units = Array(String(character).utf16)
        units.withUnsafeBufferPointer { buffer in
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        post(down)
        post(up)
    }
}
