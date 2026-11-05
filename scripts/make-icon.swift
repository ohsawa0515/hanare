#!/usr/bin/env swift
// Draws the app icon and writes Support/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
// The artwork is licensed under CC BY-NC-SA 4.0 (see LICENSE-ASSETS.md).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let archer = NSImage(contentsOf: root.appending(path: "Sources/Hanare/Resources/Characters/male-hanare.svg"))!

func draw(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Squircle following the macOS icon grid: 824pt of content in a 1024pt canvas.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(srgbRed: 0.10, green: 0.20, blue: 0.36, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.36, blue: 0.56, alpha: 1),
                        NSColor(srgbRed: 0.08, green: 0.15, blue: 0.29, alpha: 1)])!.draw(in: body, angle: -90)

    // A target (mato) on the left, where the arrow flies.
    let center = NSPoint(x: 330 * s, y: 560 * s)
    for (radius, alpha) in [(215.0, 0.16), (150.0, 0.18), (85.0, 0.22)] {
        let r = CGFloat(radius) * s
        NSColor(white: 1, alpha: alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).fill()
    }

    // The archer in ivory.
    let side = 640 * s
    let rect = NSRect(x: 512 * s - side / 2 + 50 * s, y: 512 * s - side / 2 - 5 * s, width: side, height: side)
    let tinted = NSImage(size: rect.size, flipped: false) { bounds in
        archer.draw(in: bounds)
        NSColor(srgbRed: 0.98, green: 0.96, blue: 0.90, alpha: 1).setFill()
        bounds.fill(using: .sourceIn)
        return true
    }
    tinted.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.current = nil
    return rep
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "Hanare.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
let output = root.appending(path: "Support/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try draw(size: 1024).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: "preview.png"))
print("Wrote \(output.path), preview at \(iconset.appending(path: "preview.png").path)")
