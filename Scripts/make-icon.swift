// Draws the Haftnotiz app icon and writes Resources/AppIcon.icns (+ AppIcon.png for the README).
// A full-bleed yellow note on a pad, with the bottom-right corner folded back, a ticked circle and
// two lines. Run: swift Scripts/make-icon.swift
import AppKit

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let c = ns.cgContext
    c.scaleBy(x: size / 1024, y: size / 1024)   // draw in a 1024 grid, y up

    let radius: CGFloat = 186
    let pad = CGRect(x: 100, y: 100, width: 824, height: 824)
    let sheet = CGRect(x: 100, y: 152, width: 824, height: 772)

    // 1. The pad underneath: a golden block whose front edge shows below the top sheet.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0, 0, 0, 0.30))
    c.addPath(roundedRect(pad, radius))
    c.setFillColor(color(0.84, 0.69, 0.25))
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(roundedRect(pad, radius))
    c.clip()
    c.drawLinearGradient(gradient([color(0.80, 0.64, 0.20), color(0.90, 0.78, 0.36), color(0.80, 0.62, 0.16)], [0, 0.6, 1]),
                         start: CGPoint(x: 100, y: 0), end: CGPoint(x: 924, y: 0), options: [])
    c.restoreGState()

    // The corner fold: everything beyond the line A-B is lifted off the sheet and folded back over it.
    let a = CGPoint(x: 924, y: 410)   // on the straight part of the right edge
    let b = CGPoint(x: 630, y: 152)   // on the straight part of the bottom edge
    let beyond = CGMutablePath()
    beyond.addLines(between: [a, b, CGPoint(x: b.x, y: 0), CGPoint(x: 1024, y: 0), CGPoint(x: 1024, y: a.y)])
    beyond.closeSubpath()
    let sheetPath = roundedRect(sheet, radius)
    let corner = sheetPath.intersection(beyond)

    // Mirror the lifted corner across the fold line.
    let angle = atan2(a.y - b.y, a.x - b.x)
    var mirror = CGAffineTransform(translationX: b.x, y: b.y)
        .rotated(by: angle).scaledBy(x: 1, y: -1).rotated(by: -angle)
        .translatedBy(x: -b.x, y: -b.y)
    let flap = corner.copy(using: &mirror)!

    // 2. The top sheet without the lifted corner (the pad shows where it was).
    c.saveGState()
    c.addPath(sheetPath.subtracting(beyond))
    c.clip()
    c.drawLinearGradient(gradient([color(1.00, 0.94, 0.55), color(0.99, 0.91, 0.50), color(0.96, 0.86, 0.45)], [0, 0.55, 1]),
                         start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 152), options: [])
    c.restoreGState()

    // A soft shadow the lifted corner casts onto the pad, along the fold.
    c.saveGState()
    c.addPath(corner)
    c.clip()
    c.drawLinearGradient(gradient([color(0.45, 0.32, 0.02, 0.35), color(0.45, 0.32, 0.02, 0)], [0, 1]),
                         start: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2),
                         end: CGPoint(x: (a.x + b.x) / 2 + 60, y: (a.y + b.y) / 2 - 60), options: [])
    c.restoreGState()

    // 3. The folded-back corner: the paper's underside, lying on the sheet with a shadow.
    c.saveGState()
    c.setShadow(offset: CGSize(width: -4, height: -10), blur: 24, color: color(0.40, 0.28, 0.0, 0.40))
    c.addPath(flap)
    c.setFillColor(color(0.97, 0.87, 0.47))
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(flap)
    c.clip()
    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    let tip = CGPoint(x: 924, y: 152).applying(mirror)
    c.drawLinearGradient(gradient([color(0.90, 0.76, 0.33), color(0.98, 0.89, 0.52), color(1.00, 0.95, 0.66)], [0, 0.45, 1]),
                         start: mid, end: tip, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()

    // 4. The writing: a ticked circle with a line, then two lines.
    let mark = color(0.87, 0.74, 0.30)
    c.setFillColor(mark)
    c.fillEllipse(in: CGRect(x: 236, y: 618, width: 120, height: 120))
    c.setStrokeColor(color(1.00, 0.94, 0.58))
    c.setLineWidth(18)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 268, y: 680))
    c.addLine(to: CGPoint(x: 290, y: 656))
    c.addLine(to: CGPoint(x: 326, y: 708))
    c.strokePath()
    for (x, y, w) in [(400.0, 654.0, 400.0), (236.0, 486.0, 564.0), (236.0, 332.0, 330.0)] {
        c.addPath(roundedRect(CGRect(x: x, y: y, width: w, height: 48), 14))
        c.setFillColor(mark)
        c.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try render(512).representation(using: .png, properties: [:])!.write(to: root.appending(path: "Resources/AppIcon.png"))
print("Wrote Resources/AppIcon.icns")
