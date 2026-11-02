import Foundation
import Carbon

enum HotkeyRole: Hashable, Sendable {
    case clicker, command(UUID), emergency
}

@MainActor
final class GlobalHotkeyManager {
    private var handler: EventHandlerRef?
    private var references: [HotkeyRole: EventHotKeyRef] = [:]
    private var roles: [UInt32: HotkeyRole] = [:]
    private var nextEventID: UInt32 = 1
    private var held: Set<UInt32> = []
    private var handlerStatus: OSStatus = noErr
    var onPress: ((HotkeyRole) -> Void)?
    static let signature: OSType = 0x4D414B59

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalHotkeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(context).takeUnretainedValue()
            // Carbon dispatches this application event handler on the main event loop.
            MainActor.assumeIsolated {
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { manager.held.remove(id.id) }
                else if manager.held.insert(id.id).inserted, let role = manager.roles[id.id] {
                    manager.onPress?(role)
                }
            }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(config: Configuration, automationValid: Bool = true) -> [String] {
        unregister()
        guard handlerStatus == noErr else { return ["Global shortcut handler failed (\(handlerStatus)). Restart the app; use Stop All in the menu meanwhile."] }
        var failures: [String] = []
        // Emergency gets first chance and remains registered even for invalid settings.
        let assignments = automationValid ? config.shortcutAssignments : [(.emergency, Shortcut.emergency)]
        for (role, shortcut) in assignments {
            // Never reuse IDs when settings change: queued events from an old
            // registration must not trigger a different command.
            let eventID = nextEventID
            nextEventID += 1
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                EventHotKeyID(signature: Self.signature, id: eventID), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references[role] = reference; roles[eventID] = role }
            else { failures.append("\(shortcut.label) could not be registered (macOS \(status)). It may be in use or reserved. Try ⌃⌥F8 / ⌃⌥F9. Stop All remains available in the menu.") }
        }
        return failures
    }
    func unregister() {
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll()
        roles.removeAll()
        held.removeAll()
    }
    func shutdown() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
