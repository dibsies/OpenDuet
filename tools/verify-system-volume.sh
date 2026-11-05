#!/bin/bash
# Fake Core Audio state only: no device, system volume or USB settings are changed.
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/check.swift" <<'SWIFT'
import Foundation
@MainActor final class Fake: SystemVolumeBackend {
    var onChange: (@MainActor @Sendable () -> Void)?
    var onDefaultOutputChange: (@MainActor @Sendable () -> Void)?
    var selected: UInt32? = 7
    var value = SystemVolumeState(level: -3, muted: false)
    var tracked: UInt32?
    var writes: [(UInt32, SystemVolumeState)] = []
    var fail = false
    func defaultOutput() -> UInt32? { selected }
    func track(_ device: UInt32?) -> Bool { tracked = device; return true }
    func read(_ device: UInt32) -> SystemVolumeState? { device == selected ? value : nil }
    func scalar(_ device: UInt32) -> Double? { pow(Double(value.level + 64) / 64, 2) }
    func write(_ state: SystemVolumeState, to device: UInt32) -> Bool {
        guard !fail, device == selected else { return false }
        writes.append((device, state)); value = state; return true
    }
    func emit(_ state: SystemVolumeState) { value = state; onChange?() }
}
@main struct Test {
    @MainActor static func main() async {
        func expect(_ condition: @autoclosure () -> Bool) {
            if !condition() { FileHandle.standardError.write(Data("System-volume check failed\n".utf8)); exit(1) }
        }
        var nativeMuted = false
        var operations: [String] = []
        expect(SystemVolumePropertyWriter.write(.init(level: -26, muted: false), before: .init(level: -24, muted: false),
            level: { operations.append("level"); nativeMuted = true; return true },
            mute: { operations.append("mute"); nativeMuted = $0; return true }))
        expect(!nativeMuted && operations == ["level", "mute"])
        operations = []
        expect(SystemVolumePropertyWriter.write(.init(level: -26, muted: true), before: .init(level: -24, muted: false),
            level: { operations.append("level"); nativeMuted = false; return true },
            mute: { operations.append("mute"); nativeMuted = $0; return true }))
        expect(nativeMuted && operations == ["mute", "level", "mute"])
        let backend = Fake()
        var delivered: [SystemVolumeState] = []
        let bridge = SystemVolumeBridge(backend: backend, changed: { delivered.append($0) }, status: { _ in })
        bridge.update(device: 7, state: nil)
        expect(backend.writes.isEmpty && delivered.isEmpty)
        let initial = SystemVolumeState(level: -42, muted: false)
        bridge.update(device: 7, state: initial)
        expect(backend.value == initial && delivered.isEmpty) // Do not import stale -3 dB into hardware.
        backend.onChange?(); backend.onChange?()
        expect(delivered.isEmpty) // Synchronization echoes never generate USB changes.
        backend.emit(.init(level: -46, muted: false))
        backend.onChange?()
        expect(delivered == [.init(level: -44, muted: false)]) // Duplicate notifications coalesce.
        bridge.update(device: 7, state: .init(level: -44, muted: false))
        backend.emit(.init(level: -44, muted: true))
        try? await Task.sleep(for: .milliseconds(260))
        expect(delivered.last == .init(level: -44, muted: true))
        let count = delivered.count, writes = backend.writes.count
        backend.selected = 8; backend.onDefaultOutputChange?()
        backend.emit(.init(level: 0, muted: false))
        expect(delivered.count == count && backend.writes.count == writes && backend.tracked == nil)
        backend.selected = 7; backend.onDefaultOutputChange?()
        expect(backend.value.level == -44 && delivered.count == count) // Re-select Duet: sync from hardware, never stale OS state.
        backend.value = .init(level: 0, muted: false)
        backend.onDefaultOutputChange?() // A coalesced route change still restores known state first.
        expect(backend.value.level == -44 && delivered.count == count)
        bridge.update(device: 7, state: nil)
        backend.emit(.init(level: 0, muted: false))
        expect(delivered.count == count && backend.tracked == nil) // Off, release or unknown output state.
        bridge.update(device: 7, state: .init(level: -65, muted: false))
        expect(backend.tracked == nil)
        backend.fail = true
        bridge.update(device: 7, state: initial)
        expect(backend.tracked == nil && delivered.count == count)
        let quiet = Fake()
        var quietValues: [SystemVolumeState] = []
        let fixed = SystemVolumeBridge(backend: quiet, changed: { quietValues.append($0) }, status: { _ in })
        fixed.update(device: 7, state: .init(level: -64, muted: false))
        quiet.emit(.init(level: -48, muted: false))
        expect(quietValues.last?.level == -62) // Native first 16 dB jump becomes two dB.
        quiet.onChange?()
        expect(quietValues.count == 1)
        fixed.update(device: 7, state: .init(level: -62, muted: false))
        expect(quiet.value.level == -62) // Resync HUD after the USB acknowledgement.
        quiet.emit(.init(level: -48, muted: false))
        expect(quietValues.last?.level == -60)
        let grouped = Fake()
        var groupedValue: SystemVolumeState?
        let coalesced = SystemVolumeBridge(backend: grouped, changed: { groupedValue = $0 }, status: { _ in })
        coalesced.update(device: 7, state: .init(level: -64, muted: false))
        grouped.emit(.init(level: -36, muted: false))
        expect(groupedValue?.level == -58) // Three native key steps delivered together.
        let floor = Fake()
        var floorValues: [SystemVolumeState] = []
        let floorBridge = SystemVolumeBridge(backend: floor, changed: { floorValues.append($0) }, status: { _ in })
        floorBridge.update(device: 7, state: .init(level: -56, muted: false))
        floor.emit(.init(level: -64, muted: true)) // Native Down reaches scalar zero and auto-mutes.
        expect(floorValues.last == .init(level: -58, muted: false))
        expect(floor.value == .init(level: -56, muted: false)) // OS auto-mute is undone immediately at the previous level.
        floorBridge.update(device: 7, state: .init(level: -58, muted: false))
        expect(floor.value == .init(level: -58, muted: false))
        floor.emit(.init(level: -64, muted: true))
        expect(floorValues.last == .init(level: -60, muted: false))
        floorBridge.update(device: 7, state: .init(level: -60, muted: false))
        floor.emit(.init(level: -60, muted: true)) // A real mute-key event remains valid.
        try? await Task.sleep(for: .milliseconds(260))
        expect(floorValues.last == .init(level: -60, muted: true))
        let combined = Fake()
        var combinedValue: SystemVolumeState?
        let combinedBridge = SystemVolumeBridge(backend: combined, changed: { combinedValue = $0 }, status: { _ in })
        combinedBridge.update(device: 7, state: .init(level: -24, muted: false))
        combined.emit(.init(level: -28, muted: true))
        expect(combinedValue == .init(level: -26, muted: false))
        expect(combined.value == .init(level: -24, muted: false))
        combinedBridge.update(device: 7, state: .init(level: -26, muted: false))
        combined.emit(.init(level: -26, muted: true))
        try? await Task.sleep(for: .milliseconds(260))
        expect(combinedValue == .init(level: -26, muted: true))
        let split = Fake()
        var splitValues: [SystemVolumeState] = []
        let splitBridge = SystemVolumeBridge(backend: split, changed: { splitValues.append($0) }, status: { _ in })
        splitBridge.update(device: 7, state: .init(level: -58, muted: false))
        split.emit(.init(level: -58, muted: true))
        expect(splitValues.isEmpty) // Native Down announces mute before changing level.
        try? await Task.sleep(for: .milliseconds(125))
        split.emit(.init(level: -64, muted: true))
        expect(splitValues == [.init(level: -60, muted: false)])
        splitBridge.update(device: 7, state: .init(level: -60, muted: false))
        try? await Task.sleep(for: .milliseconds(260))
        expect(splitValues.count == 1 && !split.value.muted) // Delayed mute task was cancelled.
        split.emit(.init(level: -60, muted: true))
        try? await Task.sleep(for: .milliseconds(260))
        expect(splitValues.last == .init(level: -60, muted: true)) // Standalone Mute remains supported.
        print("System volume initialization, echo/duplicate suppression, mute, default-device gating, off/unknown state and failure checks passed")
    }
}
SWIFT
swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/SystemVolumeBridge.swift "$scratch/check.swift" -o "$scratch/check"
"$scratch/check"
