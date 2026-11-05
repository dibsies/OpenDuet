import CoreAudio
import Foundation

/// Audio configuration uses Apple's audio service, independent of USB control ownership.
enum NativeAudioDevice {
    struct Snapshot {
        let id: AudioDeviceID
        let sampleRate: Double
        let supportedRates: [Double]
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func failure(_ message: String, _ status: OSStatus = 0) -> NSError {
        NSError(domain: "OpenDuet.Audio", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: message + (status == 0 ? "" : " (\(status))")])
    }

    static func snapshot() throws -> Snapshot {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size)
        guard status == noErr, size > 0 else { throw failure("Audio devices are unavailable", status) }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.stride)
        status = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &property, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { throw failure("Unable to read audio devices", status) }
        let matches = devices.filter { device in
            var nameProperty = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout.size(ofValue: name))
            let result = AudioObjectGetPropertyData(device, &nameProperty, 0, nil, &nameSize, &name)
            guard result == noErr else { return false }
            return name?.takeRetainedValue() as String? == "Duet USB"
        }
        guard matches.count == 1, let device = matches.first else {
            throw failure(matches.isEmpty ? "Duet USB is not available in Core Audio" : "Multiple Duet audio devices found")
        }
        property = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Double = 0
        size = UInt32(MemoryLayout<Double>.size)
        status = AudioObjectGetPropertyData(device, &property, 0, nil, &size, &rate)
        guard status == noErr, rate.isFinite, rate > 0 else { throw failure("Unable to read the Duet sample rate", status) }
        property = address(kAudioDevicePropertyAvailableNominalSampleRates)
        size = 0
        status = AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size)
        guard status == noErr, size > 0 else { throw failure("Supported sample rates are unavailable", status) }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.stride)
        status = ranges.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { throw failure("Unable to read supported sample rates", status) }
        let candidates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        let supported = candidates.filter { value in ranges.contains { $0.mMinimum <= value && value <= $0.mMaximum } }
        return Snapshot(id: device, sampleRate: rate, supportedRates: supported)
    }

    @MainActor
    static func setSampleRate(_ rate: Double) async throws -> Snapshot {
        let before = try snapshot()
        guard before.supportedRates.contains(rate) else { throw failure("The Duet does not advertise this sample rate") }
        var property = address(kAudioDevicePropertyNominalSampleRate)
        var settable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(before.id, &property, &settable)
        guard status == noErr, settable.boolValue else { throw failure("The Duet sample rate cannot currently be changed", status) }
        var requested = rate
        status = AudioObjectSetPropertyData(before.id, &property, 0, nil, UInt32(MemoryLayout<Double>.size), &requested)
        guard status == noErr else { throw failure("The audio service rejected the sample-rate change", status) }
        for _ in 0..<20 {
            let observed = try snapshot()
            guard observed.id == before.id else { throw failure("The audio device changed during configuration") }
            if abs(observed.sampleRate - rate) < 0.5 { return observed }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw failure("The requested sample rate has not been confirmed by Core Audio")
    }
}
