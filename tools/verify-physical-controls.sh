#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/main.swift" <<'SWIFT'
func event(a: Bool = false, b: Bool = false, press: Bool = false, up: UInt8 = 0, down: UInt8 = 0) -> DeviceEvents {
    var bytes = [UInt8](repeating: 0, count: 29)
    bytes.replaceSubrange(0..<6, with: [1, a ? 1 : 0, b ? 1 : 0, press ? 1 : 0, down, up])
    return DeviceEvents(bytes: bytes)!
}
var controller = PhysicalController()
precondition(controller.handle(event(up: 1)) == [.message("Initialize or apply output settings before using the hardware level control.")])
controller.outputs[0] = .init(known: true, level: -64, muted: true, dimmed: false)
precondition(controller.handle(event(up: 4)) == [.output(index: 0, level: -60, muted: true, dimmed: false)])
precondition(controller.handle(event(up: 255)) == [.output(index: 0, level: 0, muted: true, dimmed: false)])
precondition(controller.handle(event(down: 255)) == [.output(index: 0, level: -64, muted: true, dimmed: false)])
controller.selected = .input1
controller.inputs[0] = .init(mode: .instrument, gain: 64)
precondition(controller.handle(event(up: 20)) == [.inputGain(channel: 1, gain: 65, instrument: true)])
controller.inputs[0] = .init(mode: .plus4, gain: nil)
precondition(controller.handle(event(up: 1)).count == 1)
controller.selected = .headphones
_ = controller.handle(event(press: true))
precondition(controller.selected == .input1)
controller.actionA = .muteMain
precondition(controller.handle(event(a: true)) == [.output(index: 0, level: -64, muted: false, dimmed: false)])
controller.actionA = .muteBoth
precondition(controller.handle(event(a: true)).count == 1) // Unknown headphone state must not unmute.
controller.outputs[1] = .init(known: true, level: -50, muted: false, dimmed: false)
precondition(controller.handle(event(a: true)) == [
    .output(index: 0, level: -64, muted: true, dimmed: false),
    .output(index: 1, level: -50, muted: true, dimmed: false)])
controller.actionB = .headphoneMixer
controller.outputs[0].route = .playback34
controller.outputs[1].route = .playback12
precondition(controller.handle(event(b: true)) == [.routes(main: 1, headphones: 2)])
controller.actionA = .clearMeters
precondition(controller.handle(event(a: true)) == [.clearMeters])
controller.invalidate()
precondition(controller.outputs.allSatisfy { !$0.known })
controller.selected = .input1
controller.linkInputs = true
controller.inputs = [.init(mode: .mic, gain: 20), .init(mode: .mic, gain: 20)]
precondition(controller.handle(event(up: 2)) == [
    .inputGain(channel: 1, gain: 22, instrument: false),
    .inputGain(channel: 2, gain: 22, instrument: false)])
controller.inputs[1].mode = .instrument
precondition(controller.handle(event(up: 1)) == [.message("Apply matching input settings before using linked hardware gain.")])
precondition(controller.inputs[0].gain == 22)
precondition(GainLink.shifting([20, 26], by: 3, maximum: 75) == [23, 29])
precondition(GainLink.shifting([70, 75], by: 3, maximum: 75) == [70, 75])
precondition(GainLink.shifting([20, 26], by: -255, maximum: 75) == [0, 6])
precondition(GainLink.shifting([64, 60], by: 255, maximum: 65) == [65, 61])
precondition(GainLink.shifting([76, 20], by: 1, maximum: 75) == nil)
var pair = PhysicalController()
pair.linkInputs = true; pair.selected = .input2
pair.inputs = [.init(mode: .mic, gain: 20), .init(mode: .mic, gain: 26)]
precondition(pair.handle(event(up: 2)) == [.inputGain(channel: 2, gain: 28, instrument: false), .inputGain(channel: 1, gain: 22, instrument: false)])
for target in PhysicalController.Target.allCases {
    var dial = PhysicalController()
    dial.selected = target
    dial.inputs = [.init(mode: .mic, gain: 20), .init(mode: .instrument, gain: 20)]
    dial.outputs = [.init(known: true, level: -30), .init(known: true, level: -30)]
    _ = dial.handle(event(down: 1))
    if target.rawValue < 2 { precondition(dial.inputs[target.rawValue].gain == 19) }
    else { precondition(dial.outputs[target.rawValue - 2].level == -31) }
    _ = dial.handle(event(up: 1))
    if target.rawValue < 2 { precondition(dial.inputs[target.rawValue].gain == 20) }
    else { precondition(dial.outputs[target.rawValue - 2].level == -30) }
}
print("Physical selection, gain limits, touchpads and unknown-state guards passed")
SWIFT
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{ControlPacket,InputControlPacket,OutputControlPacket,DeviceEvents,GainLink,PhysicalController}.swift "$scratch/main.swift" -o "$scratch/check"
"$scratch/check"
