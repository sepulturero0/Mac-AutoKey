import SwiftUI

private enum WorkspaceTab: Int, CaseIterable {
    case clicker, keyboard
    var title: String { self == .clicker ? "Auto Clicker" : "Keyboard Commands" }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: WorkspaceTab = ProcessInfo.processInfo.arguments.contains("--keyboard-tab") ? .keyboard : .clicker
    @Environment(\.openWindow) private var openWindow
    private var hasAccess: Bool { model.permissions.trusted && model.permissions.canPost }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !hasAccess {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(.orange)
                    Text("Allow Accessibility before starting automation.")
                    Spacer()
                    Button("Set Up Access") { openWindow(id: "settings") }
                }.padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
            }
            if let message = model.configurationError ?? model.lastFailure {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if model.configurationError == nil {
                        Button { model.dismissFailure() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss last error")
                    }
                }.font(.callout).foregroundStyle(.red).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            if !model.hotkeyWarnings.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(model.hotkeyWarnings.joined(separator: "\n")).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.font(.caption).foregroundStyle(.orange).padding(12)
                Divider()
            }
            switch selectedTab {
            case .clicker: ClickerView(model: model)
            case .keyboard: KeyboardWorkspace(model: model)
            }
            Divider()
            runBar
        }
        // Keep related controls within reach on wide and fullscreen windows.
        // The outer frame fills the native window; the workspace keeps a readable width.
        .frame(maxWidth: selectedTab == .clicker ? 940 : 1240, maxHeight: .infinity)
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--settings-panel") { openWindow(id: "settings") }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.permissions.refresh()
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cursorarrow.click").font(.system(size: 24)).foregroundStyle(.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac AutoKey").font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        StatusIndicator(state: model.automationState)
                        if model.isActive { Text(model.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                Spacer()
                Button { openWindow(id: "settings") } label: {
                    Label(hasAccess ? "Access ready" : "Access needed", systemImage: hasAccess ? "checkmark.shield" : "lock.shield")
                        .foregroundStyle(hasAccess ? Color.green : Color.orange)
                }.buttonStyle(.plain).font(.callout).help("Accessibility permissions and app settings")
                Button { openWindow(id: "settings") } label: { Label("Settings", systemImage: "gearshape") }
                    .keyboardShortcut(",", modifiers: .command)
                Button(role: .destructive) { model.stopAll() } label: { Label("Stop All", systemImage: "stop.fill") }
                    .help("Stop every automation · Command + Shift + Escape")
            }
            Picker("Automation feature", selection: $selectedTab) {
                ForEach(WorkspaceTab.allCases, id: \.rawValue) { tab in Text(tab.title).tag(tab) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
        }.padding(20)
    }
    private var selectedCanRun: Bool {
        guard hasAccess, model.configurationError == nil, model.positionCaptureSeconds == nil else { return false }
        if selectedTab == .clicker { return model.config.clickerEnabled }
        guard let command = model.selectedCommand else { return false }
        return model.config.keyboardEnabled && command.enabled && !command.actions.isEmpty
    }
    private var selectedShortcut: String {
        selectedTab == .clicker ? model.config.clickShortcut.label : (model.selectedCommand?.shortcut.label ?? "No command selected")
    }
    private var startHelp: String {
        if model.positionCaptureSeconds != nil { return "Move your pointer to the desired spot. Wait for Pick Position to finish, or cancel it." }
        if !hasAccess { return "Set up Accessibility to send clicks and keystrokes." }
        if model.configurationError != nil { return "Correct the highlighted setting before starting." }
        if selectedTab == .clicker, !model.config.clickerEnabled { return "Enable Auto Clicker to start." }
        if selectedTab == .keyboard {
            if !model.config.keyboardEnabled { return "Enable keyboard shortcuts above the command list." }
            guard let command = model.selectedCommand else { return "Click Add Command to get started." }
            if !command.enabled { return "Enable this command to run it." }
            if command.actions.isEmpty { return "Add at least one step to run this command." }
        }
        return "Start hides this window. You have 3 seconds to focus your target."
    }
    private var runBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isActive ? model.activeRunTitle : (selectedTab == .clicker ? (model.config.fixedClickEnabled ? "Click at X \(model.config.fixedClickX), Y \(model.config.fixedClickY)" : "Click where you point") : (model.selectedCommand?.name ?? "Create your first command")))
                        .font(.headline).lineLimit(1)
                    Text(model.isPaused ? "Resume continues where you paused. Focus the original target within 3 seconds." : (model.isActive ? "Pause from the menu bar · Stop All: ⌘⇧Escape" : startHelp))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if model.isActive {
                    if model.isPaused {
                        Button(model.resumePending ? "Resuming…" : "Resume", systemImage: "play.fill") { model.resumeActive(manual: true) }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.resumePending)
                    }
                    Button("Stop", systemImage: "stop.fill") { model.stopAll() }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                } else {
                    Button(selectedTab == .clicker ? "Start Clicking" : "Run Command", systemImage: "play.fill") {
                        if selectedTab == .clicker { model.toggleClicker(manual: true) }
                        else if let command = model.selectedCommand { model.runCommand(id: command.id, manual: true) }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!selectedCanRun)
                }
            }
            HStack {
                Text(model.notice).lineLimit(1).help(model.notice)
                Spacer()
                Text("Shortcut: \(selectedShortcut)").font(.caption.monospaced())
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 14).background(.bar)
    }
}

struct ShortcutEditor: View {
    let title: String
    @Binding var shortcut: Shortcut
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(shortcut.label).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack(spacing: 14) {
                Picker("Key", selection: $shortcut.keyCode) {
                    ForEach(KeyCatalog.keys) { key in Text(key.name).tag(key.code) }
                }.frame(width: 180)
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                Toggle("Command", isOn: $shortcut.command)
                Toggle("Option", isOn: $shortcut.option)
                Toggle("Control", isOn: $shortcut.control)
                Toggle("Shift", isOn: $shortcut.shift)
            }.toggleStyle(.checkbox)
        }
    }
}

private struct ClickerView: View {
    @ObservedObject var model: AppModel
    private var frequency: String { String(format: "%.1f", 1000.0 / Double(max(30, model.config.clickIntervalMS))) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Automatic left clicks").font(.title3.weight(.semibold))
                        Text(model.config.fixedClickEnabled ? "Repeat clicks at saved coordinates without moving your pointer." : "Repeat clicks at your pointer’s current position.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: $model.config.clickerEnabled).toggleStyle(.switch).fixedSize()
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Fixed click position", isOn: $model.config.fixedClickEnabled)
                            .toggleStyle(.switch).font(.headline)
                        Text("Click only at the saved X/Y location. Your pointer stays free to move.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Text("X")
                            NumericInput(model: model, field: .fixedClickX).frame(width: 90)
                            Text("Y")
                            NumericInput(model: model, field: .fixedClickY).frame(width: 90)
                            Spacer(minLength: 8)
                            Button {
                                if model.positionCaptureSeconds != nil { model.cancelPositionCapture(showNotice: true) }
                                else { model.pickClickPosition() }
                            } label: {
                                Label(model.positionCaptureSeconds.map { "Cancel Pick (\($0))" } ?? "Pick Position (3s)", systemImage: "scope")
                            }.disabled(model.isActive)
                        }.disabled(!model.config.fixedClickEnabled)
                        Text(model.positionCaptureSeconds != nil ? "Move your pointer to the desired spot now. No click will be sent." : "Pick Position saves the pointer location after 3 seconds. Coordinates use screen points from the top-left of the main display; other displays may use negative values.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Time between clicks").font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            NumericInput(model: model, field: .clickInterval).frame(width: 110)
                            Text("milliseconds").foregroundStyle(.secondary)
                            Spacer()
                            Text("About \(frequency) clicks / second").font(.callout).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            ForEach([100, 250, 500, 1000], id: \.self) { interval in
                                Button(interval == 1000 ? "1 second" : "\(interval) ms") { model.setNumberText(String(interval), field: .clickInterval) }
                                    .help("Set interval to \(interval) milliseconds")
                            }
                        }
                        Text("Choose 30 milliseconds to 60 seconds.").font(.caption).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        ShortcutEditor(title: "Start / stop shortcut", shortcut: $model.config.clickShortcut)
                        Text("Press this shortcut in your target app to start. Press it again to stop. For a function key, you may also need Fn.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(12)
                }
                Label(model.config.fixedClickEnabled ? "Switching applications stops the run. Keep the target window at the saved position." : "Switching applications stops the run. Your pointer is never moved automatically.", systemImage: "hand.raised")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.clicker.state != .idle { StateLabel(state: model.clicker.state) }
            }.padding(24).frame(maxWidth: 740, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}

private struct KeyboardWorkspace: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Commands").font(.headline)
                    Spacer()
                    Text("\(model.config.commands.count)").foregroundStyle(.secondary).monospacedDigit()
                }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
                Toggle("Keyboard shortcuts", isOn: $model.config.keyboardEnabled)
                    .toggleStyle(.switch).controlSize(.small).padding(.horizontal, 14).padding(.bottom, 10)
                    .help("Enable or pause all command hotkeys.")
                List(selection: $model.selectedCommandID) {
                    ForEach(model.config.commands) { command in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(model.commandState(id: command.id).statusColor).frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(command.name.isEmpty ? "Untitled command" : command.name).fontWeight(.medium).foregroundStyle(.primary).lineLimit(2)
                            }
                            Text(command.shortcut.label).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if model.commandState(id: command.id).isActive {
                                Text(model.commandState(id: command.id).statusTitle).font(.caption.weight(.medium))
                            }
                            Text("\(command.actions.count == 1 ? "1 step" : "\(command.actions.count) steps")\(command.enabled ? "" : " · Disabled")").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(command.id)
                    }
                }.listStyle(.sidebar)
                Divider()
                VStack(spacing: 10) {
                    Button { model.addCommand() } label: { Label("Add Command", systemImage: "plus").frame(maxWidth: .infinity) }
                        .disabled(model.config.commands.count >= 50)
                    HStack {
                        Button("Duplicate", systemImage: "doc.on.doc") { model.addCommand(duplicate: true) }
                            .disabled(model.selectedCommand == nil || model.config.commands.count >= 50)
                        Spacer(minLength: 0)
                        Button(role: .destructive) { model.deleteSelectedCommand() } label: { Image(systemName: "trash") }
                            .disabled(model.selectedCommand == nil).help("Delete selected command").accessibilityLabel("Delete selected command")
                    }.controlSize(.small)
                    if model.canUndoCommandDeletion {
                        Button("Undo Delete", systemImage: "arrow.uturn.backward") { model.undoCommandDeletion() }.controlSize(.small)
                    }
                }.padding(12)
            }.frame(minWidth: 190, idealWidth: 220, maxWidth: 260)
            if let command = model.selectedCommand {
                CommandEditor(model: model, commandID: command.id).id(command.id)
                    .frame(minWidth: 570, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Your keyboard commands", systemImage: "keyboard")
                } description: {
                    Text("Create a command, give it a shortcut, and add the text or keys it should send.")
                } actions: {
                    Button("Add Command") { model.addCommand() }.buttonStyle(.borderedProminent)
                }.frame(minWidth: 570, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct CommandEditor: View {
    @ObservedObject var model: AppModel
    let commandID: UUID
    @State private var showingTypingOptions = false
    private var command: Binding<KeyboardCommand> {
        Binding(get: { model.config.commands.first { $0.id == commandID } ?? KeyboardCommand.sample }, set: { model.updateCommand($0) })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Command name").font(.headline)
                        TextField("For example, Enter amounts", text: command.name).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Command name")
                    }
                    Spacer(minLength: 12)
                    Toggle("Enabled", isOn: command.enabled).toggleStyle(.switch).fixedSize().padding(.top, 24)
                }
                ShortcutEditor(title: "Run once shortcut", shortcut: command.shortcut)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Steps").font(.headline)
                        Text("Runs once, from top to bottom.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Type Text", systemImage: "text.cursor") { add(.text) }
                        Button("Press Key", systemImage: "keyboard") { add(.key) }
                        Button("Wait / Delay", systemImage: "clock") { add(.delay) }
                    } label: { Label("Add Step", systemImage: "plus") }
                        .fixedSize().disabled(command.wrappedValue.actions.count >= 500)
                }
                if command.wrappedValue.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What should this command do?").fontWeight(.medium)
                        Text("Add text to type, a key to press, or a pause between actions.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Type Text", systemImage: "text.cursor") { add(.text) }
                            Button("Press Key", systemImage: "keyboard") { add(.key) }
                            Button("Wait", systemImage: "clock") { add(.delay) }
                        }
                    }.padding(.vertical, 12)
                }
                VStack(spacing: 12) {
                    ForEach(Array(command.wrappedValue.actions.enumerated()), id: \.element.id) { index, action in
                        ActionRow(model: model, index: index, count: command.wrappedValue.actions.count,
                            action: Binding(get: { command.wrappedValue.actions.first { $0.id == action.id } ?? action }, set: { updated in
                                edit { value in
                                    if let position = value.actions.firstIndex(where: { $0.id == action.id }) { value.actions[position] = updated }
                                }
                            }), move: { offset in
                                edit { value in
                                    guard value.actions.indices.contains(index), value.actions.indices.contains(index + offset) else { return }
                                    value.actions.swapAt(index, index + offset)
                                }
                            }, remove: { edit { $0.actions.removeAll { $0.id == action.id } } })
                    }
                }
                Divider()
                DisclosureGroup("Typing options", isExpanded: $showingTypingOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pause between keys")
                            Spacer()
                            NumericInput(model: model, field: .commandDelay(commandID)).frame(width: 80)
                            Text("ms").foregroundStyle(.secondary)
                        }
                        Picker("Text input", selection: command.textMode) {
                            Text("Standard keyboard (US layout)").tag(TextEntryMode.physical)
                            Text("Unicode text").tag(TextEntryMode.unicode)
                        }
                        Text("Use Unicode for accented or non-Latin text. Remote apps may work better with standard keyboard input and a longer pause.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 10)
                }
                if model.keyboard.state != .idle { StateLabel(state: model.keyboard.state) }
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    private func edit(_ change: (inout KeyboardCommand) -> Void) {
        var value = command.wrappedValue
        change(&value)
        model.updateCommand(value)
    }
    private func add(_ kind: ActionKind) {
        guard command.wrappedValue.actions.count < 500 else { return }
        edit { $0.actions.append(.init(kind: kind)) }
    }
}

private struct ActionRow: View {
    @ObservedObject var model: AppModel
    let index: Int
    let count: Int
    @Binding var action: SequenceAction
    let move: (Int) -> Void
    let remove: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22).padding(.top, 5)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Action for step \(index + 1)", selection: $action.kind) {
                    ForEach(ActionKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                }.labelsHidden().frame(width: 155)
                switch action.kind {
                case .key:
                    Picker("Key for step \(index + 1)", selection: $action.keyCode) {
                        ForEach(KeyCatalog.keys) { key in Text(key.name).tag(key.code) }
                    }.labelsHidden()
                case .text:
                    TextField("Text to type", text: $action.text, axis: .vertical).lineLimit(1...4)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Text for step \(index + 1)")
                case .delay:
                    HStack {
                        NumericInput(model: model, field: .actionDelay(action.id)).frame(maxWidth: 130)
                            .accessibilityLabel("Delay in milliseconds for step \(index + 1)")
                        Text("milliseconds").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Move Up", systemImage: "arrow.up") { move(-1) }.disabled(index == 0)
                Button("Move Down", systemImage: "arrow.down") { move(1) }.disabled(index == count - 1)
                Divider()
                Button("Delete Step", systemImage: "trash", role: .destructive, action: remove)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().frame(width: 26)
                .accessibilityLabel("Options for step \(index + 1)").help("Move or delete step \(index + 1)")
        }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismissWindow(id: "settings") }.keyboardShortcut(.defaultAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.permissions.trusted && model.permissions.canPost ? "Accessibility is ready" : "Allow Accessibility", systemImage: "checkmark.shield")
                            .font(.headline)
                        Text("Mac AutoKey needs Accessibility access to send clicks and keystrokes to other apps.")
                            .foregroundStyle(.secondary)
                        HStack {
                            if !model.permissions.trusted { Button("Request Access") { model.permissions.request() } }
                            Button("Open System Settings") { model.permissions.openSettings() }
                            Button("Check Again") { model.permissions.refresh() }
                        }
                        Text("After an app update, you may need to remove the old Accessibility entry and add this app again.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Target protection").font(.headline)
                        Toggle("Citrix Only — allow selected applications", isOn: $model.config.citrixOnly)
                        Text("Leave this off to use any local app. Every run stops when you switch applications.")
                            .foregroundStyle(.secondary)
                        if model.config.citrixOnly {
                            HStack {
                                Button(model.capturePending ? "Switch to target…" : "Capture Target in 3 Seconds") { model.captureTarget() }.disabled(model.capturePending)
                                if let recent = model.targets.recentExternal {
                                    Button("Allow Recent: \(recent.name)") { model.addRecentTarget() }.lineLimit(1).help(recent.path)
                                }
                            }
                            if model.config.allowedTargets.isEmpty { Text("No allowed apps. Capture your Citrix viewer before starting.").foregroundStyle(.orange) }
                            ForEach(model.config.allowedTargets) { target in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(target.name)
                                        Text(target.bundleID).font(.caption).foregroundStyle(.secondary)
                                    }.help(target.path)
                                    Spacer()
                                    Button("Remove", role: .destructive) { model.config.allowedTargets.removeAll { $0.id == target.id } }
                                        .accessibilityLabel("Remove allowed target \(target.name)")
                                }
                            }
                            Text("Verify the allowed app is your intended Citrix viewer. Remote input still depends on session policies.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    DisclosureGroup("Troubleshooting") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last start: \(model.lastTrigger)")
                            Text("Accessibility: \(model.permissions.trusted ? "allowed" : "denied") · Event posting: \(model.permissions.canPost ? "allowed" : "denied")")
                            Text("App: \(Bundle.main.bundlePath)").textSelection(.enabled)
                            Button("Save and Retry Shortcuts") { model.save() }
                        }.font(.callout).padding(.top, 10)
                    }
                    Text("Mac AutoKey 1.3 · Stop All: ⌘⇧Escape").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(width: 650, height: 560)
    }
}

private struct NumericInput: View {
    @ObservedObject var model: AppModel
    let field: NumericField
    var body: some View {
        TextField(field.label, text: Binding(get: { model.numberText(field) }, set: { model.setNumberText($0, field: field) }))
            .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(field.label)
    }
}

extension RunState {
    var statusTitle: String {
        switch self {
        case .running: "Running"
        case .paused: "Paused"
        case .arming: "Starting"
        case .failed: "Error"
        case .idle, .stopped, .completed: "Stopped"
        }
    }
    var statusColor: Color {
        switch self {
        case .running: .green
        case .paused: .orange
        case .arming: .blue
        case .failed: .red
        case .idle, .stopped, .completed: .gray
        }
    }
}

struct StatusIndicator: View {
    let state: RunState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.statusColor).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(state.statusTitle).font(.caption.weight(.semibold)).foregroundStyle(.primary)
        }.padding(.horizontal, 9).padding(.vertical, 5)
            .background(state.statusColor.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore).accessibilityLabel("Status: \(state.statusTitle)")
    }
}

private struct StateLabel: View {
    let state: RunState
    var body: some View {
        HStack(spacing: 8) {
            StatusIndicator(state: state)
            if state != .running && state != .paused { Text(state.label).font(.callout).foregroundStyle(.secondary) }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
