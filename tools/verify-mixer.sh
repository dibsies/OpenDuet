#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/main.swift" <<'SWIFT'
import Foundation
precondition(MixerCoefficients.PlaybackSource.playback34.packet.setupBytes == [0x40, 0x36, 0, 0, 0, 0, 1, 0])
precondition(MixerCoefficients.PlaybackSource.playback34.packet.payload == 1)
var state = MixerCoefficients.State()
var banks = MixerCoefficients.encode(state)!
precondition(banks[0].coefficients == [5793, 5793, 8192, 0])
precondition(banks[1].coefficients == [5793, 5793, 0, 8192])
precondition(banks[0].payload == [0x16, 0xa1, 0x16, 0xa1, 0x20, 0, 0, 0])
precondition(banks[1].setupBytes == [0x40, 0x10, 0, 0, 1, 0, 8, 0])
state.input1.pan = 0
state.input2.pan = 1
state.playback.pan = 0.75
banks = MixerCoefficients.encode(state)!
precondition(banks[0].coefficients == [8192, 0, 2048, 0])
precondition(banks[1].coefficients == [0, 8192, 0, 8192])
state.input1.solo = true
banks = MixerCoefficients.encode(state)!
precondition(banks[0].coefficients == [8192, 0, 0, 0])
precondition(banks[1].coefficients == [0, 0, 0, 0])
state.playback.soloSafe = true
precondition(MixerCoefficients.encode(state)![1].coefficients[3] == 8192)
state.input1.muted = true
precondition(MixerCoefficients.encode(state)![0].coefficients[0] == 0)
state.masterMuted = true
precondition(MixerCoefficients.encode(state)!.allSatisfy { $0.coefficients.allSatisfy { $0 == 0 } })
state.masterMuted = false
state.masterLevel = -60
precondition(MixerCoefficients.encode(state)!.allSatisfy { $0.coefficients.allSatisfy { $0 == 0 } })
state.masterLevel = .nan
precondition(MixerCoefficients.encode(state) == nil)
state.masterLevel = 0
state.input1.pan = 1.01
precondition(MixerCoefficients.encode(state) == nil)
state = MixerCoefficients.State()
state.input1.pan = 0
state.input1.level = 12
state.masterLevel = 12
precondition(MixerCoefficients.encode(state)![0].coefficients[0] == 32613)
state.input1.level = -64
precondition(MixerCoefficients.encode(state)![0].coefficients[0] == 0)
state = MixerCoefficients.State()
state.stereoLinked = true
precondition(MixerCoefficients.encode(state)![0].coefficients == [8192, 0, 8192, 0])
precondition(MixerCoefficients.encode(state)![1].coefficients == [0, 8192, 0, 8192])
state.input1.pan = 0.75
precondition(MixerCoefficients.encode(state)![0].coefficients[0] == 2048)
precondition(MixerCoefficients.encode(state)![1].coefficients[1] == 8192)
state.input1.muted = true
precondition(MixerCoefficients.encode(state)![0].coefficients[0] == 0)
precondition(MixerCoefficients.encode(state)![1].coefficients[1] == 0)
print("Mixer coefficient checks passed")
SWIFT
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{ControlPacket,MixerCoefficients}.swift "$scratch/main.swift" -o "$scratch/check"
"$scratch/check"
