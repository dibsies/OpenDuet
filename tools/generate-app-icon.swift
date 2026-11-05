// Original OpenDuet artwork. Vector paths rendered at each macOS icon resolution.
import AppKit
import Foundation

func pill(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func drawLogo(markOnly: Bool = false) {
    if !markOnly {
        let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 204, yRadius: 204)
        NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.19, alpha: 1),
                   ending: NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.065, alpha: 1))!.draw(in: background, angle: 90)
    }
    let mint = NSColor(calibratedRed: 0.25, green: 0.90, blue: 0.76, alpha: 1)
    let blue = NSColor(calibratedRed: 0.15, green: 0.58, blue: 0.96, alpha: 1)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: 512, y: 512)
    let scale: CGFloat = markOnly ? 1.49 : 1
    context.scaleBy(x: scale, y: scale)
    let circle = NSBezierPath(ovalIn: NSRect(x: -302, y: -302, width: 604, height: 604))
    NSGradient(starting: blue, ending: mint)!.draw(in: circle, angle: 0)
    // Original circular waveform artwork, matching the in-app visual direction.
    let heights: [CGFloat] = [90, 155, 245, 115, 205, 145, 80]
    for (index, height) in heights.enumerated() {
        pill(NSRect(x: CGFloat(index - 3) * 47 - 14, y: -height / 2, width: 28, height: height),
             radius: 14, color: .white)
    }
    NSGraphicsContext.restoreGraphicsState()
}
func bitmap(pixels: Int, markOnly: Bool = false) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels)/1024, y: CGFloat(pixels)/1024)
    drawLogo(markOnly: markOnly)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
guard (2...3).contains(CommandLine.arguments.count) else { fatalError("Pass an iconset output folder") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = bitmap(pixels: pixels)
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

if CommandLine.arguments.count == 3 {
    try bitmap(pixels: 512, markOnly: true).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
