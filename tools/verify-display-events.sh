#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/main.swift" <<'SWIFT'
import Foundation
let clear = OLEDTransfer.fill(x: 0, y: 0, width: 160, height: 128, color: 0)!
precondition(clear.setupBytes == [0x40, 0x23, 0, 0, 0x7f, 0x9f, 2, 0])
precondition(clear.payload == [0, 0])
let corner = OLEDTransfer.fill(x: 159, y: 127, width: 1, height: 1, color: 0x1234)!
precondition(corner.index == 0x9f7f && corner.value == 0x9f7f)
precondition(corner.payload == [0x12, 0x34])
precondition(OLEDTransfer.fill(x: 159, y: 127, width: 2, height: 1, color: 0) == nil)
precondition(OLEDTransfer.fill(x: -1, y: 0, width: 1, height: 1, color: 0) == nil)
precondition(OLEDTransfer.fill(x: 0, y: 0, width: Int.max, height: 1, color: 0) == nil)
var report = [UInt8](repeating: 0, count: 29)
report.replaceSubrange(0..<6, with: [1, 1, 0, 1, 3, 2])
let events = DeviceEvents(bytes: report)!
precondition(events.available && events.touchpadA && !events.touchpadB && events.encoderPressed)
precondition(events.clockwiseSteps == 2 && events.counterclockwiseSteps == 3)
report[0] = 0
let idle = DeviceEvents(bytes: report)!
precondition(!idle.touchpadA && idle.clockwiseSteps == 0 && !idle.encoderPressed)
precondition(DeviceEvents(bytes: Array(report.dropLast())) == nil)
var snapshot = DeviceDisplayRenderer.Snapshot()
snapshot.inputs[0] = .init(mode: "MIC", gain: 24, phantom: true, meter: -12)
snapshot.inputs[1] = .init(mode: "INST", gain: 12, phantom: false, meter: -.infinity)
snapshot.outputs[0] = .init(level: -50, muted: false)
snapshot.outputs[1] = .init(level: -64, muted: true)
let pixels = DeviceDisplayRenderer.render(snapshot)!
precondition(pixels.count == 40960 && pixels.contains { $0 != 0 })
var changedValues = snapshot
changedValues.inputs[0].gain = 60
changedValues.outputs[0].level = -10
precondition(DeviceDisplayRenderer.render(changedValues)! == pixels) // No permanent numbers in overview.
changedValues.focused = true
var oldFocused = snapshot; oldFocused.focused = true
precondition(DeviceDisplayRenderer.render(changedValues)! != DeviceDisplayRenderer.render(oldFocused)!)
for focus in [false, true] {
    var powered = snapshot
    powered.focused = focus; powered.selected = 0
    powered.inputs[0].phantom = false
    let off = DeviceDisplayRenderer.render(powered)!
    powered.inputs[0].phantom = true
    let on = DeviceDisplayRenderer.render(powered)!
    func bluePixels(_ frame: [UInt8]) -> Int {
        stride(from: 0, to: frame.count, by: 2).filter { offset in
            let pixel = UInt16(frame[offset]) << 8 | UInt16(frame[offset + 1])
            let red = Int(pixel >> 11), green = Int((pixel >> 5) & 63), blue = Int(pixel & 31)
            return blue > red * 2 && blue * 2 > green + 10
        }.count
    }
    precondition(bluePixels(on) > bluePixels(off) + 30)
    for output in 0..<2 {
        var signal = snapshot
        signal.focused = focus; signal.selected = output + 2
        let silent = DeviceDisplayRenderer.render(signal)!
        signal.outputs[output].meters = [-6, -12]
        precondition(DeviceDisplayRenderer.render(signal)! != silent)
    }
}
var focused = snapshot
focused.focused = true
var focusedFrames: [[UInt8]] = []
for target in 0..<4 {
    focused.selected = target
    let frame = DeviceDisplayRenderer.render(focused)!
    precondition(frame.count == pixels.count && frame != pixels && !focusedFrames.contains(frame))
    focusedFrames.append(frame)
}
let tiles = OLEDTransfer.frameTiles(pixels)!
precondition(tiles.count == 640 && tiles.allSatisfy { $0.payload.count == 64 })
precondition(tiles[0].setupBytes == [0x40, 0x21, 0, 0, 7, 15, 64, 0])
precondition(tiles[636].value == 0x9078 && tiles[636].index == 0x9f7f)
var reconstructed = [UInt8](repeating: 0, count: pixels.count)
for base in stride(from: 0, to: tiles.count, by: 4) {
    let first = tiles[base]
    let x = Int(first.value >> 8), y = Int(first.value & 255)
    let group = Array(tiles[base..<base + 4])
    precondition(group.dropFirst().allSatisfy { $0.request == 0x22 && $0.index == 0 && $0.value == 0 })
    let bytes = group.flatMap(\.payload)
    for row in 0..<8 {
        let start = (y + row) * 320 + x * 2
        reconstructed.replaceSubrange(start..<start + 32, with: bytes[row * 32..<row * 32 + 32])
    }
}
precondition(reconstructed == pixels)
precondition(OLEDTransfer.frameTiles(Array(pixels.dropLast())) == nil)
if CommandLine.arguments.count == 2 { try Data(pixels).write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
print("Display geometry and event report checks passed")
SWIFT
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{OLEDTransfer,DeviceEvents,DeviceDisplayRenderer,DuetbarMeterScale}.swift "$scratch/main.swift" -o "$scratch/check"
"$scratch/check" "${1:-$scratch/frame.rgb565}"
