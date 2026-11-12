import AppKit
import Combine
import SwiftUI

@MainActor
final class ClickerStatusItem: NSObject {
    private let model: AppModel
    private let openWindow: (String) -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var observation: AnyCancellable?

    init(model: AppModel, openWindow: @escaping (String) -> Void) {
        self.model = model
        self.openWindow = openWindow
        super.init()
        item.button?.target = self
        item.button?.action = #selector(press(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refresh()
        observation = model.objectWillChange.sink { [weak self] in
            // Published values are set after objectWillChange fires.
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func performClick() { item.button?.performClick(nil) }

    @objc private func press(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        guard event?.cgEvent?.getIntegerValueField(.eventSourceUserData) != NativeEventEmitter.eventTag else { return }
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(from: sender)
        } else {
            model.pressClickerStatusButton()
        }
    }

    private func refresh() {
        guard let button = item.button else { return }
        let state = model.automationState
        let image: NSImage? = switch state {
        case .running: Self.runningIcon
        case .paused: model.clicker.state == .paused ? Self.clickerPausedIcon : Self.keyboardPausedIcon
        case .arming: Self.startingIcon
        case .failed: Self.errorIcon
        default: Self.readyIcon
        }
        let action: String = if model.keyboard.state.isActive {
            "Keyboard command active"
        } else {
            switch state {
            case .running: "Click to pause"
            case .paused: "Click to resume"
            case .arming: "Click to cancel"
            default: "Click to start Auto Clicker"
            }
        }
        let label = "Mac AutoKey: \(state.statusTitle). \(action). Right-click for options."
        button.image = image
        button.toolTip = model.lastFailure.map { "\(label) \($0)" } ?? label
        button.setAccessibilityLabel(label)
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let status = NSMenuItem(title: model.lastFailure ?? model.summary, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        add("Open Mac AutoKey", #selector(showMainWindow), to: menu)
        add("Settings…", #selector(showSettings), to: menu)
        if model.canPause || model.isPaused {
            let pause = add(model.isPaused ? "Resume" : "Pause", #selector(togglePause), to: menu)
            pause.isEnabled = !model.resumePending
        }
        add("Stop All", #selector(stopAll), to: menu)
        menu.addItem(.separator())
        add("Quit Mac AutoKey", #selector(quit), to: menu)

        // Do not send clicks into the options while the user is choosing one.
        model.statusMenuIsOpen = true
        defer { model.statusMenuIsOpen = false }
        let bottom = button.isFlipped ? button.bounds.maxY : button.bounds.minY
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bottom), in: button)
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    @objc private func showMainWindow() { openWindow("main") }
    @objc private func showSettings() { openWindow("settings") }
    @objc private func togglePause() {
        if model.isPaused { model.resumeActive(manual: model.clicker.state == .paused) }
        else { model.pauseActive() }
    }
    @objc private func stopAll() { model.stopAll() }
    @objc private func quit() { NSApp.terminate(nil) }

    private static let readyIcon = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
    private static let runningIcon = coloredIcon("play.circle.fill", .green)
    private static let clickerPausedIcon = coloredIcon("pause.circle.fill", .red)
    private static let keyboardPausedIcon = coloredIcon("pause.circle.fill", .orange)
    private static let startingIcon = coloredIcon("clock.fill", .blue)
    private static let errorIcon = coloredIcon("exclamationmark.circle.fill", .red)

    private static func coloredIcon(_ symbol: String, _ color: Color) -> NSImage? {
        // Preserve the symbol's original color in the menu bar.
        let renderer = ImageRenderer(content: Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(color)
            .frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }
}
