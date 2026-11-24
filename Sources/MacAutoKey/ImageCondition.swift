import AppKit
import ApplicationServices
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Display-local points, measured from the top-left of the captured display.
struct ReferenceScreenArea: Codable, Equatable, Sendable {
    let displayUUID: UUID
    let rect: CGRect

    static func identity(for display: CGDirectDisplayID) -> UUID? {
        guard let id = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return UUID(uuidString: CFUUIDCreateString(nil, id) as String)
    }

    var isValid: Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite) &&
            rect.origin.x >= 0 && rect.origin.y >= 0 &&
            (8...4000).contains(rect.size.width) && (8...4000).contains(rect.size.height)
    }

    func fits(in displaySize: CGSize) -> Bool {
        isValid && CGRect(origin: .zero, size: displaySize).contains(rect)
    }
}

struct ImageReference: Codable, Equatable, Sendable {
    var png: Data
    var name: String
    var widthPoints: Double
    var heightPoints: Double
    var screenArea: ReferenceScreenArea? = nil

    @MainActor
    static func load(data: Data, name: String) throws -> Self {
        guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary), let original = NSImage(data: data),
              original.size.width >= 8, original.size.height >= 8,
              original.size.width <= 4000, original.size.height <= 4000 else {
            throw AutoKeyError.message("Choose a cropped image from 8 to 4,000 screen points, under 20 MB.")
        }
        let bitmap = try ImageRaster(image: image)
        guard bitmap.variance > 36 else {
            throw AutoKeyError.message("This image is too plain to recognize reliably. Crop around text or a distinctive icon.")
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw AutoKeyError.message("Could not read that image. Try a PNG screenshot.")
        }
        return Self(png: png, name: String(name.prefix(150)), widthPoints: original.size.width, heightPoints: original.size.height)
    }
}

enum ImageScanArea: String, CaseIterable, Codable, Sendable {
    case capturedArea
    case entireDisplay

    var title: String {
        switch self {
        case .capturedArea: "Captured Area"
        case .entireDisplay: "Entire Display"
        }
    }

    func sourceRect(for area: ReferenceScreenArea, displaySize: CGSize) -> CGRect? {
        switch self {
        case .capturedArea: area.fits(in: displaySize) ? area.rect : nil
        case .entireDisplay: CGRect(origin: .zero, size: displaySize)
        }
    }
}

struct ImageConditionSettings: Codable, Equatable, Sendable {
    var enabled = false
    var reference: ImageReference?
    var minimumSimilarity = 0.92
    var appearanceDelayMS = 0
    var scanArea = ImageScanArea.capturedArea

    init(enabled: Bool = false, reference: ImageReference? = nil, minimumSimilarity: Double = 0.92,
         appearanceDelayMS: Int = 0, scanArea: ImageScanArea = .capturedArea) {
        self.enabled = enabled
        self.reference = reference
        self.minimumSimilarity = minimumSimilarity
        self.appearanceDelayMS = appearanceDelayMS
        self.scanArea = scanArea
    }

    private enum CodingKeys: String, CodingKey { case enabled, reference, minimumSimilarity, appearanceDelayMS, scanArea }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        reference = try values.decodeIfPresent(ImageReference.self, forKey: .reference)
        minimumSimilarity = try values.decode(Double.self, forKey: .minimumSimilarity)
        appearanceDelayMS = try values.decodeIfPresent(Int.self, forKey: .appearanceDelayMS) ?? 0
        scanArea = try values.decodeIfPresent(ImageScanArea.self, forKey: .scanArea) ?? .capturedArea
    }
}

/// Matching runs on an actor, away from the UI/input loop. Screenshots are never saved.
actor ImageMatcher {
    private struct TemplateKey: Hashable {
        let width: Int
        let height: Int
    }
    private struct CachedSamples {
        let screenWidth: Int
        let coarse: ImageRaster.Samples
        let fine: ImageRaster.Samples
    }

    private var reference: ImageReference?
    private var referenceImage: CGImage?
    private var templates: [TemplateKey: ImageRaster] = [:]
    private var samplePlans: [TemplateKey: CachedSamples] = [:]
    private var fixedTemplate: (raster: ImageRaster, samples: ImageRaster.Samples)?

    private func image(for reference: ImageReference) throws -> CGImage {
        try Task.checkCancellation()
        if self.reference != reference {
            self.reference = reference
            templates.removeAll(keepingCapacity: true)
            samplePlans.removeAll(keepingCapacity: true)
            fixedTemplate = nil
            guard let source = CGImageSourceCreateWithData(reference.png as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                referenceImage = nil
                throw AutoKeyError.message("The reference image could not be read. Choose it again.")
            }
            referenceImage = image
        }
        guard let image = referenceImage else {
            throw AutoKeyError.message("The reference image could not be read. Choose it again.")
        }
        return image
    }

    private func templateForFixedArea(_ reference: ImageReference) throws -> (raster: ImageRaster, samples: ImageRaster.Samples) {
        let image = try image(for: reference)
        if let fixedTemplate { return fixedTemplate }
        let raster = try ImageRaster(image: image, maxDimension: 720)
        let template = (raster, raster.prepareSamples(grid: 14, edges: 64, screenWidth: raster.width))
        fixedTemplate = template
        return template
    }

    func fixedAreaPixelSize(_ reference: ImageReference) throws -> CGSize {
        let raster = try templateForFixedArea(reference).raster
        return CGSize(width: raster.width, height: raster.height)
    }

    func fixedAreaSimilarity(frame: CGImage, reference: ImageReference) throws -> Double {
        let (template, samples) = try templateForFixedArea(reference)
        guard frame.width == template.width, frame.height == template.height else { return 0 }
        let raster = try ImageRaster(image: frame, width: frame.width, height: frame.height)
        // A flat area can be close in color and still be missing the reference pattern.
        guard samples.energy > 100 else { return 0 }
        let pattern = raster.score(x: 0, y: 0, template: template, samples: samples)
        guard pattern > 0 else { return 0 }
        return min(pattern, try raster.alignedSimilarity(to: template))
    }

    func similarity(frame: CGImage, widthPoints: Double, reference: ImageReference) throws -> Double {
        let image = try image(for: reference)
        let raster = try ImageRaster(image: frame, maxDimension: 720)
        let scale = Double(raster.width) / widthPoints
        var best = 0.0
        // Handles common 1x/2x screenshot resolutions and modest UI scaling.
        for factor in [1.0, 0.75, 1.25, 0.5, 2.0] {
            try Task.checkCancellation()
            let width = Int((reference.widthPoints * scale * factor).rounded())
            let height = Int((reference.heightPoints * scale * factor).rounded())
            guard width >= 6, height >= 6, width <= raster.width, height <= raster.height else { continue }
            let key = TemplateKey(width: width, height: height)
            let template: ImageRaster
            if let cached = templates[key] { template = cached }
            else {
                template = try ImageRaster(image: image, width: width, height: height)
                templates[key] = template
            }
            let samples: CachedSamples
            if let cached = samplePlans[key], cached.screenWidth == raster.width {
                samples = cached
            } else {
                samples = CachedSamples(screenWidth: raster.width,
                    coarse: template.prepareSamples(grid: 6, edges: 24, screenWidth: raster.width),
                    fine: template.prepareSamples(grid: 14, edges: 64, screenWidth: raster.width))
                samplePlans[key] = samples
            }
            best = max(best, try raster.find(template, coarse: samples.coarse, fine: samples.fine))
            if best >= 0.995 { return best }
        }
        return best
    }
}

struct ImageRaster: Sendable {
    struct Samples: Sendable {
        let offsets: [Int]
        let referenceOffsets: [Int]
        let values: [Double]
        let sum: Double
        let energy: Double
    }

    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(image: CGImage, maxDimension: Int = 1024) throws {
        let scale = min(1.0, Double(maxDimension) / Double(max(image.width, image.height)))
        try self.init(image: image, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)))
    }
    init(image: CGImage, width: Int, height: Int) throws {
        self.width = width; self.height = height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw AutoKeyError.message("Could not prepare image matching.") }
        pixels = bytes
    }
    private func gray(_ index: Int) -> Double {
        Double(pixels[index]) * 0.299 + Double(pixels[index + 1]) * 0.587 + Double(pixels[index + 2]) * 0.114
    }
    var variance: Double {
        let values = stride(from: 0, to: pixels.count, by: 4).map { gray($0) }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    fileprivate func alignedSimilarity(to template: ImageRaster) throws -> Double {
        // Score every pixel. The lowest local score keeps a large, unchanged
        // background from masking a changed letter or icon elsewhere in the crop.
        let columns = (width + 11) / 12
        let rows = (height + 11) / 12
        var worstSquaredError = 0.0
        for row in 0..<rows {
            try Task.checkCancellation()
            let top = row * height / rows
            let bottom = (row + 1) * height / rows
            for column in 0..<columns {
                let left = column * width / columns
                let right = (column + 1) * width / columns
                var squaredError = 0
                for y in top..<bottom {
                    for x in left..<right {
                        let i = (y * width + x) * 4
                        let red = abs(Int(pixels[i]) - Int(template.pixels[i]))
                        let green = abs(Int(pixels[i + 1]) - Int(template.pixels[i + 1]))
                        let blue = abs(Int(pixels[i + 2]) - Int(template.pixels[i + 2]))
                        let difference = max(red, green, blue)
                        squaredError += difference * difference
                    }
                }
                let area = (bottom - top) * (right - left)
                worstSquaredError = max(worstSquaredError, Double(squaredError) / Double(area))
            }
        }
        return 1 - sqrt(worstSquaredError) / 255
    }
    private func samples(grid: Int, edges: Int) -> [Int] {
        var points = Set<Int>()
        for y in 0..<grid { for x in 0..<grid {
            points.insert((min(height - 1, y * height / grid) * width + min(width - 1, x * width / grid)) * 4)
        } }
        var gradients: [(Int, Double)] = []
        if width > 2 && height > 2 {
            for y in stride(from: 1, to: height - 1, by: 2) { for x in stride(from: 1, to: width - 1, by: 2) {
                let i = (y * width + x) * 4
                gradients.append((i, abs(gray(i + 4) - gray(i - 4)) + abs(gray(i + width * 4) - gray(i - width * 4))))
            } }
        }
        for value in gradients.sorted(by: { $0.1 > $1.1 }).prefix(edges) { points.insert(value.0) }
        return points.sorted()
    }
    func prepareSamples(grid: Int, edges: Int, screenWidth: Int) -> Samples {
        let points = samples(grid: grid, edges: edges)
        let values = points.map { gray($0) }
        let sum = values.reduce(0, +)
        return Samples(offsets: points.map { (($0 / 4 / width) * screenWidth + ($0 / 4 % width)) * 4 },
            referenceOffsets: points, values: values, sum: sum,
            energy: values.reduce(0) { $0 + $1 * $1 } - sum * sum / Double(points.count))
    }
    fileprivate func score(x: Int, y: Int, template: ImageRaster, samples: Samples) -> Double {
        let origin = (y * width + x) * 4
        var sum = 0.0, squared = 0.0, dot = 0.0, colorError = 0.0
        for n in samples.offsets.indices {
            let i = origin + samples.offsets[n], j = samples.referenceOffsets[n]
            let value = gray(i)
            sum += value; squared += value * value; dot += value * samples.values[n]
            colorError += abs(Double(pixels[i]) - Double(template.pixels[j]))
                + abs(Double(pixels[i + 1]) - Double(template.pixels[j + 1]))
                + abs(Double(pixels[i + 2]) - Double(template.pixels[j + 2]))
        }
        let count = Double(samples.offsets.count)
        let energy = squared - sum * sum / count
        guard energy > samples.energy * 0.15 else { return 0 }
        let correlation = (dot - sum * samples.sum / count) / sqrt(energy * samples.energy)
        let color = 1 - colorError / (count * 3 * 255) * 1.5
        return max(0, min(correlation, color))
    }
    func find(_ template: ImageRaster, coarse: Samples, fine: Samples) throws -> Double {
        guard template.width <= width, template.height <= height else { return 0 }
        guard coarse.energy > 100, fine.energy > 100 else { return 0 }
        let maxX = width - template.width, maxY = height - template.height
        var candidates: [(x: Int, y: Int, score: Double)] = []
        for y in stride(from: 0, through: maxY, by: 3) {
            try Task.checkCancellation()
            for x in stride(from: 0, through: maxX, by: 3) {
                let value = score(x: x, y: y, template: template, samples: coarse)
                if candidates.count < 24 { candidates.append((x, y, value)) }
                else if let lowest = candidates.indices.min(by: { candidates[$0].score < candidates[$1].score }), value > candidates[lowest].score {
                    candidates[lowest] = (x, y, value)
                }
            }
        }
        // Include the far edges even when the coarse stride doesn't land there.
        candidates.append((maxX, maxY, score(x: maxX, y: maxY, template: template, samples: coarse)))
        var best = 0.0
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            try Task.checkCancellation()
            for y in max(0, candidate.y - 3)...min(maxY, candidate.y + 3) {
                for x in max(0, candidate.x - 3)...min(maxX, candidate.x + 3) {
                    best = max(best, score(x: x, y: y, template: template, samples: fine))
                    if best >= 0.995 { return best }
                }
            }
        }
        return best
    }
}

@MainActor
final class ImageConditionMonitor: ObservableObject {
    private struct DisplayCapture {
        let displayID: CGDirectDisplayID
        let bounds: CGRect
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    @Published private(set) var similarity: Double?
    private let matcher = ImageMatcher()
    private var lastCheck: ContinuousClock.Instant?
    private var lastResult = false
    private var content: SCShareableContent?
    private var contentTime: ContinuousClock.Instant?
    private var displayCapture: DisplayCapture?
    private var generation = UUID()

    func reset() {
        generation = UUID(); lastCheck = nil; lastResult = false; similarity = nil
        content = nil; contentTime = nil
        displayCapture = nil
    }

    func matches(_ settings: ImageConditionSettings, targetPID: pid_t) async throws -> Bool {
        guard settings.enabled, let reference = settings.reference else {
            throw AutoKeyError.message("Choose a reference image before using the image condition.")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw AutoKeyError.message("Allow Screen Recording for Mac AutoKey to use image conditions, then reopen the app if required.")
        }
        if let lastCheck, lastCheck.duration(to: .now) < .milliseconds(200) { return lastResult }
        let token = generation
        let checkedAt = ContinuousClock.now
        let score: Double
        if let area = reference.screenArea {
            do {
                score = try await displayScore(area, scanArea: settings.scanArea, reference: reference, token: token)
            } catch let error as SCStreamError where Self.canRetry(error) {
                try checkCurrentRun(token)
                // A failed capture cannot authorize a click. Rebuild it on the next poll.
                displayCapture = nil
                content = nil
                score = 0
            }
        } else {
            score = try await windowScore(targetPID: targetPID, reference: reference, token: token)
        }
        try checkCurrentRun(token)
        if similarity != score { similarity = score }
        lastResult = score >= settings.minimumSimilarity
        // Date from capture start, not from the end of a potentially slow match.
        lastCheck = checkedAt
        return lastResult
    }

    private func checkCurrentRun(_ token: UUID) throws {
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
    }

    private func shareableContent(token: UUID) async throws -> SCShareableContent {
        if let content, let contentTime, contentTime.duration(to: .now) <= .seconds(1) { return content }
        let refreshed = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try checkCurrentRun(token)
        content = refreshed
        contentTime = .now
        return refreshed
    }

    private static func canRetry(_ error: SCStreamError) -> Bool {
        switch error.code {
        case .failedToStart, .failedApplicationConnectionInterrupted, .internalError, .noDisplayList, .noCaptureSource:
            true
        default:
            false
        }
    }

    private func displayScore(_ area: ReferenceScreenArea, scanArea: ImageScanArea,
                              reference: ImageReference, token: UUID) async throws -> Double {
        if let capture = displayCapture,
           CGDisplayIsActive(capture.displayID) == 0 || CGDisplayBounds(capture.displayID) != capture.bounds {
            displayCapture = nil
            content = nil
        }
        if displayCapture == nil {
            let displays = try await shareableContent(token: token).displays
            guard let display = displays.first(where: { ReferenceScreenArea.identity(for: $0.displayID) == area.displayUUID }),
                  let rect = scanArea.sourceRect(for: area, displaySize: display.frame.size) else { return 0 }
            let size = switch scanArea {
            case .capturedArea: try await matcher.fixedAreaPixelSize(reference)
            case .entireDisplay: Self.searchPixelSize(for: rect.size)
            }
            try checkCurrentRun(token)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = rect
            configuration.width = Int(size.width)
            configuration.height = Int(size.height)
            configuration.showsCursor = false
            configuration.capturesAudio = false
            displayCapture = DisplayCapture(displayID: display.displayID, bounds: CGDisplayBounds(display.displayID),
                filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration)
            // The capture holds its display filter. Release the full window list.
            content = nil
        }
        guard let capture = displayCapture else { return 0 }
        let frame = try await SCScreenshotManager.captureImage(contentFilter: capture.filter, configuration: capture.configuration)
        try checkCurrentRun(token)
        switch scanArea {
        case .capturedArea:
            return try await matcher.fixedAreaSimilarity(frame: frame, reference: reference)
        case .entireDisplay:
            return try await matcher.similarity(frame: frame, widthPoints: capture.configuration.sourceRect.width, reference: reference)
        }
    }

    private static func searchPixelSize(for size: CGSize) -> CGSize {
        let scale = min(1, 720 / max(size.width, size.height))
        return CGSize(width: max(1, Int(size.width * scale)), height: max(1, Int(size.height * scale)))
    }

    private func windowScore(targetPID: pid_t, reference: ImageReference, token: UUID) async throws -> Double {
        let content = try await shareableContent(token: token)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int) == Int(targetPID) && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let rectangle = CGRect(dictionaryRepresentation: bounds as CFDictionary), !rectangle.isEmpty else {
            return 0
        }
        var best = 0.0
        for display in content.displays {
            let crop = rectangle.intersection(display.frame)
            guard !crop.isNull, crop.width >= 8, crop.height >= 8 else { continue }
            let config = SCStreamConfiguration()
            config.sourceRect = crop.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            let size = Self.searchPixelSize(for: crop.size)
            config.width = Int(size.width); config.height = Int(size.height)
            config.showsCursor = false
            config.capturesAudio = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let frame = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try checkCurrentRun(token)
            best = max(best, try await matcher.similarity(frame: frame, widthPoints: crop.width, reference: reference))
        }
        return best
    }
}
