import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot create icon") }
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.08, green: 0.35, blue: 0.87, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 194, yRadius: 194).fill()
        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 325, y: 770))
        for point in [NSPoint(x: 325, y: 300), NSPoint(x: 447, y: 414), NSPoint(x: 548, y: 210),
                      NSPoint(x: 636, y: 254), NSPoint(x: 536, y: 453), NSPoint(x: 706, y: 477)] {
            cursor.line(to: point)
        }
        cursor.close()
        NSColor.white.setFill()
        cursor.fill()
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let rays = NSBezierPath()
        rays.lineWidth = 26
        rays.lineCapStyle = .round
        for (a,b) in [(NSPoint(x: 560,y: 760),NSPoint(x: 610,y: 815)),
                      (NSPoint(x: 650,y: 665),NSPoint(x: 730,y: 680)),
                      (NSPoint(x: 440,y: 825),NSPoint(x: 450,y: 883))] {
            rays.move(to:a); rays.line(to:b)
        }
        rays.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
