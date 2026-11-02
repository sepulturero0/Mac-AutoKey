import Foundation
import CoreGraphics
import AppKit
import Testing
@testable import MacAutoKey

@MainActor
private final class RecordingEmitter: InputEmitting {
    enum Event: Equatable { case click, fixedClick(CGPoint, pid_t), key(KeyStroke), unicode(Character) }
    var events: [Event] = []
    var times: [ContinuousClock.Instant] = []
    var shouldFail = false
    func record(_ event: Event) throws {
        if shouldFail { throw AutoKeyError.message("Test emission failure") }
        events.append(event)
        times.append(.now)
    }
    func click() throws { try record(.click) }
    func click(at point: CGPoint, targetPID: pid_t) throws { try record(.fixedClick(point, targetPID)) }
    func press(_ stroke: KeyStroke) throws { try record(.key(stroke)) }
    func unicode(_ character: Character) throws { try record(.unicode(character)) }
}

@Suite(.serialized)
@MainActor
struct AutomationTests {
    @Test func sampleSequenceOrderAndDelays() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        engine.start(actions: SequenceAction.sample, delayMS: 60, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(1_650))
        #expect(engine.state == .completed)
        #expect(emitter.events == [
            .key(.init(code: 18, shift: false)), .key(.init(code: 23, shift: false)),
            .key(.init(code: 36, shift: false)), .key(.init(code: 18, shift: false)),
            .key(.init(code: 29, shift: false)), .key(.init(code: 36, shift: false))
        ])
        #expect(emitter.times.count == 6)
        if emitter.times.count == 6 {
            #expect(emitter.times[1].duration(to: emitter.times[2]) >= .milliseconds(550))
            #expect(emitter.times[2].duration(to: emitter.times[3]) >= .milliseconds(550))
        }
    }

    @Test func clickerIntervalDuplicateStartAndStop() async throws {
        let emitter = RecordingEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        engine.start(intervalMS: 40, safety: {})
        engine.start(intervalMS: 40, safety: {})
        try await Task.sleep(for: .milliseconds(185))
        engine.stop()
        let count = emitter.events.count
        #expect((3...6).contains(count))
        for (a, b) in zip(emitter.times, emitter.times.dropFirst()) {
            #expect(a.duration(to: b) >= .milliseconds(35))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(emitter.events.count == count)
        #expect(engine.state == .stopped)
    }

    @Test func cancellationDuringLongDelay() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        engine.start(actions: [.init(kind: .delay, delayMS: 60_000), .init(kind: .key)],
                     delayMS: 20, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(30))
        engine.stop()
        try await Task.sleep(for: .milliseconds(50))
        #expect(emitter.events.isEmpty)
        #expect(engine.state == .stopped)
    }

    @Test func cancellationDuringTypingAndOverlapPrevention() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        let actions: [SequenceAction] = [.init(kind: .text, text: "1234567890")]
        engine.start(actions: actions, delayMS: 60, mode: .physical, safety: {})
        engine.start(actions: actions, delayMS: 60, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(145))
        engine.stop()
        let count = emitter.events.count
        #expect((1...3).contains(count))
        try await Task.sleep(for: .milliseconds(120))
        #expect(emitter.events.count == count)
    }

    @Test func cancellationDuringArmingProducesNoInput() async throws {
        let emitter = RecordingEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        engine.start(intervalMS: 30, manual: true, safety: {})
        #expect(engine.state == .arming)
        engine.stop()
        try await Task.sleep(for: .milliseconds(50))
        #expect(emitter.events.isEmpty)
    }

    @Test func rapidStopRestartDoesNotOverwriteNewRun() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        engine.start(actions: [.init(kind: .delay, delayMS: 10_000)], delayMS: 20, mode: .physical, safety: {})
        engine.stop()
        engine.start(actions: [.init(kind: .text, text: "9")], delayMS: 20, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.state == .completed)
        #expect(emitter.events == [.key(.init(code: 25, shift: false))])
    }

    @Test func failedFocusGateStopsBeforeNextEvent() async throws {
        let emitter = RecordingEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        var focused = true
        engine.start(intervalMS: 30, safety: {
            if !focused { throw AutoKeyError.message("Target lost focus") }
        })
        try await Task.sleep(for: .milliseconds(45))
        focused = false
        let count = emitter.events.count
        try await Task.sleep(for: .milliseconds(80))
        #expect(emitter.events.count == count)
        #expect(engine.state == .failed("Target lost focus"))
    }

    @Test func focusGateCheckedPerCharacter() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        engine.start(actions: [.init(kind: .text, text: "12345")], delayMS: 20, mode: .physical, safety: {
            if emitter.events.count == 2 { throw AutoKeyError.message("Permission revoked") }
        })
        try await Task.sleep(for: .milliseconds(150))
        #expect(emitter.events.count == 2)
        #expect(engine.state == .failed("Permission revoked"))
    }

    @Test func emitterFailureIsReported() async throws {
        let emitter = RecordingEmitter()
        emitter.shouldFail = true
        let engine = AutoClickerEngine(emitter: emitter)
        engine.start(intervalMS: 30, safety: {})
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.state == .failed("Test emission failure"))
        #expect(emitter.events.isEmpty)
    }

    @Test func unicodeEmitsEachCharacterAndPreservesOrder() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        engine.start(actions: [.init(kind: .text, text: "é界🙂")], delayMS: 20, mode: .unicode, safety: {})
        try await Task.sleep(for: .milliseconds(150))
        #expect(engine.state == .completed)
        #expect(emitter.events == [.unicode("é"), .unicode("界"), .unicode("🙂")])
    }
}

struct ConfigurationTests {
    @Test func persistenceRoundTrip() throws {
        let name = "MacAutoKey.Tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = ConfigurationStore(defaults: defaults)
        var config = Configuration()
        config.clickIntervalMS = 234
        config.keystrokeDelayMS = 87
        config.clickShortcut = .init(keyCode: 100, option: true, control: true)
        config.sequenceShortcut = .init(keyCode: 101, option: true, control: true)
        config.citrixOnly = true
        config.allowedTargets = [.init(bundleID: "com.example.viewer", name: "Viewer", path: "/Applications/Viewer.app")]
        config.actions = [.init(kind: .text, text: "custom"), .init(kind: .delay, delayMS: 987), .init(kind: .key, keyCode: 48)]
        try first.save(config)
        let reopened = ConfigurationStore(defaults: defaults)
        #expect(try reopened.load() == config)
    }
    @Test func rejectedSavePreservesPreviousConfiguration() throws {
        let name = "MacAutoKey.Tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConfigurationStore(defaults: defaults)
        try store.save(Configuration())
        var bad = Configuration()
        bad.clickIntervalMS = 1
        #expect(throws: (any Error).self) { try store.save(bad) }
        #expect(try store.load() == Configuration())
    }
    @Test func validatesBoundsDuplicatesAndSelfTriggering() throws {
        try Configuration().validate()
        var bad = Configuration()
        bad.clickIntervalMS = 29
        #expect(throws: (any Error).self) { try bad.validate() }
        bad.clickIntervalMS = 60_001
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = Configuration()
        bad.sequenceShortcut = bad.clickShortcut
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = Configuration()
        bad.clickShortcut = .emergency
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = Configuration()
        bad.clickShortcut = .init(keyCode: 18)
        #expect(throws: (any Error).self) { try bad.validate() }
        bad.clickShortcut.control = true
        try bad.validate()
    }
    @Test func physicalMappingAndUnicodeValidation() throws {
        #expect(KeyCatalog.stroke(for: "1") == .init(code: 18, shift: false))
        #expect(KeyCatalog.stroke(for: "A") == .init(code: 0, shift: true))
        #expect(KeyCatalog.stroke(for: "!") == .init(code: 18, shift: true))
        #expect(KeyCatalog.stroke(for: "é") == nil)
        var config = Configuration()
        config.actions = [.init(kind: .text, text: "é")]
        #expect(throws: (any Error).self) { try config.validate() }
        config.textMode = .unicode
        try config.validate()
        config.clickShortcut = .init(keyCode: 0)
        #expect(throws: (any Error).self) { try config.validate() }
    }
    @Test func rejectsReservedShortcut() {
        var config = Configuration()
        config.clickShortcut = .init(keyCode: 49, command: true)
        #expect(throws: (any Error).self) { try config.validate() }
    }
}

@MainActor
struct NativeEventTests {
    @Test func fixedClicksUseOnlyTheBoundProcessAndWindow() throws {
        var globalEvents: [CGEvent] = []
        var directedEvents: [(CGEvent, pid_t)] = []
        var pointerReads = 0
        let point = CGPoint(x: -150, y: 300)
        let emitter = NativeEventEmitter(deliver: { globalEvents.append($0) }, pointer: {
            pointerReads += 1
            return CGPoint(x: 999, y: 999)
        }, deliverToPID: { directedEvents.append(($0, $1)) }, resolveTargetWindow: { requested, pid in
            #expect(requested == point)
            #expect(pid == 123)
            return ClickTargetWindow(id: 456, bounds: CGRect(x: -200, y: 200, width: 500, height: 500))
        })
        try emitter.click(at: point, targetPID: 123)
        #expect(globalEvents.isEmpty && pointerReads == 0)
        #expect(directedEvents.map { $0.0.type } == [.leftMouseDown, .leftMouseUp])
        #expect(directedEvents.allSatisfy {
            $0.1 == 123 && NSEvent(cgEvent: $0.0)?.windowNumber == 456 && $0.0.flags.isEmpty &&
            $0.0.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 456 &&
            $0.0.getIntegerValueField(.eventSourceUserData) == NativeEventEmitter.eventTag
        })
    }
    @Test func unavailableFixedTargetNeverFallsBackToThePointer() {
        var delivered = 0
        let emitter = NativeEventEmitter(deliver: { _ in delivered += 1 }, deliverToPID: { _, _ in delivered += 1 },
            resolveTargetWindow: { _, _ in throw AutoKeyError.message("Target moved") })
        #expect(throws: (any Error).self) { try emitter.click(at: .zero, targetPID: 123) }
        #expect(throws: (any Error).self) { try emitter.click(at: .zero, targetPID: 0) }
        #expect(throws: (any Error).self) { try emitter.click(at: CGPoint(x: CGFloat.nan, y: 0), targetPID: 123) }
        #expect(delivered == 0)
    }
    @Test func mousePairsUseCurrentPositionWithoutMovement() throws {
        var events: [CGEvent] = []
        var point = CGPoint(x: 123, y: 456)
        let emitter = NativeEventEmitter(deliver: { events.append($0) }, pointer: { point })
        try emitter.click()
        point = CGPoint(x: 234, y: 567)
        try emitter.click()
        #expect(events.map(\.type) == [.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        #expect(events.map(\.location) == [CGPoint(x: 123, y: 456), CGPoint(x: 123, y: 456), point, point])
        #expect(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == NativeEventEmitter.eventTag })
        #expect(events.allSatisfy { $0.flags.isEmpty })
    }
    @Test func keyPairsAndShiftAreReleased() throws {
        var events: [CGEvent] = []
        let emitter = NativeEventEmitter(deliver: { events.append($0) })
        try emitter.press(.init(code: 18, shift: false))
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        #expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 18 && $0.flags.isEmpty })
        events = []
        try emitter.press(.init(code: 0, shift: true))
        #expect(events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(events.first?.getIntegerValueField(.keyboardEventKeycode) == 56)
        #expect(events.last?.getIntegerValueField(.keyboardEventKeycode) == 56)
        #expect(events.last?.flags.isEmpty == true)
    }
    @Test func unicodeContainsUTF16AndEnterUsesPhysicalKey() throws {
        var events: [CGEvent] = []
        let emitter = NativeEventEmitter(deliver: { events.append($0) })
        try emitter.unicode("🙂")
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        events[0].keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        #expect(String(utf16CodeUnits: buffer, count: length) == "🙂")
        events = []
        try emitter.unicode("\n")
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 36 })
    }
}

struct FixedPositionConfigurationTests {
    @Test func olderSettingsDefaultToPointerModeWithoutLosingCommands() throws {
        var original = Configuration()
        original.commands = [KeyboardCommand(name: "Keep this", actions: [.init(kind: .text, text: "custom")])]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["fixedClickEnabled", "fixedClickX", "fixedClickY"] { json.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!migrated.fixedClickEnabled)
        #expect(migrated.commands == original.commands)
        #expect(migrated.clickShortcut == original.clickShortcut)
        try migrated.validate()
    }
    @Test func fixedPositionPersistsAndSupportsNegativeScreenCoordinates() throws {
        var config = Configuration()
        config.fixedClickEnabled = true
        config.fixedClickX = -1920
        config.fixedClickY = 340
        let name = "MacAutoKey.FixedPosition.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConfigurationStore(defaults: defaults)
        try store.save(config)
        #expect(try store.load() == config)
        config.fixedClickX = Int.max
        #expect(throws: (any Error).self) { try store.save(config) }
        #expect(try store.load().fixedClickX == -1920)
    }
}

@MainActor
struct FixedPositionEngineTests {
    @Test func fixedCoordinatesSurvivePauseResumeAndStop() async throws {
        let emitter = RecordingEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        let point = CGPoint(x: 500, y: 300)
        var pid: pid_t?
        engine.start(intervalMS: 40, fixedPosition: point, targetPID: { pid }, prepare: { pid = 123 }, safety: {})
        try await Task.sleep(for: .milliseconds(100))
        engine.pause()
        let pausedCount = emitter.events.count
        try await Task.sleep(for: .milliseconds(100))
        #expect(pausedCount > 0 && emitter.events.count == pausedCount)
        engine.resume()
        try await Task.sleep(for: .milliseconds(90))
        engine.stop()
        let stoppedCount = emitter.events.count
        try await Task.sleep(for: .milliseconds(90))
        #expect(stoppedCount > pausedCount && emitter.events.count == stoppedCount)
        #expect(emitter.events.allSatisfy { $0 == .fixedClick(point, 123) })
    }
    @Test func missingFixedTargetFailsWithoutAnyClick() async throws {
        let emitter = RecordingEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        engine.start(intervalMS: 30, fixedPosition: CGPoint(x: 10, y: 10), safety: {})
        try await Task.sleep(for: .milliseconds(30))
        if case .failed = engine.state {} else { Issue.record("Missing fixed target must fail") }
        #expect(emitter.events.isEmpty)
    }
    @Test func invalidCoordinateDraftBlocksRunAndDisablingModeRecovers() throws {
        let name = "MacAutoKey.FixedDraft.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConfigurationStore(defaults: defaults)
        let model = AppModel(store: store, registerGlobalHotkeys: false)
        defer { model.shutdown() }
        model.config.fixedClickEnabled = true
        model.setNumberText("-200", field: .fixedClickX)
        for raw in ["", "3.5", "abc", "100001"] {
            model.setNumberText(raw, field: .fixedClickY)
            #expect(model.configurationError != nil)
            #expect(model.numberText(.fixedClickY) == raw)
            #expect(try store.load().fixedClickX == -200)
            #expect(try store.load().fixedClickY == 0)
            model.toggleClicker()
            #expect(!model.isActive)
        }
        model.config.fixedClickEnabled = false
        #expect(model.configurationError == nil)
        #expect(model.numberText(.fixedClickY) == "0")
    }
    @Test func pickingNeverStartsInputAndCanBeCancelled() async throws {
        let name = "MacAutoKey.FixedPick.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(store: ConfigurationStore(defaults: defaults), registerGlobalHotkeys: false)
        defer { model.shutdown() }
        model.config.fixedClickEnabled = true
        model.pickClickPosition()
        #expect(model.positionCaptureSeconds == 3 && !model.isActive)
        model.toggleClicker()
        #expect(!model.isActive)
        model.cancelPositionCapture()
        model.pickClickPosition()
        model.config.fixedClickEnabled = false
        try await Task.sleep(for: .milliseconds(40))
        #expect(model.positionCaptureSeconds == nil && !model.isActive)
        #expect(model.config.fixedClickX == 0 && model.config.fixedClickY == 0)
    }
}

@MainActor
struct NumericDraftTests {
    private func withModel(_ body: (AppModel, ConfigurationStore) throws -> Void) throws {
        let name = "MacAutoKey.NumericDraftTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConfigurationStore(defaults: defaults)
        let model = AppModel(store: store, registerGlobalHotkeys: false)
        defer { model.shutdown() }
        try body(model, store)
    }
    @Test func invalidDraftPreservedAndNeverSavedOrRun() throws {
        try withModel { model, store in
            try store.save(model.config)
            for raw in ["", "abc", "10.5", "29", "60001", "999999999999999999999999"] {
                model.setNumberText(raw, field: .clickInterval)
                #expect(model.configurationError != nil)
                #expect(model.numberText(.clickInterval) == raw)
                #expect(model.config.clickIntervalMS == 100)
                model.toggleClicker()
                #expect(!model.clicker.state.isActive)
                model.save()
                #expect(try store.load().clickIntervalMS == 100)
            }
            model.setNumberText("250", field: .clickInterval)
            #expect(model.configurationError == nil)
            #expect(model.config.clickIntervalMS == 250)
            #expect(try store.load().clickIntervalMS == 250)
        }
    }
    @Test func allDraftsMustBeValidAndRemovedActionsClearErrors() throws {
        try withModel { model, _ in
            let delayAction = model.config.actions.first(where: { $0.kind == .delay })
            guard let id = delayAction?.id else { Issue.record("Sample delay action missing"); return }
            model.setNumberText("", field: .keystrokeDelay)
            model.setNumberText("invalid", field: .actionDelay(id))
            model.setNumberText("80", field: .keystrokeDelay)
            #expect(model.configurationError != nil)
            #expect(model.numberText(.actionDelay(id)) == "invalid")
            model.config.actions.removeAll { $0.id == id }
            #expect(model.configurationError == nil)
            #expect(model.config.keystrokeDelayMS == 80)
        }
    }
}


struct MultipleCommandTests {
    @Test func oldSettingsMigrateWithoutLosingSequenceOrShortcut() throws {
        var original = Configuration()
        original.sequenceShortcut = .init(keyCode: 101, option: true, control: true)
        original.keystrokeDelayMS = 123
        original.actions = [.init(kind: .text, text: "existing custom text"), .init(kind: .delay, delayMS: 789)]
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        let commands = try #require(legacy.removeValue(forKey: "commands") as? [[String: Any]])
        legacy["version"] = 1
        legacy["sequenceShortcut"] = commands[0]["shortcut"]
        for key in ["keystrokeDelayMS", "textMode", "actions"] { legacy[key] = commands[0][key] }
        let migrated = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: legacy))
        try migrated.validate()
        #expect(migrated.version == 2)
        #expect(migrated.commands.count == 1)
        #expect(migrated.sequenceShortcut == original.sequenceShortcut)
        #expect(migrated.keystrokeDelayMS == 123)
        #expect(migrated.actions == original.actions)
    }
    @Test func multipleCommandsPersistAndRouteByID() throws {
        var config = Configuration()
        let second = KeyboardCommand(name: "Second", shortcut: .init(keyCode: 101, option: true, control: true),
                                     keystrokeDelayMS: 111, textMode: .unicode, actions: [.init(kind: .text, text: "é")])
        config.commands.append(second)
        try config.validate()
        let reopened = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(reopened == config)
        #expect(reopened.shortcutAssignments.contains { $0.role == .command(second.id) && $0.shortcut == second.shortcut })
        config.commands.reverse()
        #expect(config.shortcutAssignments.contains { $0.role == .command(second.id) && $0.shortcut == second.shortcut })
        config.commands[0].enabled = false
        #expect(!config.shortcutAssignments.contains { $0.role == .command(second.id) })
        #expect(config.shortcutAssignments.contains { $0.role == .emergency })
    }
    @Test func catchesCrossCommandDuplicatesAndGeneratedHotkeys() throws {
        var config = Configuration()
        var second = KeyboardCommand(name: "Second", shortcut: config.sequenceShortcut)
        config.commands.append(second)
        #expect(throws: (any Error).self) { try config.validate() }
        second.shortcut = .init(keyCode: 18)
        config.commands[1] = second
        // The first command types 1, so it would activate the second command.
        #expect(throws: (any Error).self) { try config.validate() }
        config.commands[1].shortcut.control = true
        try config.validate()
        config.commands.removeAll()
        config.clickShortcut = .init(keyCode: 49, command: true)
        #expect(throws: (any Error).self) { try config.validate() }
    }
    @MainActor @Test func duplicateAndDeleteKeepIndependentActionsAndDrafts() throws {
        let name = "MacAutoKey.CommandTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(store: ConfigurationStore(defaults: defaults), registerGlobalHotkeys: false)
        defer { model.shutdown() }
        let first = try #require(model.selectedCommand)
        model.addCommand(duplicate: true)
        let second = try #require(model.selectedCommand)
        #expect(model.config.commands.count == 2)
        #expect(first.id != second.id && first.shortcut != second.shortcut)
        #expect(Set(first.actions.map(\.id)).isDisjoint(with: second.actions.map(\.id)))
        model.setNumberText("bad", field: .commandDelay(second.id))
        model.selectedCommandID = first.id
        #expect(model.numberText(.commandDelay(first.id)) == "60")
        #expect(model.numberText(.commandDelay(second.id)) == "bad")
        model.selectedCommandID = second.id
        model.deleteSelectedCommand()
        #expect(model.configurationError == nil)
        #expect(model.config.commands == [first])
        model.deleteSelectedCommand()
        #expect(model.config.commands.isEmpty && model.selectedCommandID == nil)
        model.addCommand()
        #expect(model.config.commands.count == 1 && model.selectedCommand != nil)
        try model.config.validate()
    }
}

@MainActor
struct CommandRecoveryTests {
    @Test func undoRestoresDeletedCommandAndItsPosition() throws {
        let name = "MacAutoKey.UndoTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(store: ConfigurationStore(defaults: defaults), registerGlobalHotkeys: false)
        defer { model.shutdown() }
        model.addCommand(duplicate: true)
        let original = model.config.commands
        let selected = model.selectedCommandID
        model.deleteSelectedCommand()
        #expect(model.canUndoCommandDeletion)
        model.undoCommandDeletion()
        #expect(model.config.commands == original)
        #expect(model.selectedCommandID == selected)
        #expect(!model.canUndoCommandDeletion)
        #expect(try ConfigurationStore(defaults: defaults).load().commands == original)
    }
    @Test func undoChoosesUnusedShortcutIfOldShortcutWasReassigned() throws {
        let name = "MacAutoKey.UndoTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(store: ConfigurationStore(defaults: defaults), registerGlobalHotkeys: false)
        defer { model.shutdown() }
        let original = try #require(model.selectedCommand)
        model.deleteSelectedCommand()
        model.config.clickShortcut = original.shortcut
        model.undoCommandDeletion()
        let restored = try #require(model.selectedCommand)
        #expect(restored.id == original.id && restored.actions == original.actions)
        #expect(restored.shortcut != original.shortcut)
        #expect(model.configurationError == nil)
        try model.config.validate()
    }
}

@Suite(.serialized)
@MainActor
struct PauseResumeTests {
    @Test func clickerSuspendsAndResumesWithoutDuplicateTasks() async throws {
        let emitter = RecordingEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        engine.start(intervalMS: 40, safety: {})
        try await Task.sleep(for: .milliseconds(95))
        engine.pause()
        #expect(engine.state == .paused)
        let count = emitter.events.count
        try await Task.sleep(for: .milliseconds(160))
        #expect(emitter.events.count == count)
        engine.start(intervalMS: 30, safety: {})
        #expect(engine.state == .paused)
        engine.resume()
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.state == .running)
        #expect(emitter.events.count > count)
    }
    @Test func keyboardContinuesAtExactCharacterAfterPause() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        defer { engine.stop() }
        engine.start(actions: [.init(kind: .text, text: "12345")], delayMS: 40, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(65))
        engine.pause()
        let count = emitter.events.count
        #expect(engine.state == .paused)
        try await Task.sleep(for: .milliseconds(160))
        #expect(emitter.events.count == count)
        engine.resume()
        try await Task.sleep(for: .milliseconds(260))
        #expect(engine.state == .completed)
        #expect(emitter.events == "12345".compactMap { KeyCatalog.stroke(for: $0).map { .key($0) } })
    }
    @Test func pauseFreezesRemainingExplicitDelay() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        defer { engine.stop() }
        engine.start(actions: [.init(kind: .text, text: "1"), .init(kind: .delay, delayMS: 240), .init(kind: .text, text: "2")], delayMS: 20, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(70))
        engine.pause()
        #expect(emitter.events.count == 1)
        try await Task.sleep(for: .milliseconds(270))
        engine.resume()
        try await Task.sleep(for: .milliseconds(95))
        #expect(emitter.events.count == 1)
        try await Task.sleep(for: .milliseconds(180))
        #expect(engine.state == .completed)
        #expect(emitter.events.count == 2)
    }
    @Test func stopWakesPausedTaskAndCannotOverwriteRestart() async throws {
        let emitter = RecordingEmitter()
        let engine = KeyboardAutomationEngine(emitter: emitter)
        defer { engine.stop() }
        engine.start(actions: [.init(kind: .delay, delayMS: 60_000), .init(kind: .text, text: "old")], delayMS: 20, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(35))
        engine.pause()
        try await Task.sleep(for: .milliseconds(35))
        engine.stop()
        engine.resume()
        #expect(engine.state == .stopped)
        engine.start(actions: [.init(kind: .text, text: "9")], delayMS: 20, mode: .physical, safety: {})
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.state == .completed)
        #expect(emitter.events == [.key(.init(code: 25, shift: false))])
    }

}

// These suites publish process-wide workspace notifications and must not overlap.
@Suite(.serialized)
struct WorkspaceNotificationTests {
    @MainActor
    struct SessionSafetyTests {
        @Test func displayWakeDoesNotUnlockInactiveSession() {
            let manager = TargetManager()
            let center = NSWorkspace.shared.notificationCenter
            center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            #expect(!manager.sessionAvailable)
            center.post(name: NSWorkspace.willSleepNotification, object: nil)
            center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            #expect(!manager.sessionAvailable)
            center.post(name: NSWorkspace.didWakeNotification, object: nil)
            #expect(manager.sessionAvailable)
        }
    }

    @MainActor
    struct ResumeSafetyTests {
        @Test func stopCancelsPendingResumeWithoutClobberingNextResume() async throws {
            let suite = "MacAutoKey.ResumeTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = AppModel(store: ConfigurationStore(defaults: defaults), registerGlobalHotkeys: false)
            defer { model.shutdown() }
            // Delay-only runs cannot emit input, even if a cancellation regresses.
            model.keyboard.start(actions: [.init(kind: .delay, delayMS: 60_000)], delayMS: 20, mode: .physical, safety: {})
            try await Task.sleep(for: .milliseconds(25))
            model.pauseActive()
            model.resumeActive(manual: true)
            #expect(model.resumePending)
            model.stopAll()
            #expect(!model.resumePending && model.keyboard.state == .stopped)
            model.keyboard.start(actions: [.init(kind: .delay, delayMS: 60_000)], delayMS: 20, mode: .physical, safety: {})
            model.pauseActive()
            model.resumeActive(manual: true)
            try await Task.sleep(for: .milliseconds(50))
            #expect(model.resumePending && model.keyboard.state == .paused)
            model.keyboard.stop()
            #expect(!model.resumePending && !model.isActive)
            model.keyboard.start(actions: [.init(kind: .delay, delayMS: 60_000)], delayMS: 20, mode: .physical, safety: {})
            model.pauseActive()
            model.resumeActive(manual: true)
            #expect(model.resumePending)
            let center = NSWorkspace.shared.notificationCenter
            center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            #expect(!model.resumePending && !model.isActive)
            center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        }
    }
}
