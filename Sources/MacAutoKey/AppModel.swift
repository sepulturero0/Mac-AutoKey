import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var config: Configuration {
        didSet { if ready { configurationChanged(from: oldValue) } }
    }
    @Published private(set) var configurationError: String?
    @Published private(set) var hotkeyWarnings: [String] = []
    @Published private(set) var notice = "Settings save automatically."
    @Published var selectedCommandID: UUID?
    @Published private(set) var lastFailure: String?
    @Published private(set) var lastTrigger = "No automation started yet."
    @Published private(set) var activeCommandName: String?
    @Published private var deletedCommand: (command: KeyboardCommand, index: Int)?
    var canUndoCommandDeletion: Bool { deletedCommand != nil }
    private var runTargetPID: pid_t?
    private var clickerTargetPID: pid_t?
    private var resumeTask: Task<Void, Never>?
    private var resumeGeneration = UUID()
    @Published private(set) var resumePending = false
    @Published private(set) var activeCommandID: UUID?
    @Published private(set) var capturePending = false
    @Published private(set) var positionCaptureSeconds: Int?
    @Published private(set) var referenceCapturePending = false
    private var referencePicker: ScreenRegionPicker?
    let permissions = PermissionManager()
    let targets = TargetManager()
    let imageConditionMonitor = ImageConditionMonitor()
    let clicker: AutoClickerEngine
    let keyboard: KeyboardAutomationEngine
    private let store: ConfigurationStore
    private let hotkeys = GlobalHotkeyManager()
    private var captureTask: Task<Void, Never>?
    private var positionCaptureTask: Task<Void, Never>?
    private var ready = false
    private let registerGlobalHotkeys: Bool
    @Published private var numericDrafts: [NumericField: String] = [:]
    private var numericErrors: [NumericField: String] = [:]
    private var automationRegistrationValid = true
    var statusMenuIsOpen = false
    // Used only by the explicit local verification launcher to constrain its fixture.
    var additionalSafetyCheck: (() throws -> Void)?
    var verificationHotkeyObserver: ((HotkeyRole) -> Void)?
    private var observers: Set<AnyCancellable> = []

    init(store: ConfigurationStore = ConfigurationStore(), registerGlobalHotkeys: Bool = true) {
        self.store = store
        self.registerGlobalHotkeys = registerGlobalHotkeys
        let emitter = NativeEventEmitter()
        clicker = AutoClickerEngine(emitter: emitter)
        keyboard = KeyboardAutomationEngine(emitter: emitter)
        do { config = try store.load() }
        catch {
            config = Configuration()
            notice = "Saved settings could not be loaded: \(error.localizedDescription). Defaults are shown; the stored data is kept until you edit or save."
        }
        selectedCommandID = config.commands.first?.id
        hotkeys.onPress = { [weak self] role in
            self?.verificationHotkeyObserver?(role)
            switch role {
            case .clicker: self?.toggleClicker()
            case .command(let id): self?.runCommand(id: id)
            case .emergency: self?.stopAll()
            }
        }
        clicker.onChange = { [weak self] in self.map { $0.engineChanged(state: $0.clicker.state) } }
        keyboard.onChange = { [weak self] in self.map { $0.engineChanged(state: $0.keyboard.state) } }
        targets.onFocusChanged = { [weak self] in
            guard let self else { return }
            // Workspace can announce activation of the same application more than
            // once. Only a real target change or unavailable session cancels a run.
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let keyboardLostFocus = self.keyboard.state == .running && self.runTargetPID != nil && frontmostPID != self.runTargetPID
            let clickerLostFocus = self.clicker.state.isActive && self.clickerTargetPID != nil && frontmostPID != self.clickerTargetPID
            if self.isActive && !self.targets.sessionAvailable {
                self.stopAll(message: "Stopped: target lost focus or the session became unavailable.")
            } else if keyboardLostFocus {
                if self.clicker.isImageConditionRun {
                    self.keyboard.stop()
                    self.notice = "Keyboard sequence stopped after focus changed. Image monitoring continues."
                } else {
                    self.stopAll(message: "Stopped: target lost focus or the session became unavailable.")
                }
            } else if clickerLostFocus && !self.clicker.isImageConditionRun {
                self.stopAll(message: "Stopped: target lost focus or the session became unavailable.")
            }
            self.permissions.refresh()
        }
        permissions.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        targets.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        imageConditionMonitor.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        hotkeyWarnings = registerGlobalHotkeys ? hotkeys.register(config: config) : []
        ready = true
    }
    private func engineChanged(state: RunState) {
        if case let .failed(message) = state { lastFailure = message }
        if !isActive {
            imageConditionMonitor.reset()
            if resumePending { cancelPendingResume() }
        }
        if !keyboard.state.isActive { runTargetPID = nil }
        if !clicker.state.isActive { clickerTargetPID = nil }
        objectWillChange.send()
    }
    func dismissFailure() { lastFailure = nil }
    var selectedCommand: KeyboardCommand? { config.commands.first { $0.id == selectedCommandID } }
    func updateCommand(_ command: KeyboardCommand) {
        if let index = config.commands.firstIndex(where: { $0.id == command.id }) { config.commands[index] = command }
    }
    func addCommand(duplicate: Bool = false) {
        guard config.commands.count < 50 else { return }
        let assigned = Set([config.clickShortcut, .emergency] + config.commands.map(\.shortcut))
        let candidates = KeyCatalog.functions.dropFirst(8).map { $0.1 } + KeyCatalog.keys.map(\.code)
        let available = candidates.map { Shortcut(keyCode: $0, option: true, control: true) }
            .first { !assigned.contains($0) }
        guard let shortcut = available else { return }
        var command = duplicate ? (selectedCommand ?? KeyboardCommand()) : KeyboardCommand()
        command.id = UUID()
        command.shortcut = shortcut
        command.name = duplicate ? String(command.name.prefix(90)) + " copy" : "Command \(config.commands.count + 1)"
        command.actions = command.actions.map { action in var copy = action; copy.id = UUID(); return copy }
        config.commands.append(command)
        selectedCommandID = command.id
    }
    func deleteSelectedCommand() {
        guard let id = selectedCommandID else { return }
        guard let index = config.commands.firstIndex(where: { $0.id == id }) else { return }
        deletedCommand = (config.commands[index], index)
        config.commands.remove(at: index)
        selectedCommandID = config.commands.first?.id
    }
    func undoCommandDeletion() {
        guard let deleted = deletedCommand, config.commands.count < 50 else { return }
        var restored = deleted.command
        let assigned = Set([config.clickShortcut, .emergency] + config.commands.map(\.shortcut))
        if assigned.contains(restored.shortcut) {
            let candidates = KeyCatalog.functions.map { Shortcut(keyCode: $0.1, option: true, control: true) }
            guard let available = candidates.first(where: { !assigned.contains($0) }) else {
                notice = "Choose a different shortcut before restoring this command."; return
            }
            restored.shortcut = available
        }
        config.commands.insert(restored, at: min(deleted.index, config.commands.count))
        selectedCommandID = restored.id
        deletedCommand = nil
    }
    var isActive: Bool { clicker.state.isActive || keyboard.state.isActive }
    var isPaused: Bool { clicker.state == .paused || keyboard.state == .paused }
    var canPause: Bool { clicker.state == .running || clicker.state == .waitingForImage || clicker.state == .waitingForImageDelay || keyboard.state == .running }
    var activeRunTitle: String {
        clicker.state.isActive ? (config.fixedClickEnabled ? "Auto Clicker · X \(config.fixedClickX), Y \(config.fixedClickY)" : "Auto Clicker") : (activeCommandName ?? "Keyboard command")
    }
    var automationState: RunState {
        if resumePending { return .arming }
        if clicker.state.isActive { return clicker.state }
        if keyboard.state.isActive { return keyboard.state }
        if let error = configurationError ?? lastFailure { return .failed(error) }
        return .stopped
    }
    func commandState(id: UUID) -> RunState { id == activeCommandID ? keyboard.state : .idle }
    var summary: String {
        if resumePending { return "Resuming in 3 seconds — focus the original target" }
        if isPaused { return "\(activeRunTitle) paused" }
        if clicker.state == .arming || keyboard.state == .arming { return "Preparing — focus your target" }
        if clicker.state == .running { return "Auto Clicker running" }
        if clicker.state == .waitingForImageDelay { return "Reference image found; waiting before clicking" }
        if clicker.state == .waitingForImage { return "Waiting for the reference image in the target window" }
        if keyboard.state == .running { return "\(activeCommandName ?? "Keyboard command") · step \(keyboard.currentStep)" }
        if lastFailure != nil || configurationError != nil { return "Needs attention" }
        if keyboard.state == .completed { return "Command completed" }
        return "Ready"
    }
    private func configurationChanged(from old: Configuration) {
        if !config.fixedClickEnabled {
            cancelPositionCapture()
            for field in [NumericField.fixedClickX, .fixedClickY] {
                numericDrafts.removeValue(forKey: field)
                numericErrors.removeValue(forKey: field)
            }
        }
        // Removed or retyped steps must not leave an invisible invalid draft behind.
        for field in Array(numericDrafts.keys) {
            let removed: Bool
            switch field {
            case .actionDelay(let id): removed = !config.commands.flatMap(\.actions).contains { $0.id == id && $0.kind == .delay }
            case .commandDelay(let id): removed = !config.commands.contains { $0.id == id }
            default: removed = false
            }
            if removed { numericDrafts.removeValue(forKey: field); numericErrors.removeValue(forKey: field) }
        }
        if isActive && (config != old || !numericErrors.isEmpty) {
            stopAll(message: "Stopped because settings changed.")
        }
        do {
            if let error = numericErrors.values.sorted().first { throw AutoKeyError.message(error) }
            try store.save(config)
            configurationError = nil
            notice = "All changes saved."
            let registrationChanged = !old.shortcutAssignments.elementsEqual(config.shortcutAssignments) {
                $0.role == $1.role && $0.shortcut == $1.shortcut
            }
            if registrationChanged || !automationRegistrationValid || !oldIsValid(old) {
                if registerGlobalHotkeys { hotkeyWarnings = hotkeys.register(config: config) }
            }
            automationRegistrationValid = true
        } catch {
            configurationError = error.localizedDescription
            notice = "Fix the settings above to save and run."
            if registerGlobalHotkeys { hotkeyWarnings = hotkeys.register(config: config, automationValid: false) }
            automationRegistrationValid = false
        }
    }
    private func oldIsValid(_ config: Configuration) -> Bool { (try? config.validate()) != nil }
    func save() {
        configurationChanged(from: config)
        if configurationError == nil, registerGlobalHotkeys { hotkeyWarnings = hotkeys.register(config: config) }
    }
    func stopAll(message: String = "Stopped all automation.") {
        referencePicker?.cancel()
        imageConditionMonitor.reset()
        cancelPositionCapture()
        lastFailure = nil
        cancelPendingResume()
        clicker.stop()
        keyboard.stop()
        runTargetPID = nil
        clickerTargetPID = nil
        notice = message
    }
    private func cancelPendingResume() {
        resumeGeneration = UUID()
        resumeTask?.cancel()
        resumeTask = nil
        resumePending = false
    }
    func pauseActive() {
        guard canPause else { return }
        clicker.pause()
        keyboard.pause()
        notice = "Paused. Resume continues in the original target; Stop All ends the run."
    }
    func resumeActive(manual: Bool = false) {
        guard isPaused, !resumePending else { return }
        if manual {
            let token = UUID()
            resumeGeneration = token
            resumePending = true
            hideConfigurationForManualRun()
            resumeTask = Task { [weak self] in
                do {
                    try await AutomationTiming.sleep(ms: 3_000)
                    try await AutomationTiming.waitForShortcutRelease()
                    guard let self, self.resumeGeneration == token else { return }
                    self.resumePending = false
                    self.resumeTask = nil
                    self.finishResume()
                } catch {
                    guard let self, self.resumeGeneration == token else { return }
                    self.resumePending = false
                    self.resumeTask = nil
                    if !(error is CancellationError) { self.lastFailure = error.localizedDescription }
                }
            }
        } else { finishResume() }
    }
    private func finishResume() {
        guard isPaused else { return }
        do {
            try preflight()
            if keyboard.state.isActive {
                guard let pid = runTargetPID else { throw AutoKeyError.message("The original target is no longer available. Stop and start a new run.") }
                try targets.requireFocus(pid: pid, config: config)
            } else if clicker.state.isActive {
                guard clickerTargetPID != nil else { throw AutoKeyError.message("The original target is no longer available. Stop and start a new run.") }
                if !clicker.isImageConditionRun, let pid = clickerTargetPID { try targets.requireFocus(pid: pid, config: config) }
            }
            try additionalSafetyCheck?()
            lastFailure = nil
            if keyboard.state.isActive { imageConditionMonitor.reset() }
            clicker.resume()
            keyboard.resume()
            notice = "Resumed in the original target."
        } catch {
            lastFailure = "Resume blocked. Focus the original target and try again. \(error.localizedDescription)"
            notice = lastFailure ?? error.localizedDescription
        }
    }
    #if DEBUG
    func showStatusPreview(paused: Bool) {
        // Opt-in screenshot fixture: a delay-only run can never emit input.
        activeCommandID = selectedCommandID
        activeCommandName = selectedCommand?.name
        keyboard.start(actions: [.init(kind: .delay, delayMS: 60_000)], delayMS: 60, mode: .physical, safety: {})
        if paused { pauseActive() }
    }
    #endif
    private func preflight() throws {
        guard !referenceCapturePending else { throw AutoKeyError.message("Finish or cancel the reference capture before starting automation.") }
        guard positionCaptureSeconds == nil else { throw AutoKeyError.message("Finish or cancel Pick Position before starting automation.") }
        if let configurationError { throw AutoKeyError.message(configurationError) }
        try config.validate()
        try permissions.requireAccess()
    }
    func numberText(_ field: NumericField) -> String {
        if let draft = numericDrafts[field] { return draft }
        switch field {
        case .clickInterval: return String(config.clickIntervalMS)
        case .imageAppearanceDelay: return String(config.imageCondition.appearanceDelayMS)
        case .fixedClickX: return String(config.fixedClickX)
        case .fixedClickY: return String(config.fixedClickY)
        case .keystrokeDelay: return String(config.keystrokeDelayMS)
        case .commandDelay(let id): return String(config.commands.first { $0.id == id }?.keystrokeDelayMS ?? 60)
        case .actionDelay(let id): return String(config.commands.flatMap(\.actions).first(where: { $0.id == id })?.delayMS ?? 500)
        }
    }
    func setNumberText(_ text: String, field: NumericField) {
        guard let number = Int(text.trimmingCharacters(in: .whitespaces)), field.range.contains(number) else {
            numericDrafts[field] = text
            numericErrors[field] = "\(field.label) must be a whole number from \(field.range.lowerBound) to \(field.range.upperBound)."
            configurationChanged(from: config)
            return
        }
        numericDrafts.removeValue(forKey: field)
        numericErrors.removeValue(forKey: field)
        var updated = config
        switch field {
        case .clickInterval: updated.clickIntervalMS = number
        case .imageAppearanceDelay: updated.imageCondition.appearanceDelayMS = number
        case .fixedClickX: updated.fixedClickX = number
        case .fixedClickY: updated.fixedClickY = number
        case .keystrokeDelay: updated.keystrokeDelayMS = number
        case .commandDelay(let id):
            if let index = updated.commands.firstIndex(where: { $0.id == id }) { updated.commands[index].keystrokeDelayMS = number }
        case .actionDelay(let id):
            for index in updated.commands.indices {
                if let position = updated.commands[index].actions.firstIndex(where: { $0.id == id }) {
                    updated.commands[index].actions[position].delayMS = number
                }
            }
        }
        if config != updated { config = updated }
        else { configurationChanged(from: config) }
    }
    // A separate PID is captured per run. Even two allowed apps may not inherit a run.
    private func guards(for snapshot: Configuration, expectedPID: pid_t?, allowFocusLoss: Bool = false,
                        allowPhysicalModifiers: Bool = false, assignTarget: ((pid_t) -> Void)? = nil) -> (prepare: () throws -> Void, safety: () throws -> Void) {
        var pid: pid_t?
        let prepare: () throws -> Void = { [weak self] in
            guard let self else { throw CancellationError() }
            try self.permissions.requireAccess()
            let current = try self.targets.currentPID(config: snapshot)
            if let expectedPID, expectedPID != current {
                throw AutoKeyError.message("Target changed while releasing the shortcut. Focus your target and try again.")
            }
            pid = current
            if let assignTarget { assignTarget(current) } else { self.runTargetPID = current }
            self.notice = "Sending input to \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "the focused application")."
        }
        let safety: () throws -> Void = { [weak self] in
            guard let self, let pid else { throw CancellationError() }
            try self.permissions.requireAccess()
            if !allowFocusLoss { try self.targets.requireFocus(pid: pid, config: snapshot) }
            try self.additionalSafetyCheck?()
            if !allowPhysicalModifiers && AutomationTiming.physicalModifiersHeld {
                throw AutoKeyError.message("Stopped because a modifier key was pressed. Release the keys and run again.")
            }
        }
        return (prepare, safety)
    }
    func toggleClicker(manual: Bool = false) {
        if clicker.state.isActive { clicker.stop(); return }
        guard config.clickerEnabled else { notice = "Enable Auto Clicker first."; return }
        do {
            try preflight()
            let conditionSettings = config.imageCondition
            if conditionSettings.enabled {
                guard conditionSettings.reference != nil else { throw AutoKeyError.message("Choose a reference image before starting the Auto Clicker.") }
                guard permissions.canCaptureScreen else { throw AutoKeyError.message("Allow Screen Recording in the Image condition section before starting.") }
            }
            cancelPendingResume()
            keyboard.stop()
            imageConditionMonitor.reset()
            let expectedPID = manual ? nil : try targets.currentPID(config: config)
            runTargetPID = nil
            clickerTargetPID = nil
            lastFailure = nil
            lastTrigger = "Auto Clicker · \(manual ? "manual start" : config.clickShortcut.label)"
            let checks = guards(for: config, expectedPID: expectedPID,
                                allowFocusLoss: conditionSettings.enabled,
                                allowPhysicalModifiers: conditionSettings.enabled,
                                assignTarget: { [weak self] in self?.clickerTargetPID = $0 })
            if manual { hideConfigurationForManualRun() }
            let point = config.fixedClickEnabled ? CGPoint(x: config.fixedClickX, y: config.fixedClickY) : nil
            let condition: (() async throws -> Bool)? = conditionSettings.enabled ? { [weak self] in
                guard let self, let pid = self.clickerTargetPID else { throw CancellationError() }
                return try await self.imageConditionMonitor.matches(conditionSettings, targetPID: pid)
            } : nil
            clicker.start(intervalMS: config.clickIntervalMS, fixedPosition: point,
                          targetPID: { [weak self] in self?.clickerTargetPID }, manual: manual,
                          shouldClick: { [weak self] in
                              guard let self, self.statusMenuIsOpen == false, !self.keyboard.state.isActive else { return false }
                              guard conditionSettings.enabled else { return true }
                              return NSWorkspace.shared.frontmostApplication?.processIdentifier == self.clickerTargetPID
                          },
                          imageCondition: condition, imageAppearanceDelayMS: conditionSettings.appearanceDelayMS,
                          prepare: checks.prepare, safety: checks.safety)
        } catch { lastFailure = error.localizedDescription; notice = error.localizedDescription }
    }
    func pressClickerStatusButton() {
        guard !keyboard.state.isActive else { return }
        if resumePending {
            cancelPendingResume()
            notice = "Resume cancelled. Auto Clicker is still paused."
            return
        }
        switch clicker.state {
        case .running, .waitingForImage, .waitingForImageDelay: pauseActive()
        case .paused: resumeActive(manual: true)
        default: toggleClicker(manual: true)
        }
    }
    func chooseConditionImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a cropped screenshot of the image or screen state to wait for."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20_000_000 else { throw AutoKeyError.message("Choose a cropped image under 20 MB.") }
                    let reference = try ImageReference.load(data: Data(contentsOf: url), name: url.lastPathComponent)
                    self.config.imageCondition.reference = reference
                    self.lastFailure = nil
                } catch { self.lastFailure = error.localizedDescription }
            }
        }
    }
    func captureConditionArea() {
        guard !referenceCapturePending else { return }
        permissions.refresh()
        guard permissions.canCaptureScreen else {
            lastFailure = "Allow Screen Recording in Image condition before capturing an area."
            return
        }
        stopAll()
        referenceCapturePending = true
        let picker = ScreenRegionPicker()
        referencePicker = picker
        picker.begin { [weak self] result in
            guard let self else { return }
            self.referenceCapturePending = false
            self.referencePicker = nil
            NSApp.unhide(nil)
            NSApp.windows.first(where: { $0.title == "Mac AutoKey" })?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            switch result {
            case .success(let reference):
                if let reference {
                    self.config.imageCondition.reference = reference
                    self.lastFailure = nil
                    self.notice = "Screen area captured. Press Start when you are ready."
                } else { self.notice = "Capture cancelled. Your previous reference image was kept." }
            case .failure(let error): self.lastFailure = error.localizedDescription
            }
        }
    }
    private func hideConfigurationForManualRun() {
        // Restore the app underneath the configuration window before the countdown.
        // The user still has three seconds to position the pointer or change targets.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            NSApp.hide(nil)
        }
    }
    func runSequence(manual: Bool = false) {
        guard let id = config.commands.first?.id else { lastFailure = "Add a command first."; return }
        runCommand(id: id, manual: manual)
    }
    func runCommand(id: UUID, manual: Bool = false) {
        guard !keyboard.state.isActive else { return }
        guard config.keyboardEnabled else { notice = "Enable Keyboard Automation first."; return }
        guard let command = config.commands.first(where: { $0.id == id }), command.enabled else {
            lastFailure = "Enable this command before running it."; return
        }
        do {
            try preflight()
            guard !command.actions.isEmpty else { throw AutoKeyError.message("Add at least one sequence action.") }
            cancelPendingResume()
            if !clicker.isImageConditionRun { clicker.stop() }
            let expectedPID = manual ? nil : try targets.currentPID(config: config)
            if !clicker.isImageConditionRun { runTargetPID = nil }
            lastFailure = nil
            activeCommandName = command.name
            activeCommandID = command.id
            lastTrigger = "\(command.name) · \(manual ? "manual start" : command.shortcut.label)"
            let checks = guards(for: config, expectedPID: expectedPID)
            if manual { hideConfigurationForManualRun() }
            keyboard.start(actions: command.actions, delayMS: command.keystrokeDelayMS, mode: command.textMode,
                           manual: manual, prepare: checks.prepare, safety: checks.safety)
        } catch { lastFailure = error.localizedDescription; notice = error.localizedDescription }
    }
    func addRecentTarget() {
        guard let target = targets.recentExternal else { notice = "Focus the intended target, then return to Mac AutoKey."; return }
        if !config.allowedTargets.contains(where: { $0.id == target.id }) { config.allowedTargets.append(target) }
    }
    func captureTarget() {
        guard !capturePending else { return }
        stopAll()
        capturePending = true
        notice = "Switch to the intended Citrix window now. Target capture in 3 seconds."
        captureTask = Task { [weak self] in
            do {
                try await AutomationTiming.sleep(ms: 3_000)
                guard let self else { return }
                defer { self.capturePending = false; self.captureTask = nil }
                guard let app = NSWorkspace.shared.frontmostApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      let target = TargetManager.metadata(app) else {
                    self.notice = "No external target captured. Try again and switch to the Citrix viewer."
                    return
                }
                if !self.config.allowedTargets.contains(where: { $0.id == target.id }) { self.config.allowedTargets.append(target) }
                self.notice = "Allowed target saved: \(target.name)."
            } catch { self?.capturePending = false }
        }
    }
    func cancelPositionCapture(showNotice: Bool = false) {
        if showNotice, positionCaptureSeconds != nil { notice = "Position pick cancelled. Saved coordinates were kept." }
        positionCaptureTask?.cancel()
        positionCaptureTask = nil
        positionCaptureSeconds = nil
    }
    func pickClickPosition() {
        guard config.fixedClickEnabled, !isActive, positionCaptureSeconds == nil else { return }
        positionCaptureSeconds = 3
        notice = "Move your pointer to the click position. It will be saved in 3 seconds; no click is sent."
        positionCaptureTask = Task { [weak self] in
            do {
                for remaining in [3, 2, 1] {
                    try Task.checkCancellation()
                    self?.positionCaptureSeconds = remaining
                    try await AutomationTiming.sleep(ms: 1_000)
                }
                guard let self, self.config.fixedClickEnabled else { return }
                self.positionCaptureSeconds = nil
                self.positionCaptureTask = nil
                guard let point = CGEvent(source: nil)?.location else {
                    self.notice = "Could not read the pointer position. Try Pick Position again."
                    return
                }
                self.numericDrafts.removeValue(forKey: .fixedClickX)
                self.numericDrafts.removeValue(forKey: .fixedClickY)
                self.numericErrors.removeValue(forKey: .fixedClickX)
                self.numericErrors.removeValue(forKey: .fixedClickY)
                var updated = self.config
                updated.fixedClickX = Int(point.x.rounded())
                updated.fixedClickY = Int(point.y.rounded())
                self.config = updated
                self.notice = "Fixed click position saved: X \(updated.fixedClickX), Y \(updated.fixedClickY)."
            } catch {
                // Cancellation clears state synchronously in cancelPositionCapture.
            }
        }
    }
    func shutdown() {
        stopAll()
        captureTask?.cancel()
        hotkeys.shutdown()
    }
}
