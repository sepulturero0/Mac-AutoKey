import AppKit
import CoreGraphics
import ImageIO

/// Explicit development test command. In ordinary launches this does nothing.
/// It targets only a newly launched copy of our disposable AppKit input receiver.
@MainActor
enum LocalVerification {
    private static var started = false
    static func runIfRequested(model: AppModel, statusItem: ClickerStatusItem) {
        let args = ProcessInfo.processInfo.arguments
        guard !started, let index = args.firstIndex(of: "--verify-local-input"), args.indices.contains(index + 2) else { return }
        started = true
        let fixtureURL = URL(fileURLWithPath: args[index + 1]).resolvingSymlinksInPath()
        let reportURL = URL(fileURLWithPath: args[index + 2])
        Task { await run(model: model, statusItem: statusItem, fixtureURL: fixtureURL, reportURL: reportURL) }
    }

    private static func run(model: AppModel, statusItem: ClickerStatusItem, fixtureURL: URL, reportURL: URL) async {
        var report: [String: Any] = ["mode": "explicit local integration", "citrix": "NOT VERIFIED"]
        let receiverOutput = reportURL.deletingPathExtension().appendingPathExtension("receiver.json")
        let markerImageURL = reportURL.deletingPathExtension().appendingPathExtension("marker.png")
        let markerControlURL = reportURL.deletingPathExtension().appendingPathExtension("marker-state")
        var receiver: NSRunningApplication?
        var observedHotkeys: [HotkeyRole: Int] = [:]
        model.verificationHotkeyObserver = { observedHotkeys[$0, default: 0] += 1 }
        let originalPointer = CGEvent(source: nil)?.location
        defer {
            model.stopAll()
            model.additionalSafetyCheck = nil
            model.verificationHotkeyObserver = nil
            receiver?.terminate()
            if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
            UserDefaults(suiteName: "MacAutoKey.LocalVerification")?.removePersistentDomain(forName: "MacAutoKey.LocalVerification")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: reportURL, options: .atomic)
            }
            NSApp.terminate(nil)
        }
        do {
            guard Bundle(url: fixtureURL)?.bundleIdentifier == "com.macautokey.inputreceiver",
                  fixtureURL.lastPathComponent == "Input Receiver.app" else {
                throw AutoKeyError.message("Verification requires the bundled disposable Input Receiver.app fixture.")
            }
            model.permissions.refresh()
            report["accessibilityTrusted"] = model.permissions.trusted
            report["eventPostAllowed"] = model.permissions.canPost
            try model.permissions.requireAccess()
            try await AutomationTiming.sleep(ms: 350)
            model.config = Configuration()
            report["hotkeyRegistrationWarnings"] = model.hotkeyWarnings

            func launch(clickMode: Bool = false, imageMode: Bool = false) async throws -> NSRunningApplication {
                receiver?.terminate()
                try await AutomationTiming.sleep(ms: 300)
                let launch = NSWorkspace.OpenConfiguration()
                launch.createsNewApplicationInstance = true
                launch.activates = true
                launch.arguments = [receiverOutput.path] + (clickMode ? ["--click-test"] : [])
                    + (imageMode ? ["--image-reference", markerImageURL.path, markerControlURL.path] : [])
                    + (ProcessInfo.processInfo.arguments.contains("--physical-hotkeys") ? ["--physical-check"] : [])
                let app = try await NSWorkspace.shared.openApplication(at: fixtureURL, configuration: launch)
                receiver = app
                try await AutomationTiming.sleep(ms: 600)
                guard app.bundleIdentifier == "com.macautokey.inputreceiver",
                      app.bundleURL?.resolvingSymlinksInPath() == fixtureURL,
                      (NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier || ProcessInfo.processInfo.arguments.contains("--verify-screen-crop-only")),
                      let metadata = TargetManager.metadata(app) else {
                    throw AutoKeyError.message("Disposable test receiver did not become the focused target.")
                }
                model.config.allowedTargets = [metadata]
                model.config.citrixOnly = true
                return app
            }
            func result() throws -> [String: Any] {
                try JSONSerialization.jsonObject(with: Data(contentsOf: receiverOutput)) as? [String: Any] ?? [:]
            }
            func waitForSequence() async throws {
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while model.keyboard.state.isActive, ContinuousClock.now < deadline {
                    try await AutomationTiming.sleep(ms: 30)
                }
                guard model.keyboard.state == .completed else {
                    throw AutoKeyError.message("Local sequence did not finish: \(model.keyboard.state.label); \(model.notice)")
                }
            }

            func constrainClicks(to app: NSRunningApplication) throws {
                guard let rectangle = try result()["clickRect"] as? [Double], rectangle.count == 4 else {
                    throw AutoKeyError.message("Fixture did not publish its safe click rectangle.")
                }
                let safeRect = CGRect(x: rectangle[0], y: rectangle[1], width: rectangle[2], height: rectangle[3])
                model.additionalSafetyCheck = {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                          let point = CGEvent(source: nil)?.location, safeRect.contains(point) else {
                        throw AutoKeyError.message("Verification stopped: pointer left the harmless click counter.")
                    }
                }
            }
            func verifyFixedPosition() async throws {
                // Fixed clicks must reach a real button while the hardware pointer
                // is elsewhere, including after it moves during the same run.
                let fixedReceiver = try await launch(clickMode: true)
                let fixedRectValues = try result()["clickRect"] as? [Double] ?? []
                guard fixedRectValues.count == 4 else { throw AutoKeyError.message("Missing fixed-position fixture bounds.") }
                let fixedRect = CGRect(x: fixedRectValues[0], y: fixedRectValues[1], width: fixedRectValues[2], height: fixedRectValues[3])
                model.config.fixedClickEnabled = true
                model.pickClickPosition()
                let captureDeadline = ContinuousClock.now.advanced(by: .seconds(6))
                while model.positionCaptureSeconds != nil, ContinuousClock.now < captureDeadline {
                    try await AutomationTiming.sleep(ms: 50)
                }
                let fixedPoint = CGPoint(x: model.config.fixedClickX, y: model.config.fixedClickY)
                report["fixedPositionPoint"] = [fixedPoint.x, fixedPoint.y]
                report["fixedPositionNotice"] = model.notice
                report["fixedPositionCapturePassed"] = model.positionCaptureSeconds == nil && fixedRect.contains(fixedPoint)
                model.additionalSafetyCheck = {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == fixedReceiver.processIdentifier,
                          fixedRect.contains(fixedPoint) else { throw AutoKeyError.message("Fixed click verification left its disposable target.") }
                }
                let away = CGPoint(x: fixedRect.midX, y: fixedRect.maxY + 100)
                CGWarpMouseCursorPosition(away)
                model.toggleClicker()
                try await AutomationTiming.sleep(ms: 400)
                let firstFixedCount = try result()["clicks"] as? Int ?? 0
                let firstPointerUnmoved = CGEvent(source: nil)?.location == away
                let movedAway = CGPoint(x: away.x + 80, y: away.y + 40)
                CGWarpMouseCursorPosition(movedAway)
                try await AutomationTiming.sleep(ms: 300)
                let secondFixedCount = try result()["clicks"] as? Int ?? 0
                report["fixedPositionClickPassed"] = firstFixedCount >= 2 && secondFixedCount > firstFixedCount && model.clicker.state == .running
                report["fixedPositionPointerUnmovedPassed"] = firstPointerUnmoved && CGEvent(source: nil)?.location == movedAway
                report["fixedPositionClicks"] = secondFixedCount
                report["fixedPositionState"] = model.clicker.state.label
                report["fixedPositionReceivedEvents"] = try result()["mouseEvents"]
                model.pauseActive()
                try await AutomationTiming.sleep(ms: 100)
                let fixedPausedCount = try result()["clicks"] as? Int ?? 0
                try await AutomationTiming.sleep(ms: 180)
                let afterFixedPauseCount = try result()["clicks"] as? Int
                let fixedStayedPaused = model.isPaused && afterFixedPauseCount == fixedPausedCount
                model.resumeActive()
                try await AutomationTiming.sleep(ms: 220)
                model.stopAll()
                try await AutomationTiming.sleep(ms: 100)
                let fixedStoppedCount = try result()["clicks"] as? Int ?? 0
                try await AutomationTiming.sleep(ms: 180)
                let afterFixedStopCount = try result()["clicks"] as? Int
                report["fixedPositionPauseStopPassed"] = fixedStayedPaused && fixedStoppedCount > fixedPausedCount
                    && afterFixedStopCount == fixedStoppedCount && !model.isActive
                do {
                    _ = try NativeEventEmitter.windowAtClickPosition(fixedPoint, targetPID: ProcessInfo.processInfo.processIdentifier)
                    report["fixedPositionWrongTargetBlockedPassed"] = false
                } catch { report["fixedPositionWrongTargetBlockedPassed"] = true }
                model.config.fixedClickX = -99_999
                model.config.fixedClickY = -99_999
                model.toggleClicker()
                try await AutomationTiming.sleep(ms: 150)
                if case .failed = model.clicker.state {
                    report["fixedPositionOffDisplayBlockedPassed"] = (try result()["clicks"] as? Int) == fixedStoppedCount
                } else { report["fixedPositionOffDisplayBlockedPassed"] = false }
                model.stopAll()
                model.config.fixedClickEnabled = false
                model.additionalSafetyCheck = nil

            }
            func waitForPhysical(_ role: HotkeyRole, count: Int) async throws {
                let deadline = ContinuousClock.now.advanced(by: .seconds(600))
                while observedHotkeys[role, default: 0] < count {
                    guard ContinuousClock.now < deadline else { throw AutoKeyError.message("Physical shortcut check timed out; no input was inferred.") }
                    try await AutomationTiming.sleep(ms: 50)
                }
            }
            func prepareMarker() throws -> Data {
                let context = CGContext(data: nil, width: 112, height: 84, bitsPerComponent: 8, bytesPerRow: 448,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 112, height: 84))
                context.setFillColor(CGColor(red: 0.95, green: 0.2, blue: 0.1, alpha: 1))
                context.fill(CGRect(x: 16, y: 14, width: 28, height: 56))
                context.setFillColor(CGColor(gray: 0.95, alpha: 1))
                context.fillEllipse(in: CGRect(x: 56, y: 20, width: 38, height: 42))
                context.setFillColor(CGColor(gray: 0.05, alpha: 1))
                context.fill(CGRect(x: 56, y: 28, width: 16, height: 18))
                let data = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
                try data.write(to: markerImageURL)
                return data
            }
            func verifyImageCondition() async throws {
                report["imageConditionIncluded"] = true
                guard model.permissions.canCaptureScreen else { throw AutoKeyError.message("Screen Recording permission is needed for the image-condition live test.") }
                let data = try prepareMarker()
                func marker(_ visible: Bool) throws { try Data((visible ? "visible" : "hidden").utf8).write(to: markerControlURL, options: .atomic) }
                try marker(false)
                let app = try await launch(clickMode: true, imageMode: true)
                try constrainClicks(to: app)
                let verifyDelay = ProcessInfo.processInfo.arguments.contains("--verify-image-delay")
                model.config.imageCondition = .init(enabled: true, reference: try ImageReference.load(data: data, name: "Test marker"), appearanceDelayMS: verifyDelay ? 700 : 0)
                report["imageDelayIncluded"] = verifyDelay
                if verifyDelay {
                    let rect = try result()["clickRect"] as? [Double] ?? []
                    guard rect.count == 4 else { throw AutoKeyError.message("Missing delay-test counter bounds.") }
                    model.config.fixedClickEnabled = true
                    model.config.fixedClickX = Int(rect[0] + rect[2] / 2)
                    model.config.fixedClickY = Int(rect[1] + rect[3] / 2)
                    model.additionalSafetyCheck = {
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                            throw AutoKeyError.message("Delay verification left its disposable target.")
                        }
                    }
                }
                try await AutomationTiming.sleep(ms: 400)
                model.toggleClicker()
                try await AutomationTiming.sleep(ms: 900)
                let initiallyEmpty = try result()["clicks"] as? Int ?? -1
                report["imageInitiallyWaitsPassed"] = model.clicker.state == .waitingForImage && initiallyEmpty == 0
                func waitFor(_ state: RunState) async throws {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
                    while model.clicker.state != state, ContinuousClock.now < deadline {
                        if !model.clicker.state.isActive { throw AutoKeyError.message("Image test stopped: \(model.clicker.state.label); \(model.notice)") }
                        try await AutomationTiming.sleep(ms: 50)
                    }
                    guard model.clicker.state == state else { throw AutoKeyError.message("Image test did not reach \(state.label); score \(model.imageConditionMonitor.similarity ?? -1)") }
                }
                try marker(true)
                if verifyDelay {
                    try await waitFor(.waitingForImageDelay)
                    report["imageDelayBlocksEarlyClickPassed"] = (try result()["clicks"] as? Int) == 0
                    try marker(false)
                    try await waitFor(.waitingForImage)
                    try await AutomationTiming.sleep(ms: 800)
                    report["imageDelayDisappearanceCancelsPassed"] = (try result()["clicks"] as? Int) == 0
                    let appeared = ProcessInfo.processInfo.systemUptime
                    try marker(true)
                    try await waitFor(.running)
                    try await AutomationTiming.sleep(ms: 150)
                    let times = try result()["clickTimes"] as? [Double] ?? []
                    report["imageDelayFirstClickMS"] = times.first.map { ($0 - appeared) * 1000 }
                    report["imageDelayRestartsPassed"] = times.first.map { $0 - appeared >= 0.7 } ?? false
                }
                try await waitFor(.running)
                try await AutomationTiming.sleep(ms: 400)
                let presentCount = try result()["clicks"] as? Int ?? 0
                report["imageAppearsStartsPassed"] = presentCount > 0
                report["imageMatchedSimilarity"] = model.imageConditionMonitor.similarity
                try marker(false)
                try await waitFor(.waitingForImage)
                try await AutomationTiming.sleep(ms: 150)
                let stoppedCount = try result()["clicks"] as? Int ?? -1
                try await AutomationTiming.sleep(ms: 450)
                let afterMissing = try result()["clicks"] as? Int ?? -2
                report["imageDisappearsStopsPassed"] = stoppedCount == afterMissing && model.clicker.state == .waitingForImage
                try marker(true)
                try await waitFor(.running)
                try await AutomationTiming.sleep(ms: 350)
                let returnedCount = try result()["clicks"] as? Int ?? 0
                report["imageReturnsResumesPassed"] = returnedCount > afterMissing
                model.pauseActive()
                try await AutomationTiming.sleep(ms: 150)
                let pausedCount = try result()["clicks"] as? Int ?? -1
                try marker(false)
                try await AutomationTiming.sleep(ms: 350)
                try marker(true)
                try await AutomationTiming.sleep(ms: 450)
                let afterPause = try result()["clicks"] as? Int ?? -2
                report["imageCannotOverridePausePassed"] = model.isPaused && afterPause == pausedCount
                model.resumeActive()
                try await waitFor(.running)
                try await AutomationTiming.sleep(ms: 350)
                let resumedCount = try result()["clicks"] as? Int ?? 0
                report["imageManualResumePassed"] = resumedCount > pausedCount
                model.stopAll()
                try await AutomationTiming.sleep(ms: 150)
                let finalCount = try result()["clicks"] as? Int ?? -1
                try await AutomationTiming.sleep(ms: 450)
                let afterStop = try result()["clicks"] as? Int ?? -2
                report["imageCannotOverrideStopPassed"] = !model.isActive && afterStop == finalCount
                model.config.imageCondition.enabled = false
                model.additionalSafetyCheck = nil
            }
            if ProcessInfo.processInfo.arguments.contains("--verify-screen-crop-only") {
                report["mode"] = "screen crop integration"
                let data = try prepareMarker()
                try Data("visible".utf8).write(to: markerControlURL, options: .atomic)
                _ = try await launch(clickMode: true, imageMode: true)
                try await AutomationTiming.sleep(ms: 200)
                report["markerRect"] = try result()["markerRect"]
                func capture(_ stage: String) async throws {
                    model.captureConditionArea()
                    let ready: [String: Any] = ["stage": stage, "markerRect": try result()["markerRect"] ?? []]
                    try JSONSerialization.data(withJSONObject: ready).write(to: reportURL.appendingPathExtension("ready"), options: .atomic)
                    let deadline = ContinuousClock.now.advanced(by: .seconds(120))
                    while model.referenceCapturePending, ContinuousClock.now < deadline {
                        try await AutomationTiming.sleep(ms: 50)
                    }
                    guard !model.referenceCapturePending else { throw AutoKeyError.message("Screen crop gesture timed out.") }
                }
                try await capture("drag")
                guard let reference = model.config.imageCondition.reference else {
                    throw AutoKeyError.message("No reference after crop: \(model.lastFailure ?? model.notice)")
                }
                report["screenCropDimensions"] = [reference.widthPoints, reference.heightPoints]
                try reference.png.write(to: reportURL.appendingPathExtension("crop.png"))
                report["screenCropSavedPassed"] = reference.widthPoints == 112 && reference.heightPoints == 84
                let source = CGImageSourceCreateWithData(data as CFData, nil)!
                let original = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                let score = try await ImageMatcher().similarity(frame: original, widthPoints: 112, reference: reference)
                report["screenCropSimilarity"] = score
                report["screenCropMatchesPassed"] = score >= 0.92
                try await AutomationTiming.sleep(ms: 300)
                try await capture("cancel")
                report["screenCropCancelPreservedPassed"] = model.config.imageCondition.reference == reference
                let cropClickCount = try result()["clicks"] as? Int
                report["screenCropDidNotClickPassed"] = !model.isActive && cropClickCount == 0
                report["finished"] = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--verify-image-condition-only") {
                report["mode"] = "image condition integration"
                try await verifyImageCondition()
                report["finished"] = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--verify-fixed-position-only") {
                try await verifyFixedPosition()
                report["finished"] = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--physical-hotkeys") {
                report["mode"] = "human physical hotkey integration"
                NSApp.windows.first(where: { $0.title == "Mac AutoKey" })?.close()
                _ = try await launch()
                try Data("ready".utf8).write(to: reportURL.appendingPathExtension("ready"))
                try await waitForPhysical(.command(model.config.commands[0].id), count: 1)
                try await waitForSequence()
                try await AutomationTiming.sleep(ms: 150)
                let text = try result()["text"] as? String ?? ""
                report["physicalSequenceHotkeyPassed"] = text == "15\n10\n"
                report["physicalSampleText"] = text
                let app = try await launch(clickMode: true)
                try constrainClicks(to: app)
                try await waitForPhysical(.clicker, count: 2)
                try await AutomationTiming.sleep(ms: 100)
                let count = try result()["clicks"] as? Int ?? 0
                report["physicalClickTogglePassed"] = !model.clicker.state.isActive && count >= 3
                report["physicalClickCount"] = count
                try await waitForPhysical(.clicker, count: 3)
                try await waitForPhysical(.emergency, count: 1)
                try await AutomationTiming.sleep(ms: 100)
                report["physicalEmergencyPassed"] = !model.isActive
                report["backgroundWithWindowClosedPassed"] = true
                report["finished"] = true
                return
            }

            _ = try await launch()
            try sendShortcut(model.config.sequenceShortcut)
            try await AutomationTiming.sleep(ms: 150)
            let sequenceHotkeyActivated = observedHotkeys[.command(model.config.commands[0].id), default: 0] > 0
            report["syntheticSequenceHotkeyActivated"] = sequenceHotkeyActivated
            if !sequenceHotkeyActivated { model.runSequence() }
            try await waitForSequence()
            try await AutomationTiming.sleep(ms: 150)
            let sampleText = try result()["text"] as? String ?? ""
            report["physicalSampleText"] = sampleText
            report["physicalSamplePassed"] = sampleText == "15\n10\n"

            // A different command must run its own content even while the first
            // command remains selected in the editor.
            let extra = KeyboardCommand(name: "Second command", shortcut: .init(keyCode: 101, option: true, control: true),
                                        actions: [.init(kind: .text, text: "222"), .init(kind: .key)])
            model.config.commands.append(extra)
            _ = try await launch()
            try sendShortcut(extra.shortcut)
            try await AutomationTiming.sleep(ms: 150)
            try await waitForSequence()
            try await AutomationTiming.sleep(ms: 150)
            let secondText = try result()["text"] as? String
            report["independentCommandHotkeyPassed"] = observedHotkeys[.command(extra.id), default: 0] == 1 && secondText == "222\n"
            report["commandCount"] = model.config.commands.count

            // Reproduce a manual button start with our own configuration focused.
            // Hiding it must restore the disposable editor beneath it.
            let manualTarget = try await launch()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Mac AutoKey" })?.makeKeyAndOrderFront(nil)
            try await AutomationTiming.sleep(ms: 250)
            let configurationWasFocused = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            model.runCommand(id: extra.id, manual: true)
            try await waitForSequence()
            try await AutomationTiming.sleep(ms: 150)
            let manualText = try result()["text"] as? String
            report["manualStartRestoresTargetPassed"] = configurationWasFocused
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == manualTarget.processIdentifier
                && manualText == "222\n"

            _ = try await launch()
            model.config.actions = [
                .init(kind: .text, text: "ab"), .init(kind: .key, keyCode: 123),
                .init(kind: .text, text: "x"), .init(kind: .key, keyCode: 124),
                .init(kind: .key, keyCode: 51), .init(kind: .key, keyCode: 49),
                .init(kind: .key, keyCode: 48), .init(kind: .key)
            ]
            model.runSequence()
            try await waitForSequence()
            try await AutomationTiming.sleep(ms: 150)
            let commonKeysText = try result()["text"] as? String ?? ""
            report["commonKeysText"] = commonKeysText
            report["commonKeysPassed"] = commonKeysText == "ax \t\n"

            _ = try await launch()
            model.config.textMode = .unicode
            model.config.actions = [.init(kind: .text, text: "é界🙂"), .init(kind: .key)]
            model.runSequence()
            try await waitForSequence()
            try await AutomationTiming.sleep(ms: 150)
            let unicodeText = try result()["text"] as? String ?? ""
            report["unicodeText"] = unicodeText
            report["unicodePassed"] = unicodeText == "é界🙂\n"

            NSApp.windows.first(where: { $0.title == "Mac AutoKey" })?.close()
            report["configurationWindowClosed"] = true
            let clickApp = try await launch(clickMode: true)
            try constrainClicks(to: clickApp)
            try sendShortcut(model.config.clickShortcut)
            try await AutomationTiming.sleep(ms: 150)
            report["syntheticClickHotkeyActivated"] = observedHotkeys[.clicker, default: 0] > 0
            if !model.clicker.state.isActive { model.toggleClicker() }
            report["backgroundAfterWindowClosePassed"] = model.clicker.state.isActive
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            try await AutomationTiming.sleep(ms: 150)
            report["sameTargetNotificationContinuesPassed"] = model.clicker.state == .running
            try await AutomationTiming.sleep(ms: 1_000)
            try sendShortcut(model.config.clickShortcut)
            try await AutomationTiming.sleep(ms: 100)
            report["syntheticToggleStopped"] = observedHotkeys[.clicker, default: 0] >= 2 && !model.clicker.state.isActive
            model.stopAll()
            let stoppedCount = try result()["clicks"] as? Int ?? 0
            try await AutomationTiming.sleep(ms: 250)
            report["clickCount"] = stoppedCount
            report["clicksStopped"] = (try result()["clicks"] as? Int) == stoppedCount
            let times = try result()["clickTimes"] as? [Double] ?? []
            let intervals = zip(times, times.dropFirst()).map { ($1 - $0) * 1000 }
            report["clickIntervalsMS"] = intervals
            report["clickTimingPassed"] = times.count >= 5 && intervals.allSatisfy { (80...250).contains($0) }

            statusItem.performClick()
            let clickWasArming = model.clicker.state == .arming
            try await AutomationTiming.sleep(ms: 3_350)
            let startedCount = try result()["clicks"] as? Int ?? 0
            let clickerStartedFromButton = model.clicker.state == .running && startedCount > stoppedCount
            statusItem.performClick()
            let clickWasPaused = model.clicker.state == .paused
            try await AutomationTiming.sleep(ms: 100) // let already-posted Quartz events drain
            let pausedCount = try result()["clicks"] as? Int ?? 0
            try await AutomationTiming.sleep(ms: 220)
            let stayedPaused = (try result()["clicks"] as? Int) == pausedCount
            statusItem.performClick()
            let resumeWasPending = model.resumePending
            try await AutomationTiming.sleep(ms: 3_350)
            let resumedCount = try result()["clicks"] as? Int ?? 0
            report["clickPauseResumePassed"] = clickWasPaused && stayedPaused && resumedCount > pausedCount && model.clicker.state == .running
            report["statusButtonPassed"] = clickWasArming && clickerStartedFromButton && resumeWasPending
            model.stopAll()

            model.toggleClicker()
            try await AutomationTiming.sleep(ms: 250)
            try sendShortcut(.emergency)
            try await AutomationTiming.sleep(ms: 100)
            report["syntheticEmergencyStopped"] = observedHotkeys[.emergency, default: 0] > 0 && !model.isActive
            model.stopAll()
            model.toggleClicker()
            try await AutomationTiming.sleep(ms: 150)
            let runningBeforeFocusLoss = model.clicker.state == .running
            // A closed configuration window may not take focus when asked to
            // activate. Launch a second disposable app instance to prove a real
            // foreground PID change, keeping the original target alive.
            let switchOutput = reportURL.deletingPathExtension().appendingPathExtension("focus-target.json")
            let switchConfig = NSWorkspace.OpenConfiguration()
            switchConfig.createsNewApplicationInstance = true
            switchConfig.activates = true
            switchConfig.arguments = [switchOutput.path]
            let switchTarget = try await NSWorkspace.shared.openApplication(at: fixtureURL, configuration: switchConfig)
            try await AutomationTiming.sleep(ms: 200)
            report["realFocusLossStopped"] = runningBeforeFocusLoss && !model.isActive
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == switchTarget.processIdentifier
            switchTarget.terminate()
            model.stopAll()
            model.additionalSafetyCheck = nil

            try await verifyFixedPosition()

            let pausedReceiver = try await launch()
            model.config.actions = [.init(kind: .text, text: "123456")]
            model.runSequence()
            try await AutomationTiming.sleep(ms: 85)
            model.pauseActive()
            try await AutomationTiming.sleep(ms: 100)
            let pausedText = try result()["text"] as? String ?? ""
            try await AutomationTiming.sleep(ms: 200)
            let textStayedPaused = (try result()["text"] as? String) == pausedText && model.keyboard.state == .paused
            let otherOutput = reportURL.deletingPathExtension().appendingPathExtension("pause-other.json")
            let otherConfig = NSWorkspace.OpenConfiguration()
            otherConfig.createsNewApplicationInstance = true
            otherConfig.activates = true
            otherConfig.arguments = [otherOutput.path]
            let other = try await NSWorkspace.shared.openApplication(at: fixtureURL, configuration: otherConfig)
            try await AutomationTiming.sleep(ms: 250)
            model.resumeActive()
            try await AutomationTiming.sleep(ms: 100)
            report["pausedResumeRejectsWrongTargetPassed"] = model.keyboard.state == .paused && model.lastFailure != nil
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == other.processIdentifier
            other.terminate()
            pausedReceiver.activate(options: [])
            try await AutomationTiming.sleep(ms: 250)
            model.resumeActive()
            try await waitForSequence()
            try await AutomationTiming.sleep(ms: 150)
            let resumedText = try result()["text"] as? String
            report["keyboardPauseResumePassed"] = !pausedText.isEmpty && textStayedPaused && resumedText == "123456"

            _ = try await launch()
            model.config.actions = [.init(kind: .delay, delayMS: 60_000), .init(kind: .text, text: "must not type")]
            model.runSequence()
            try await AutomationTiming.sleep(ms: 60)
            model.pauseActive()
            model.stopAll()
            try await AutomationTiming.sleep(ms: 100)
            let stoppedPausedText = try result()["text"] as? String
            report["stopWhilePausedPassed"] = model.keyboard.state == .stopped && stoppedPausedText == ""

            _ = try await launch()
            model.config.actions = [.init(kind: .delay, delayMS: 60_000), .init(kind: .key)]
            model.runSequence()
            try await AutomationTiming.sleep(ms: 100)
            model.stopAll()
            try await AutomationTiming.sleep(ms: 150)
            let afterDelayText = try result()["text"] as? String
            report["delayCancellationPassed"] = model.keyboard.state == .stopped && afterDelayText == ""

            model.config.actions = [.init(kind: .text, text: String(repeating: "1", count: 100))]
            model.runSequence()
            try await AutomationTiming.sleep(ms: 155)
            model.stopAll()
            try await AutomationTiming.sleep(ms: 100)
            let stoppedText = try result()["text"] as? String ?? ""
            try await AutomationTiming.sleep(ms: 180)
            let finalText = try result()["text"] as? String ?? ""
            report["typingCancellationPassed"] = !stoppedText.isEmpty && stoppedText == finalText && finalText.count < 100
            report["typingCharactersBeforeStop"] = finalText.count
            if ProcessInfo.processInfo.arguments.contains("--verify-image-condition") { try await verifyImageCondition() }
            report["finished"] = true
        } catch { report["error"] = error.localizedDescription }
    }

    private static func sendShortcut(_ shortcut: Shortcut) throws {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
            throw AutoKeyError.message("Could not create local shortcut test events.")
        }
        var flags: CGEventFlags = []
        if shortcut.command { flags.insert(.maskCommand) }
        if shortcut.option { flags.insert(.maskAlternate) }
        if shortcut.control { flags.insert(.maskControl) }
        if shortcut.shift { flags.insert(.maskShift) }
        // Match the technical flags macOS supplies on native navigation and
        // function keys. These are distinct from the user-selected modifiers.
        var technicalFlags: CGEventFlags = []
        if [123, 124, 125, 126].contains(shortcut.keyCode) {
            technicalFlags.formUnion([.maskNumericPad, .maskSecondaryFn])
        } else if KeyCatalog.functions.contains(where: { $0.1 == shortcut.keyCode }) {
            technicalFlags.insert(.maskSecondaryFn)
        }
        flags.formUnion(technicalFlags)
        down.flags = flags
        up.flags = technicalFlags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
