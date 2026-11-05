#!/bin/bash
# Render synthetic display previews only. Never opens a USB device.
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:?Pass an output folder}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$destination"
cat > "$scratch/preview.swift" <<'SWIFT'
import AppKit
import Foundation
@main struct Preview {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var overview = DeviceDisplayRenderer.Snapshot()
        overview.inputs[0] = .init(mode: "MIC", gain: 24, phantom: true, softLimit: false, phase: false, meter: -14, peak: -10)
        overview.inputs[1] = .init(mode: "INST", gain: 12, phantom: false, meter: -22, peak: -18)
        overview.outputs[0] = .init(level: -32, muted: false, meters: [-18, -22], peaks: [-14, -18])
        overview.outputs[1] = .init(level: -20, muted: false, meters: [-12, -15], peaks: [-10, -12])
        var cases: [(String, DeviceDisplayRenderer.Snapshot)] = [("Overview", overview)]
        for index in 0..<4 {
            var focused = overview; focused.focused = true; focused.selected = index
            if index == 3 {
                focused.outputs[1] = .init(level: -64, muted: true, meters: [-.infinity, -.infinity])
            }
            cases.append((["Mic 1", "Instrument 2", "Main output", "Headphones"][index], focused))
        }
        var setup = DeviceDisplayRenderer.Snapshot(); setup.focused = true
        cases.append(("Unknown output state", setup))
        let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1040, pixelsHigh: 650, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1040, height: 650).fill()
        for (index, entry) in cases.enumerated() {
            let pixels = DeviceDisplayRenderer.render(entry.1)!
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<128 { for x in 0..<160 {
                let offset = (y * 160 + x) * 2
                let value = UInt16(pixels[offset]) << 8 | UInt16(pixels[offset + 1])
                var rgba = [Int((value >> 11) & 31) * 255 / 31, Int((value >> 5) & 63) * 255 / 63, Int(value & 31) * 255 / 31, 255]
                rgba.withUnsafeMutableBufferPointer { bitmap.setPixel($0.baseAddress!, atX: x, y: y) }
            }}
            let name = entry.0.lowercased().replacingOccurrences(of: " ", with: "-")
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            let x = 20 + (index % 3) * 340, y = 350 - (index / 3) * 310
            NSGraphicsContext.current!.imageInterpolation = .none
            NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: 160, height: 128))
                .draw(in: NSRect(x: x, y: y, width: 320, height: 256))
            (entry.0 as NSString).draw(at: NSPoint(x: x, y: y + 269), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        try sheet.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("display-contact-sheet.png"))
    }
}
SWIFT
swiftc -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{DeviceDisplayRenderer,DuetbarMeterScale}.swift "$scratch/preview.swift" -o "$scratch/preview"
"$scratch/preview" "$destination"
