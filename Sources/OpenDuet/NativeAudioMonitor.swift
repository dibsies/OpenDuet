import AppKit
import CoreAudio

/// Registration is managed on the main actor; callbacks never access mutable fields.
/// Deinitialization removes the retained Core Audio blocks and notification tokens.
final class NativeAudioMonitor: @unchecked Sendable {
    private let block: AudioObjectPropertyListenerBlock
    private var catalogRegistered = false
    private var rateDevice: AudioObjectID?
    private var tokens: [NSObjectProtocol] = []

    @MainActor
    init(onChange: @escaping @Sendable () -> Void,
         onSleep: @escaping @Sendable () -> Void,
         onWake: @escaping @Sendable () -> Void) {
        block = { _, _ in onChange() }
        var address = Self.address(kAudioHardwarePropertyDevices)
        catalogRegistered = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in onSleep() })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in onWake() })
    }

    @MainActor
    func trackRate(_ device: AudioObjectID?) {
        guard device != rateDevice else { return }
        removeRateListener()
        guard let device else { return }
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr { rateDevice = device }
    }

    private func removeRateListener() {
        if let device = rateDevice {
            var address = Self.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        rateDevice = nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    deinit {
        if catalogRegistered {
            var address = Self.address(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        removeRateListener()
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
    }
}
