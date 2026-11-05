import CoreAudio
import Foundation
import OSLog

/// Only output-element zero on the selected Duet is touched; no keyboard event tap.
final class CoreAudioVolumeBackend: SystemVolumeBackend, @unchecked Sendable {
    @MainActor var onChange: (@MainActor @Sendable () -> Void)?
    @MainActor var onDefaultOutputChange: (@MainActor @Sendable () -> Void)?
    private static let logger = Logger(subsystem: "org.openduet.experimental", category: "KeyboardVolume")
    private var systemBlock: AudioObjectPropertyListenerBlock?
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var tracked: AudioObjectID?
    private var selectors: [AudioObjectPropertySelector] = []

    @MainActor init() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.onDefaultOutputChange?() }
        }
        var property = Self.property(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, .main, block) == noErr {
            systemBlock = block
        }
    }

    private static func property(_ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T>(_ device: AudioObjectID, _ property: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var value = initial, property = property, size = UInt32(MemoryLayout<T>.size)
        let result = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, $0.baseAddress!)
        }
        return result == noErr ? value : nil
    }

    @MainActor func defaultOutput() -> UInt32? {
        Self.get(AudioObjectID(kAudioObjectSystemObject),
                 Self.property(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal), UInt32(0))
    }

    @MainActor func track(_ device: UInt32?) -> Bool {
        if device == tracked { return device == nil || deviceBlock != nil }
        removeDeviceListeners()
        guard let device else { return true }
        guard systemBlock != nil else { return false }
        for selector in [kAudioDevicePropertyVolumeDecibels, kAudioDevicePropertyMute] {
            var p = Self.property(selector), settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &p),
                  AudioObjectIsPropertySettable(device, &p, &settable) == noErr, settable.boolValue else { return false }
        }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }
        tracked = device; deviceBlock = block
        for selector in [kAudioDevicePropertyVolumeDecibels, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var p = Self.property(selector)
            guard AudioObjectAddPropertyListenerBlock(device, &p, .main, block) == noErr else {
                removeDeviceListeners(); return false
            }
            selectors.append(selector)
        }
        return true
    }

    @MainActor func read(_ device: UInt32) -> SystemVolumeState? {
        guard defaultOutput() == device,
              let level = Self.get(device, Self.property(kAudioDevicePropertyVolumeDecibels), Float32(0)), level.isFinite,
              let mute = Self.get(device, Self.property(kAudioDevicePropertyMute), UInt32(0)) else { return nil }
        return .init(level: Int(max(-64, min(0, level)).rounded()), muted: mute != 0)
    }

    @MainActor func scalar(_ device: UInt32) -> Double? {
        guard defaultOutput() == device,
              let value = Self.get(device, Self.property(kAudioDevicePropertyVolumeScalar), Float32(0)), value.isFinite else { return nil }
        return Double(value)
    }

    @MainActor func write(_ state: SystemVolumeState, to device: UInt32) -> Bool {
        guard state.valid, defaultOutput() == device, let before = read(device),
              let range = Self.get(device, Self.property(kAudioDevicePropertyVolumeRangeDecibels), AudioValueRange()),
              range.mMinimum.isFinite, range.mMaximum.isFinite, range.mMinimum <= range.mMaximum else { return false }
        func set<T>(_ selector: AudioObjectPropertySelector, value: T) -> Bool {
            guard defaultOutput() == device else { return false }
            var p = Self.property(selector), value = value
            return withUnsafeBytes(of: &value) {
                AudioObjectSetPropertyData(device, &p, 0, nil, UInt32($0.count), $0.baseAddress!) == noErr
            }
        }
        let level = Float32(max(range.mMinimum, min(range.mMaximum, Double(state.level))))
        // Setting the level can itself change mute. The snapshot from before
        // that write cannot decide whether the final mute write is necessary.
        guard SystemVolumePropertyWriter.write(state, before: before,
                  level: { set(kAudioDevicePropertyVolumeDecibels, value: level) },
                  mute: { set(kAudioDevicePropertyMute, value: UInt32($0 ? 1 : 0)) }),
              let after = read(device), after == state else {
            Self.logger.notice("HAL sync failed: target \(state.level) mute \(state.muted)")
            return false
        }
        Self.logger.debug("HAL synchronized: level \(after.level) mute \(after.muted)")
        return true
    }

    private func removeDeviceListeners() {
        if let device = tracked, let block = deviceBlock {
            for selector in selectors {
                var p = Self.property(selector)
                AudioObjectRemovePropertyListenerBlock(device, &p, .main, block)
            }
        }
        tracked = nil; deviceBlock = nil; selectors = []
    }

    deinit {
        removeDeviceListeners()
        if let block = systemBlock {
            var p = Self.property(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &p, .main, block)
        }
    }
}
