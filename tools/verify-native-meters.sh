#!/bin/bash
# Offscreen native meter checks: no device, audio stream or window is opened.
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/check.swift" <<'SWIFT'
import AppKit
import Combine
@MainActor final class MeterPresentation: ObservableObject {
    @Published var revision = 0
}
@MainActor final class ConsoleModel {
    let meterPresentation = MeterPresentation()
    var level: Double = -.infinity
    var peak: Double = -.infinity
    var clip = false
    func inputMeter(_ index: Int) -> Double? { level }
    func inputPeak(_ index: Int) -> Double? { peak }
    func inputOver(_ index: Int) -> Bool { clip }
    var playbackMeters: [Double]? { [level, level] }
    var playbackPeaks: [Double]? { [peak, peak] }
    var playbackOvers: [Bool]? { [clip, clip] }
    func outputMeters(headphone: Bool) -> [Double]? { playbackMeters }
    func outputPeaks(headphone: Bool) -> [Double]? { playbackPeaks }
    func outputOvers(headphone: Bool) -> [Bool]? { playbackOvers }
    func outputMeterCaption(headphone: Bool) -> String { "After level/mute · calculated" }
}
@main struct Test {
    @MainActor static func main() {
        let model = ConsoleModel()
        func render(_ kind: NativeMeterReadout.Kind, compact: Bool = false) -> Data {
            let view = MeterReadoutNSView(model: model, kind: kind)
            view.compact = compact
            view.frame = NSRect(x: 0, y: 0, width: 220, height: kind == .input(0) ? 142 : 55)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 220, pixelsHigh: Int(view.frame.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!
        }
        for kind in [NativeMeterReadout.Kind.input(0), .playback, .output(headphone: false), .output(headphone: true)] {
            model.level = -.infinity; model.peak = -.infinity; model.clip = false
            let silent = render(kind)
            model.level = -6; model.peak = -3
            let signal = render(kind)
            precondition(signal != silent)
            model.clip = true
            precondition(render(kind) != signal)
            let clippedCompact = render(kind, compact: true)
            model.level = -.infinity; model.peak = -.infinity; model.clip = false
            precondition(render(kind, compact: true) != clippedCompact)
        }
        let view = MeterReadoutNSView(model: model, kind: .input(0))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 142), styleMask: [], backing: .buffered, defer: false)
        window.contentView = view
        model.level = -12
        precondition(view.refreshFromMeters(force: true))
        precondition(!view.refreshFromMeters(force: true)) // An unchanged visible value must not request another repaint.
        view.configure(model: model, kind: .input(0))
        precondition(!view.refreshFromMeters(force: true)) // Rebinding identical SwiftUI inputs must keep the render cache.
        model.level = -3
        precondition(view.refreshFromMeters(force: true))
        precondition(view.needsDisplay)
        precondition(view.isFlipped && view.wantsLayer)
        precondition(!window.isVisible && !view.refreshFromMeters()) // A hidden window must not paint live frames.
        view.compact = true
        precondition(!view.refreshFromMeters()) // A closed popover must not request frames either.
        withExtendedLifetime(window) {}
        print("Native signal/peak/clip, unchanged-frame and hidden-window checks passed")
    }
}
SWIFT
swiftc -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{NativeMeterReadout,DuetbarMeterScale}.swift "$scratch/check.swift" -o "$scratch/check"
"$scratch/check"
