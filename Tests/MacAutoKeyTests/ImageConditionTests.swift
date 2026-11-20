import AppKit
import Testing
@testable import MacAutoKey

@MainActor
private func patternImage(width: Int = 64, height: Int = 48) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.95, green: 0.25, blue: 0.1, alpha: 1)); context.fill(CGRect(x: width / 7, y: height / 6, width: width / 4, height: height * 2 / 3))
    context.setFillColor(CGColor(gray: 0.95, alpha: 1)); context.fillEllipse(in: CGRect(x: width / 2, y: height / 4, width: width / 3, height: height / 2))
    context.setFillColor(CGColor(gray: 0.05, alpha: 1)); context.fill(CGRect(x: width / 2, y: height / 3, width: width / 7, height: height / 5))
    return try #require(context.makeImage())
}

@MainActor
struct ScreenCropTests {
    @Test func convertsRetinaSelectionsAndClampsToDisplay() {
        let points = CGSize(width: 800, height: 600), pixels = CGSize(width: 1600, height: 1200)
        #expect(ScreenCropGeometry.pixelRect(selection: CGRect(x: 10, y: 15, width: 40, height: 20), pointSize: points, pixelSize: pixels) == CGRect(x: 20, y: 30, width: 80, height: 40))
        #expect(ScreenCropGeometry.pixelRect(selection: CGRect(x: -20, y: -10, width: 60, height: 40), pointSize: points, pixelSize: pixels) == CGRect(x: 0, y: 0, width: 80, height: 60))
        #expect(ScreenCropGeometry.pixelRect(selection: CGRect(x: 50, y: 35, width: -40, height: -20), pointSize: points, pixelSize: pixels) == CGRect(x: 20, y: 30, width: 80, height: 40))
    }
    @Test func rejectsTinyAndOffscreenSelections() {
        let points = CGSize(width: 800, height: 600), pixels = CGSize(width: 800, height: 600)
        #expect(ScreenCropGeometry.pixelRect(selection: CGRect(x: 10, y: 10, width: 7, height: 20), pointSize: points, pixelSize: pixels) == nil)
        #expect(ScreenCropGeometry.pixelRect(selection: CGRect(x: 900, y: 10, width: 20, height: 20), pointSize: points, pixelSize: pixels) == nil)
        #expect(ScreenCropGeometry.pixelRect(selection: CGRect(x: 10, y: 10, width: 20, height: 20), pointSize: .zero, pixelSize: pixels) == nil)
    }
    @Test func capturedPNGPreservesLogicalScreenSize() throws {
        let image = try patternImage(width: 128, height: 96)
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = CGSize(width: 64, height: 48)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let reference = try ImageReference.load(data: data, name: "Captured area")
        #expect(abs(reference.widthPoints - 64) < 0.1)
        #expect(abs(reference.heightPoints - 48) < 0.1)
    }
}

@MainActor
struct ImageConditionTests {
    private func reference(_ image: CGImage) throws -> ImageReference {
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        return try ImageReference.load(data: png, name: "Reference.png")
    }
    private func frame(_ template: CGImage?, scale: CGFloat = 1, x: CGFloat = 101, y: CGFloat = 87) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8,
            bytesPerRow: 1280, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.15, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        if let template { context.draw(template, in: CGRect(x: x, y: y, width: CGFloat(template.width) * scale, height: CGFloat(template.height) * scale)) }
        return try #require(context.makeImage())
    }
    @Test func findsTranslatedCroppedImageAndRejectsItsDisappearance() async throws {
        let template = try patternImage(), reference = try reference(template)
        let matcher = ImageMatcher()
        for offset in [0, 1, 2] {
            let present = try await matcher.similarity(frame: frame(template, x: CGFloat(100 + offset)), widthPoints: 320, reference: reference)
            #expect(present >= 0.92)
        }
        let absent = try await matcher.similarity(frame: frame(nil), widthPoints: 320, reference: reference)
        #expect(absent < 0.80)
    }
    @Test func supportsCommonScreenshotScalesAndScreenEdges() async throws {
        let template = try patternImage(), reference = try reference(template)
        let matcher = ImageMatcher()
        let doubled = try await matcher.similarity(frame: frame(template, scale: 2, x: 23, y: 31), widthPoints: 320, reference: reference)
        #expect(doubled >= 0.92)
        let edge = try await matcher.similarity(frame: frame(template, x: 256, y: 192), widthPoints: 320, reference: reference)
        #expect(edge >= 0.92)
    }
    @Test func rejectsUnreadableAndBlankReferences() throws {
        #expect(throws: (any Error).self) { try ImageReference.load(data: Data("not an image".utf8), name: "Bad") }
        let blank = try frame(nil)
        #expect(throws: (any Error).self) { try reference(blank) }
    }
    @Test func settingsPersistAndOldFilesKeepConditionOff() throws {
        var configuration = Configuration()
        let template = try patternImage()
        configuration.imageCondition = .init(enabled: true, reference: try reference(template), minimumSimilarity: 0.94)
        let encoded = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(Configuration.self, from: encoded) == configuration)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "imageCondition")
        let migrated = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!migrated.imageCondition.enabled && migrated.commands == configuration.commands)
        configuration.imageCondition.minimumSimilarity = 0.2
        #expect(throws: (any Error).self) { try configuration.validate() }
    }
}

@MainActor
private final class ConditionTestEmitter: InputEmitting {
    var clicks = 0
    var times: [ContinuousClock.Instant] = []
    func click() throws { clicks += 1; times.append(.now) }
    func click(at point: CGPoint, targetPID: pid_t) throws { try click() }
    func press(_ stroke: KeyStroke) throws {}
    func unicode(_ character: Character) throws {}
}

@MainActor
struct ImageConditionEngineTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(predicate(), "Engine did not reach its expected state within two seconds")
    }
    @Test func appearanceDelayAppliesOnceThenUsesClickInterval() async throws {
        let emitter = ConditionTestEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        var firstMatch: ContinuousClock.Instant?
        var delayEntries = 0
        engine.onChange = { if engine.state == .waitingForImageDelay { delayEntries += 1 } }
        engine.start(intervalMS: 50, imageCondition: {
            if firstMatch == nil { firstMatch = .now }
            return true
        }, imageAppearanceDelayMS: 300, safety: {})
        try await waitUntil { engine.state == .waitingForImageDelay }
        #expect(emitter.clicks == 0)
        try await waitUntil { emitter.clicks >= 3 }
        let matchedAt = try #require(firstMatch)
        #expect(matchedAt.duration(to: emitter.times[0]) >= .milliseconds(300))
        #expect(delayEntries == 1)
        for (a, b) in zip(emitter.times, emitter.times.dropFirst()) {
            #expect(a.duration(to: b) >= .milliseconds(50))
        }
    }
    @Test func disappearanceCancelsPendingClickAndRestartsFullDelay() async throws {
        let emitter = ConditionTestEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        var visible = true
        engine.start(intervalMS: 30, imageCondition: { visible }, imageAppearanceDelayMS: 400, safety: {})
        try await waitUntil { engine.state == .waitingForImageDelay }
        visible = false
        try await waitUntil { engine.state == .waitingForImage }
        #expect(emitter.clicks == 0)
        let returned = ContinuousClock.now
        visible = true
        try await waitUntil { emitter.clicks > 0 }
        #expect(returned.duration(to: emitter.times[0]) >= .milliseconds(400))
    }
    @Test func appearanceDelayRespectsPauseAndStop() async throws {
        let emitter = ConditionTestEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        engine.start(intervalMS: 30, imageCondition: { true }, imageAppearanceDelayMS: 600, safety: {})
        try await waitUntil { engine.state == .waitingForImageDelay }
        engine.pause()
        try await Task.sleep(for: .milliseconds(700))
        #expect(engine.state == .paused && emitter.clicks == 0)
        engine.resume()
        try await waitUntil { engine.state == .waitingForImageDelay }
        engine.stop()
        try await Task.sleep(for: .milliseconds(700))
        #expect(engine.state == .stopped && emitter.clicks == 0)
    }
    @Test func appearanceDelayMigratesAndValidates() throws {
        let old = Data(#"{"enabled":true,"minimumSimilarity":0.92}"#.utf8)
        #expect(try JSONDecoder().decode(ImageConditionSettings.self, from: old).appearanceDelayMS == 0)
        var configuration = Configuration()
        configuration.imageCondition.appearanceDelayMS = 2_000
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(configuration)) == configuration)
        for invalid in [-1, 60_001] {
            configuration.imageCondition.appearanceDelayMS = invalid
            #expect(throws: (any Error).self) { try configuration.validate() }
        }
    }
    @Test func watchesForDisappearanceDuringLongClickIntervals() async throws {
        let emitter = ConditionTestEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        var visible = true
        engine.start(intervalMS: 60_000, imageCondition: { visible }, safety: {})
        try await waitUntil { emitter.clicks == 1 }
        #expect(emitter.clicks == 1)
        visible = false
        try await waitUntil { engine.state == .waitingForImage }
        #expect(engine.state == .waitingForImage && emitter.clicks == 1)
        visible = true
        try await waitUntil { engine.state == .running && emitter.clicks == 2 }
        #expect(engine.state == .running && emitter.clicks == 2)
    }
    @Test func resumeDiscardsAMatchCapturedBeforePause() async throws {
        let emitter = ConditionTestEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        var visible = true
        engine.start(intervalMS: 30, imageCondition: {
            let snapshot = visible
            try await Task.sleep(for: .milliseconds(70))
            return snapshot
        }, safety: {})
        try await Task.sleep(for: .milliseconds(25))
        engine.pause()
        visible = false
        try await Task.sleep(for: .milliseconds(100))
        engine.resume()
        try await Task.sleep(for: .milliseconds(140))
        #expect(engine.state == .waitingForImage && emitter.clicks == 0)
    }
    @Test func missingImageWaitsAndReappearanceResumesWithoutOverridingManualPause() async throws {
        let emitter = ConditionTestEmitter()
        let clicker = AutoClickerEngine(emitter: emitter)
        defer { clicker.stop() }
        var visible = false
        clicker.start(intervalMS: 30, imageCondition: { visible }, safety: {})
        try await waitUntil { clicker.state == .waitingForImage }
        #expect(clicker.state == .waitingForImage && emitter.clicks == 0)
        visible = true
        try await waitUntil { clicker.state == .running && emitter.clicks > 0 }
        #expect(clicker.state == .running && emitter.clicks > 0)
        visible = false
        try await waitUntil { clicker.state == .waitingForImage }
        let count = emitter.clicks
        #expect(clicker.state == .waitingForImage)
        clicker.pause()
        visible = true
        try await Task.sleep(for: .milliseconds(260))
        #expect(clicker.state == .paused && emitter.clicks == count)
        clicker.resume()
        try await waitUntil { clicker.state == .running && emitter.clicks > count }
        #expect(clicker.state == .running && emitter.clicks > count)
        clicker.stop()
        let stopped = emitter.clicks
        try await Task.sleep(for: .milliseconds(100))
        #expect(clicker.state == .stopped && emitter.clicks == stopped)
    }
    @Test func stopDuringCaptureCannotEmitLateClick() async throws {
        let emitter = ConditionTestEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        engine.start(intervalMS: 30, imageCondition: {
            // Simulates a capture API that completes after cancellation.
            try? await Task.sleep(for: .milliseconds(180))
            return true
        }, safety: {})
        try await Task.sleep(for: .milliseconds(30))
        engine.stop()
        try await Task.sleep(for: .milliseconds(210))
        #expect(emitter.clicks == 0 && engine.state == .stopped)
    }
    @Test func captureFailureStopsWithoutInput() async throws {
        let emitter = ConditionTestEmitter()
        let engine = AutoClickerEngine(emitter: emitter)
        defer { engine.stop() }
        engine.start(intervalMS: 30, imageCondition: { throw AutoKeyError.message("Screen Recording was revoked") }, safety: {})
        try await Task.sleep(for: .milliseconds(40))
        #expect(emitter.clicks == 0)
        if case .failed = engine.state {} else { Issue.record("Capture failure must stop the clicker") }
    }
}
