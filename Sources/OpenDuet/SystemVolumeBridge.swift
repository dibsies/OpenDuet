import Foundation
import OSLog

struct SystemVolumeState: Equatable {
    let level: Int
    let muted: Bool
    var valid: Bool { (-64...0).contains(level) }
}

/// A level write may change mute as a side effect. Assert the final mute state
/// afterward, while muting first when the requested end state is muted.
enum SystemVolumePropertyWriter {
    static func write(_ state: SystemVolumeState, before: SystemVolumeState,
                      level: () -> Bool, mute: (Bool) -> Bool) -> Bool {
        if state.muted && !before.muted && !mute(true) { return false }
        if state.level != before.level && !level() { return false }
        return mute(state.muted)
    }
}

protocol SystemVolumeBackend: AnyObject {
    @MainActor var onChange: (@MainActor @Sendable () -> Void)? { get set }
    @MainActor var onDefaultOutputChange: (@MainActor @Sendable () -> Void)? { get set }
    @MainActor func defaultOutput() -> UInt32?
    @MainActor func track(_ device: UInt32?) -> Bool
    @MainActor func read(_ device: UInt32) -> SystemVolumeState?
    @MainActor func scalar(_ device: UInt32) -> Double?
    @MainActor func write(_ state: SystemVolumeState, to device: UInt32) -> Bool
}

/// Event-driven bridge: initialize the OS from known hardware state, never the reverse.
@MainActor
final class SystemVolumeBridge {
    private static let logger = Logger(subsystem: "org.openduet.experimental", category: "KeyboardVolume")
    private let backend: any SystemVolumeBackend
    private let changed: (SystemVolumeState) -> Void
    private let status: (String) -> Void
    private var device: UInt32?
    private var desired: SystemVolumeState?
    private var active: UInt32?
    private var observed: SystemVolumeState?
    private var observedScalar: Double?
    private var message = ""
    private var pendingMute: Task<Void, Never>?

    init(backend: any SystemVolumeBackend, changed: @escaping (SystemVolumeState) -> Void,
         status: @escaping (String) -> Void) {
        self.backend = backend; self.changed = changed; self.status = status
        backend.onChange = { [weak self] in self?.propertyChanged() }
        backend.onDefaultOutputChange = { [weak self] in self?.synchronize() }
    }

    func update(device: UInt32?, state: SystemVolumeState?) {
        guard self.device != device || desired != state || observed != state || active == nil else { return }
        pendingMute?.cancel(); pendingMute = nil
        self.device = device; desired = state
        synchronize()
    }

    private func report(_ value: String) {
        guard value != message else { return }
        message = value; status(value)
    }

    private func suspend(_ reason: String) {
        pendingMute?.cancel(); pendingMute = nil
        _ = backend.track(nil); active = nil; observed = nil; observedScalar = nil
        report(reason)
    }

    private func synchronize() {
        guard let device, let desired, desired.valid else {
            suspend("Keyboard volume waits for an initialized Main Out."); return
        }
        guard backend.defaultOutput() == device else {
            suspend("Keyboard volume is inactive: Duet USB is not the system output."); return
        }
        guard backend.track(device), backend.write(desired, to: device),
              let baseline = backend.read(device), let scalar = backend.scalar(device), scalar.isFinite, (0...1).contains(scalar) else {
            suspend("System volume controls are unavailable for this device."); return
        }
        active = device; observed = baseline; observedScalar = scalar
        report("Keyboard volume uses 2 dB steps; mute controls Main Out while Duet USB is the system output.")
    }

    private func propertyChanged(settledMute: Bool = false) {
        guard let device, desired != nil, backend.defaultOutput() == device else {
            synchronize(); return
        }
        guard active == device else { synchronize(); return }
        guard let value = backend.read(device), value.valid,
              let scalar = backend.scalar(device), scalar.isFinite, (0...1).contains(scalar),
              let previous = observed, let previousScalar = observedScalar, let desired else {
            suspend("Unable to read system volume; hardware level is unchanged."); return
        }
        let delta = scalar - previousScalar
        guard value != previous || abs(delta) > 0.000001 else { return }
        Self.logger.notice("HAL event: level \(value.level) mute \(value.muted) scalar \(scalar); previous \(previous.level) mute \(previous.muted) scalar \(previousScalar); target \(desired.level) mute \(desired.muted)")
        var level = desired.level
        let volumeMoved = abs(delta) > 0.000001 || value.level != previous.level
        // On this native driver, Volume Down first publishes mute, then the
        // scalar change ~125 ms later. Keep the prior unmuted baseline while
        // waiting briefly to distinguish that pair from a standalone Mute key.
        pendingMute?.cancel(); pendingMute = nil
        if !settledMute && !volumeMoved && value.muted && !desired.muted {
            pendingMute = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
                self?.propertyChanged(settledMute: true)
            }
            return
        }
        let automaticVolumeMute = value.muted && !desired.muted
            && (volumeMoved || (scalar <= 0.000001 && desired.level > -64))
        if volumeMoved {
            // macOS normal volume keys change normalized volume by 1/16.
            // Recover coalesced key steps, then apply a fixed hardware dB step.
            let steps = max(1, Int((abs(delta) * 16).rounded()))
            let direction = delta == 0 ? (value.level > previous.level ? 1 : -1) : (delta > 0 ? 1 : -1)
            level = max(-64, min(0, desired.level + direction * steps * 2))
        }
        let next = SystemVolumeState(level: level, muted: automaticVolumeMute ? false : value.muted)
        observed = value; observedScalar = scalar
        self.desired = next
        if automaticVolumeMute {
            // Native volume changes can also set mute (including at scalar
            // zero). Treat a combined level/mute change as volume, restoring
            // the previous known level; the USB acknowledgement then
            // synchronizes the final level. Do not treat it as the mute key.
            guard backend.write(desired, to: device), let restored = backend.read(device),
                  let restoredScalar = backend.scalar(device) else {
                suspend("Unable to clear system auto-mute; keyboard bridge stopped.")
                return
            }
            observed = restored; observedScalar = restoredScalar
        }
        if next != desired { changed(next) }
        else { synchronize() } // A clamped key still resets the native HUD to actual state.

    }
}
