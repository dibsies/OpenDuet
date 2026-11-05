#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/main.swift" <<'SWIFT'
precondition(InputControlPacket.mode(.instrument, channel: .two).payload == 3)
precondition(InputModeSnapshot(output: "Normal USB open: 0\nINPUT_MODES 2 3\n")?.modes == [.mic, .instrument])
precondition(InputModeSnapshot(output: "INPUT_MODES 2\n") == nil)
precondition(InputModeSnapshot(output: "INPUT_MODES 2 4\n") == nil)
precondition(InputModeSnapshot(output: "INPUT_MODES 2 3\nINPUT_MODES 0 0\n") == nil)
precondition(InputControlPacket.mode(.mic, channel: .one).index == 0)
precondition(InputControlPacket.gain(65, mode: .instrument, channel: .two)?.index == 2)
precondition(InputControlPacket.gain(66, mode: .instrument, channel: .two) == nil)
precondition(InputControlPacket.gain(76, mode: .mic, channel: .one) == nil)
precondition(InputControlPacket.phantom(false, channel: .two).payload == 0)
precondition(InputControlPacket.softLimit(true, channel: .two).setupBytes == [0x40, 0x11, 0, 0, 1, 0, 1, 0])
precondition(InputControlPacket.phaseInverted(false, channel: .one).setupBytes == [0x40, 0x13, 0, 0, 0, 0, 1, 0])
precondition(OutputControlPacket.mute(true, output: .headphones).map(\.index) == [3, 4])
precondition(OutputControlPacket.mute(true, output: .main).map(\.payload) == [1, 1])
precondition(OutputControlPacket.mainReference(plus4: true).map(\.request) == [0x18, 0x18])
precondition(OutputControlPacket.mainReference(plus4: false).map(\.index) == [0, 1])
precondition(OutputControlPacket.routing(main: .playback34, headphones: .mixer).payload == 0x21)
for main in OutputControlPacket.RouteSelector.allCases {
    precondition(OutputControlPacket.RouteSelector(sourceID: main.sourceID) == main)
    for headphones in OutputControlPacket.RouteSelector.allCases {
        let packet = OutputControlPacket.routing(main: main, headphones: headphones)
        precondition(packet.payload & 15 == main.rawValue)
        precondition(packet.payload >> 4 == headphones.rawValue)
    }
}
precondition(OutputControlPacket.RouteSelector(sourceID: 0xffffffff) == nil)
precondition(OutputControlPacket.sumToMono(main: false, headphones: true).payload == 0x10)
let packets = OutputControlPacket.attenuation(level: -50.5, dimmed: true, output: .headphones)!
precondition(packets.map(\.index) == [3, 4])
precondition(packets.map(\.payload) == [66, 66])
precondition(OutputControlPacket.attenuation(level: .nan, dimmed: false, output: .main) == nil)
precondition(InputControlPacket.mode(.mic, channel: .one).setupBytes == [0x40, 0x16, 0, 0, 0, 0, 1, 0])
precondition(InputControlPacket.gain(24, mode: .mic, channel: .two)?.setupBytes == [0x40, 0x34, 0, 0, 2, 0, 1, 0])
precondition(InputControlPacket.phantom(false, channel: .two).setupBytes == [0x40, 0x15, 0, 0, 1, 0, 1, 0])
precondition(packets.map(\.setupBytes) == [
    [0x40, 0x33, 0, 0, 3, 0, 1, 0],
    [0x40, 0x33, 0, 0, 4, 0, 1, 0]
])
print("Swift control encoder checks passed")
SWIFT
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{ControlPacket,InputControlPacket,InputModeSnapshot,OutputControlPacket}.swift "$scratch/main.swift" -o "$scratch/check"
"$scratch/check"
