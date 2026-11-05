#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/main.swift" <<'SWIFT'
import Foundation
func close(_ a: Double, _ b: Double) { precondition(abs(a - b) < 0.00001) }
var meter = MeterBallistics(count: 1)
meter.update([-24], at: 0); close(meter.levels[0], -24)
meter.update([-6], at: 0.01); close(meter.levels[0], -6)
meter.update([-60], at: 0.11); close(meter.levels[0], -8); close(meter.peaks[0], -6)
meter.update([-60], at: 1.11); close(meter.levels[0], -28)
meter.update([-60], at: 2.11); close(meter.levels[0], -48); close(meter.peaks[0], -26)
meter.update([0], at: 3); precondition(meter.overs[0])
meter.update([-60], at: 3.5); precondition(meter.overs[0])
meter.update([-60], at: 5.1); precondition(!meter.overs[0])
meter.update([0], at: 5.2, silent: [0]); precondition(meter.levels[0] == -.infinity && meter.peaks[0] == -.infinity && !meter.overs[0])
var infinite = MeterBallistics(count: 1); infinite.peakHold = .infinity
infinite.update([-6], at: 0); infinite.update([-20], at: 100); close(infinite.peaks[0], -6)
infinite.clearHolds(); precondition(infinite.peaks[0] == -.infinity)
infinite.update([-20], at: 100.1); close(infinite.peaks[0], -20)
infinite.update([.nan], at: 101); precondition(!infinite.levels[0].isNaN)
precondition(MeterRouting.output([-6, -12], level: -20, dimmed: false, muted: false, mono: false) == [-26, -32])
precondition(MeterRouting.output([-6, -12], level: -20, dimmed: true, muted: false, mono: false) == [-41, -47])
precondition(MeterRouting.output([-6, -12], level: -20, dimmed: false, muted: true, mono: false) == [-.infinity, -.infinity])
precondition(MeterRouting.output([-6, -12], level: -20, dimmed: false, muted: false, mono: true) == [-26, -26])
precondition(MeterRouting.output(nil, level: 0, dimmed: false, muted: false, mono: false) == nil)
print("Meter attack/release, peak/clip holds, mute, dim and post-control checks passed")
SWIFT
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{MeterBallistics,MeterRouting,OutputControlPacket,ControlPacket}.swift "$scratch/main.swift" -o "$scratch/check"
"$scratch/check"
