#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/main.swift" <<'SWIFT'
import Foundation
precondition(MeterPacket(bytes: []) == nil)
precondition(MeterPacket(bytes: Array(repeating: 0, count: 19)) == nil)
let silence = MeterPacket(bytes: Array(repeating: 0, count: 20))!
precondition(silence.lanes.count == 10)
precondition(silence.lanes.allSatisfy { $0.decibels == -.infinity && !$0.overloaded })
var bytes = Array(repeating: UInt8(0), count: 20)
bytes[0] = 0x20
bytes[2] = 0x3f
bytes[3] = 0xff
let packet = MeterPacket(bytes: bytes)!
precondition(abs(packet.lanes[0].decibels + 6.020599913) < 0.000001)
precondition(packet.lanes[1].overloaded && packet.lanes[1].decibels == 0)
let lanes = (0..<10).map(Double.init)
precondition(MeterRouting.source(.playback12, lanes: lanes) == [0, 1])
precondition(MeterRouting.source(.playback34, lanes: lanes) == [2, 3])
precondition(MeterRouting.source(.mixer, lanes: lanes) == [6, 7])
precondition(MeterRouting.source(nil, lanes: lanes) == nil)
precondition(MeterRouting.source(.playback12, lanes: []) == nil)
print("Meter decoding and routed source checks passed")
SWIFT
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{MeterPacket,MeterRouting,OutputControlPacket,ControlPacket}.swift "$scratch/main.swift" -o "$scratch/check"
"$scratch/check"
