// Draws the Haftnotiz app icon (a yellow sticky note with a ticked box and a few lines) and writes
// Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // The note, slightly tilted, with a soft shadow.
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: 512 * s, y: 512 * s)
    context.rotate(by: -0.045)
    context.translateBy(x: -512 * s, y: -512 * s)
    let note = NSRect(x: 150 * s, y: 130 * s, width: 724 * s, height: 760 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 34 * s
    shadow.shadowOffset = NSSize(width: 0, height: -16 * s)
    shadow.set()
    let paper = NSBezierPath(roundedRect: note, xRadius: 56 * s, yRadius: 56 * s)
    NSColor(red: 1.00, green: 0.88, blue: 0.38, alpha: 1).setFill()
    paper.fill()
    NSShadow().set()

    // A slightly darker band at the top, like the adhesive strip.
    NSGraphicsContext.saveGraphicsState()
    paper.addClip()
    NSColor(red: 0.98, green: 0.80, blue: 0.24, alpha: 1).setFill()
    NSRect(x: note.minX, y: note.maxY - 120 * s, width: note.width, height: 120 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    let ink = NSColor(red: 0.42, green: 0.33, blue: 0.08, alpha: 1)
    let accent = NSColor(red: 0.78, green: 0.58, blue: 0.06, alpha: 1)

    // A ticked circle followed by a line, then two plain lines.
    let circle = NSRect(x: 230 * s, y: 560 * s, width: 110 * s, height: 110 * s)
    accent.setFill()
    NSBezierPath(ovalIn: circle).fill()
    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: 258 * s, y: 615 * s))
    tick.line(to: NSPoint(x: 280 * s, y: 591 * s))
    tick.line(to: NSPoint(x: 314 * s, y: 641 * s))
    tick.lineWidth = 16 * s
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    NSColor.white.setStroke()
    tick.stroke()

    ink.withAlphaComponent(0.55).setFill()
    for (x, y, w) in [(380.0, 595.0, 400.0), (230.0, 440.0, 550.0), (230.0, 300.0, 420.0)] {
        NSBezierPath(roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: 42 * s), xRadius: 21 * s, yRadius: 21 * s).fill()
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
        let data = render(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appending(path: name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try render(512).representation(using: .png, properties: [:])!.write(to: root.appending(path: "Resources/AppIcon.png"))
print("Wrote Resources/AppIcon.icns")
