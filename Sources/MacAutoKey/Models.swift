import Foundation
import Carbon

struct Shortcut: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var command = false
    var option = false
    var control = false
    var shift = false

    var carbonModifiers: UInt32 {
        (command ? UInt32(cmdKey) : 0) | (option ? UInt32(optionKey) : 0)
        | (control ? UInt32(controlKey) : 0) | (shift ? UInt32(shiftKey) : 0)
    }
    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "")
        + (command ? "⌘" : "") + (KeyCatalog.name(for: keyCode))
    }
    static let clicker = Shortcut(keyCode: 97) // F6
    static let sequence = Shortcut(keyCode: 126, command: true)
    static let emergency = Shortcut(keyCode: 53, command: true, shift: true)
}

enum ActionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case key = "Press Key", text = "Type Text", delay = "Wait / Delay"
    var id: Self { self }
}

struct SequenceAction: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: ActionKind
    var keyCode: UInt16 = 36
    var text = ""
    var delayMS = 500
    static let sample: [Self] = [
        .init(kind: .text, text: "15"), .init(kind: .delay),
        .init(kind: .key), .init(kind: .delay),
        .init(kind: .text, text: "10"), .init(kind: .key)
    ]
}

enum TextEntryMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case physical = "Physical keys (US layout)"
    case unicode = "Unicode characters"
    var id: Self { self }
}

struct TargetApplication: Identifiable, Codable, Equatable, Sendable {
    var bundleID: String
    var name: String
    var path: String
    var id: String { bundleID + "|" + path }
}

struct KeyboardCommand: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name = "New command"
    var enabled = true
    var shortcut = Shortcut.sequence
    var keystrokeDelayMS = 60
    var textMode = TextEntryMode.physical
    var actions: [SequenceAction] = []
    static let sample = KeyboardCommand(name: "15 then 10", actions: SequenceAction.sample)
}

struct Configuration: Codable, Equatable, Sendable {
    var version = 2
    var clickerEnabled = true
    var keyboardEnabled = true
    var clickIntervalMS = 100
    var clickShortcut = Shortcut.clicker
    var fixedClickEnabled = false
    var fixedClickX = 0
    var fixedClickY = 0
    var citrixOnly = false
    var allowedTargets: [TargetApplication] = []
    var commands = [KeyboardCommand.sample]

    init() {}
    private enum CodingKeys: String, CodingKey {
        case version, clickerEnabled, keyboardEnabled, clickIntervalMS, clickShortcut, citrixOnly, allowedTargets, commands
        case sequenceShortcut, keystrokeDelayMS, textMode, actions
        case fixedClickEnabled, fixedClickX, fixedClickY
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        guard storedVersion == 1 || storedVersion == 2 else {
            throw AutoKeyError.message("This settings version is not supported.")
        }
        clickerEnabled = try values.decode(Bool.self, forKey: .clickerEnabled)
        keyboardEnabled = try values.decode(Bool.self, forKey: .keyboardEnabled)
        clickIntervalMS = try values.decode(Int.self, forKey: .clickIntervalMS)
        clickShortcut = try values.decode(Shortcut.self, forKey: .clickShortcut)
        fixedClickEnabled = try values.decodeIfPresent(Bool.self, forKey: .fixedClickEnabled) ?? false
        fixedClickX = try values.decodeIfPresent(Int.self, forKey: .fixedClickX) ?? 0
        fixedClickY = try values.decodeIfPresent(Int.self, forKey: .fixedClickY) ?? 0
        citrixOnly = try values.decode(Bool.self, forKey: .citrixOnly)
        allowedTargets = try values.decode([TargetApplication].self, forKey: .allowedTargets)
        if storedVersion == 1 {
            var migrated = KeyboardCommand.sample
            migrated.shortcut = try values.decode(Shortcut.self, forKey: .sequenceShortcut)
            migrated.keystrokeDelayMS = try values.decode(Int.self, forKey: .keystrokeDelayMS)
            migrated.textMode = try values.decode(TextEntryMode.self, forKey: .textMode)
            migrated.actions = try values.decode([SequenceAction].self, forKey: .actions)
            commands = [migrated]
        } else { commands = try values.decode([KeyboardCommand].self, forKey: .commands) }
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(clickerEnabled, forKey: .clickerEnabled)
        try values.encode(keyboardEnabled, forKey: .keyboardEnabled)
        try values.encode(clickIntervalMS, forKey: .clickIntervalMS)
        try values.encode(clickShortcut, forKey: .clickShortcut)
        try values.encode(fixedClickEnabled, forKey: .fixedClickEnabled)
        try values.encode(fixedClickX, forKey: .fixedClickX)
        try values.encode(fixedClickY, forKey: .fixedClickY)
        try values.encode(citrixOnly, forKey: .citrixOnly)
        try values.encode(allowedTargets, forKey: .allowedTargets)
        try values.encode(commands, forKey: .commands)
    }
    // The verification harness also exercises the original sample through these
    // primary-command accessors. The editor and hotkeys always address commands by ID.
    var sequenceShortcut: Shortcut {
        get { commands.first?.shortcut ?? .sequence }
        set { if !commands.isEmpty { commands[0].shortcut = newValue } }
    }
    var keystrokeDelayMS: Int {
        get { commands.first?.keystrokeDelayMS ?? 60 }
        set { if !commands.isEmpty { commands[0].keystrokeDelayMS = newValue } }
    }
    var textMode: TextEntryMode {
        get { commands.first?.textMode ?? .physical }
        set { if !commands.isEmpty { commands[0].textMode = newValue } }
    }
    var actions: [SequenceAction] {
        get { commands.first?.actions ?? [] }
        set { if !commands.isEmpty { commands[0].actions = newValue } }
    }
    var shortcutAssignments: [(role: HotkeyRole, shortcut: Shortcut)] {
        var result: [(HotkeyRole, Shortcut)] = [(.emergency, .emergency)]
        if clickerEnabled { result.append((.clicker, clickShortcut)) }
        if keyboardEnabled {
            result += commands.filter(\.enabled).map { (.command($0.id), $0.shortcut) }
        }
        return result
    }

    func validate() throws {
        guard version == 2 else { throw AutoKeyError.message("This settings version is not supported.") }
        guard (30...60_000).contains(clickIntervalMS) else {
            throw AutoKeyError.message("Click interval must be 30–60,000 milliseconds.")
        }
        guard (-100_000...100_000).contains(fixedClickX), (-100_000...100_000).contains(fixedClickY) else {
            throw AutoKeyError.message("Click coordinates must be whole numbers from −100,000 to 100,000.")
        }
        guard commands.count <= 50, Set(commands.map(\.id)).count == commands.count else {
            throw AutoKeyError.message("Use at most 50 commands, each with a unique ID.")
        }
        let shortcuts = [clickShortcut, Shortcut.emergency] + commands.map(\.shortcut)
        guard Set(shortcuts).count == shortcuts.count else {
            throw AutoKeyError.message("Each command and the clicker need different shortcuts, including Stop All (⌘⇧Escape).")
        }
        for shortcut in shortcuts {
            guard KeyCatalog.keys.contains(where: { $0.code == shortcut.keyCode }) else {
                throw AutoKeyError.message("Choose a supported shortcut key.")
            }
            if shortcut.command && [12, 48, 49].contains(shortcut.keyCode) {
                throw AutoKeyError.message("\(shortcut.label) is a system shortcut. Try ⌃⌥F8 or ⌃⌥F9.")
            }
        }
        for command in commands {
            guard !command.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, command.name.count <= 100 else {
                throw AutoKeyError.message("Give each command a name of 1–100 characters.")
            }
            let keystrokeDelayMS = command.keystrokeDelayMS
            let actions = command.actions
            let textMode = command.textMode
            guard (20...2_000).contains(keystrokeDelayMS) else {
                throw AutoKeyError.message("Inter-keystroke delay must be 20–2,000 milliseconds.")
            }
            guard actions.count <= 500 else { throw AutoKeyError.message("Use at most 500 sequence steps.") }
            for (index, action) in actions.enumerated() {
                switch action.kind {
                case .delay:
                    guard (0...600_000).contains(action.delayMS) else {
                        throw AutoKeyError.message("Step \(index + 1): delay must be 0–600,000 milliseconds.")
                    }
                case .key:
                    guard KeyCatalog.keys.contains(where: { $0.code == action.keyCode }) else {
                        throw AutoKeyError.message("Step \(index + 1): unsupported key.")
                    }
                case .text:
                    guard action.text.count <= 10_000 else {
                        throw AutoKeyError.message("Step \(index + 1): text is limited to 10,000 characters.")
                    }
                    if textMode == .physical,
                       let unsupported = action.text.first(where: { KeyCatalog.stroke(for: $0) == nil }) {
                        throw AutoKeyError.message("Step \(index + 1): ‘\(unsupported)’ needs Unicode mode. Physical text uses the US keyboard layout.")
                    }
                }
            }
            // Carbon hotkeys do not expose CGEvent source tags. Reject sequences that could
            // synthesize our shortcuts, rather than temporarily disabling the emergency key.
            for action in actions {
                let strokes: [KeyStroke]
                switch action.kind {
                case .key: strokes = [.init(code: action.keyCode, shift: false)]
                case .delay: strokes = []
                case .text:
                    strokes = action.text.compactMap {
                        if textMode == .unicode {
                            return KeyStroke(code: $0 == "\n" ? 36 : ($0 == "\t" ? 48 : 0), shift: false)
                        }
                        return KeyCatalog.stroke(for: $0)
                    }
                }
                for stroke in strokes {
                    if let match = shortcuts.first(where: {
                        !$0.command && !$0.control && !$0.option && $0.shift == stroke.shift && $0.keyCode == stroke.code
                    }) {
                        throw AutoKeyError.message("The sequence can generate \(match.label), which is an activation shortcut. Add Command, Control, or Option to that shortcut.")
                    }
                }
            }
        }
    }
}

enum AutoKeyError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}

enum NumericField: Hashable {
    case clickInterval, fixedClickX, fixedClickY, keystrokeDelay, commandDelay(UUID), actionDelay(UUID)
    var label: String {
        switch self {
        case .clickInterval: "Click interval in milliseconds"
        case .fixedClickX: "Click X coordinate"
        case .fixedClickY: "Click Y coordinate"
        case .keystrokeDelay, .commandDelay: "Inter-keystroke delay in milliseconds"
        case .actionDelay: "Step delay in milliseconds"
        }
    }
    var range: ClosedRange<Int> {
        switch self {
        case .clickInterval: 30...60_000
        case .fixedClickX, .fixedClickY: -100_000...100_000
        case .keystrokeDelay, .commandDelay: 20...2_000
        case .actionDelay: 0...600_000
        }
    }
}

struct ConfigurationStore {
    let defaults: UserDefaults
    static let key = "MacAutoKey.Configuration.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() throws -> Configuration {
        guard let data = defaults.data(forKey: Self.key) else { return Configuration() }
        let config = try JSONDecoder().decode(Configuration.self, from: data)
        try config.validate()
        return config
    }
    func save(_ config: Configuration) throws {
        try config.validate()
        defaults.set(try JSONEncoder().encode(config), forKey: Self.key)
    }
}
