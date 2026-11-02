import Foundation
import CoreGraphics

enum RunState: Equatable {
    case idle, arming, running, paused, completed, stopped, failed(String)
    var isActive: Bool { self == .arming || self == .running || self == .paused }
    var label: String {
        switch self {
        case .idle: "Ready"
        case .arming: "Starting in 3 seconds — focus your target"
        case .running: "Running"
        case .paused: "Paused"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .failed(let message): message
        }
    }
}

@MainActor
enum AutomationTiming {
    static func sleep(ms: Int) async throws {
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(ms))
        try Task.checkCancellation()
    }
    static var physicalModifiersHeld: Bool {
        !CGEventSource.flagsState(.hidSystemState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }
    static func waitForShortcutRelease() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while physicalModifiersHeld {
            guard ContinuousClock.now < deadline else {
                throw AutoKeyError.message("Release shortcut modifiers before running automation.")
            }
            try await sleep(ms: 20)
        }
    }
}

@MainActor
final class AutoClickerEngine {
    private(set) var state: RunState = .idle { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var control: RunControl?
    let emitter: any InputEmitting
    init(emitter: any InputEmitting) { self.emitter = emitter }

    func start(intervalMS: Int, fixedPosition: CGPoint? = nil, targetPID: @escaping () -> pid_t? = { nil }, manual: Bool = false,
               prepare: @escaping () throws -> Void = {}, safety: @escaping () throws -> Void) {
        guard !state.isActive else { return }
        guard (30...60_000).contains(intervalMS) else { state = .failed("Invalid click interval."); return }
        let token = UUID()
        generation = token
        let control = RunControl()
        self.control = control
        state = manual ? .arming : .running
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if manual { try await AutomationTiming.sleep(ms: 3_000) }
                try await AutomationTiming.waitForShortcutRelease()
                try Task.checkCancellation()
                try prepare()
                self.state = control.isPaused ? .paused : .running
                while true {
                    try await control.waitIfPaused()
                    try safety()
                    if let fixedPosition {
                        guard let pid = targetPID() else { throw AutoKeyError.message("The fixed click target is unavailable.") }
                        try self.emitter.click(at: fixedPosition, targetPID: pid)
                    } else { try self.emitter.click() }
                    // Sleep from the last click. Never catch up in bursts after a stall.
                    try await control.sleep(ms: intervalMS)
                }
            } catch {
                if self.generation == token {
                    self.state = error is CancellationError ? .stopped : .failed(error.localizedDescription)
                    self.task = nil
                }
            }
        }
    }
    func pause() {
        guard state == .running else { return }
        control?.pause()
        state = .paused
    }
    func resume() {
        guard state == .paused else { return }
        state = .running
        control?.resume()
    }
    func stop() {
        generation = UUID()
        task?.cancel()
        control?.cancel()
        control = nil
        task = nil
        if state.isActive { state = .stopped }
    }
}

@MainActor
final class KeyboardAutomationEngine {
    private(set) var state: RunState = .idle { didSet { onChange?() } }
    private(set) var currentStep = 0 { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var control: RunControl?
    let emitter: any InputEmitting
    init(emitter: any InputEmitting) { self.emitter = emitter }

    func start(actions: [SequenceAction], delayMS: Int, mode: TextEntryMode, manual: Bool = false,
               prepare: @escaping () throws -> Void = {}, safety: @escaping () throws -> Void) {
        guard !state.isActive else { return }
        guard (20...2_000).contains(delayMS) else { state = .failed("Invalid keystroke delay."); return }
        let token = UUID()
        generation = token
        let control = RunControl()
        self.control = control
        currentStep = 0
        state = manual ? .arming : .running
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if manual { try await AutomationTiming.sleep(ms: 3_000) }
                try await AutomationTiming.waitForShortcutRelease()
                try Task.checkCancellation()
                try prepare()
                self.state = control.isPaused ? .paused : .running
                for (index, action) in actions.enumerated() {
                    try await control.waitIfPaused()
                    try safety()
                    self.currentStep = index + 1
                    switch action.kind {
                    case .delay:
                        guard (0...600_000).contains(action.delayMS) else { throw AutoKeyError.message("Invalid sequence delay.") }
                        try await control.sleep(ms: action.delayMS)
                    case .key:
                        try safety()
                        try self.emitter.press(.init(code: action.keyCode, shift: false))
                        try await control.sleep(ms: delayMS)
                    case .text:
                        for character in action.text {
                            try await control.waitIfPaused()
                            try safety()
                            if mode == .unicode { try self.emitter.unicode(character) }
                            else if let stroke = KeyCatalog.stroke(for: character) { try self.emitter.press(stroke) }
                            else { throw AutoKeyError.message("Unsupported physical character: \(character)") }
                            try await control.sleep(ms: delayMS)
                        }
                    }
                }
                try await control.waitIfPaused()
                try safety()
                if self.generation == token { self.state = .completed; self.task = nil }
            } catch {
                if self.generation == token {
                    self.state = error is CancellationError ? .stopped : .failed(error.localizedDescription)
                    self.task = nil
                }
            }
        }
    }
    func pause() {
        guard state == .running else { return }
        control?.pause()
        state = .paused
    }
    func resume() {
        guard state == .paused else { return }
        state = .running
        control?.resume()
    }
    func stop() {
        generation = UUID()
        task?.cancel()
        control?.cancel()
        control = nil
        task = nil
        if state.isActive { state = .stopped }
    }
}
