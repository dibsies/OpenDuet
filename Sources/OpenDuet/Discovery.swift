import CoreAudio
import Foundation
import IOKit

enum Discovery {
    static func report() -> String {
        usbReport() + "\n\n" + audioReport()
    }

    private static func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    private static func usbReport() -> String {
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator
        )
        guard status == KERN_SUCCESS else { return "USB registry query failed (\(status))." }
        defer { IOObjectRelease(iterator) }
        var devices: [String] = []
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            guard property(device, "idVendor") as? Int == 0x0c60,
                  property(device, "idProduct") as? Int == 0x0007 else { continue }
            var lines = ["Duet USB (0C60:0007)"]
            if let revision = property(device, "bcdDevice") as? UInt16 {
                lines.append(String(format: "USB device revision 0x%04X (BCD)", revision))
            }
            for (key, label) in [
                ("locationID", "Registry location"),
                ("bNumConfigurations", "Configurations advertised"),
                ("kUSBCurrentConfiguration", "Active configuration"),
                ("IOAudioDeviceLocalizedBundle", "Audio bundle hint"),
                ("UsbExclusiveOwner", "Exclusive owner")
            ] {
                if let value = property(device, key) { lines.append("\(label)  \(value)") }
            }
            var children: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) == KERN_SUCCESS {
                defer { IOObjectRelease(children) }
                while case let child = IOIteratorNext(children), child != 0 {
                    defer { IOObjectRelease(child) }
                    guard IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
                          let number = property(child, "bInterfaceNumber") as? Int else { continue }
                    let fields = ["bInterfaceClass", "bInterfaceSubClass", "bInterfaceProtocol"]
                        .map { property(child, $0).map(String.init(describing:)) ?? "?" }
                    lines.append("Interface \(number)  class/subclass/protocol \(fields.joined(separator: "/"))")
                    if let alternate = property(child, "bAlternateSetting") as? Int,
                       let endpoints = property(child, "bNumEndpoints") as? Int {
                        lines.append("  Registry alternate \(alternate), endpoints \(endpoints)")
                    }
                    for key in [
                        "IOAudioEngineInputSampleLatency",
                        "IOAudioEngineOutputSampleLatency",
                        "IOAudioEngineSampleOffset"
                    ] {
                        if let values = property(child, key) as? [String: Int] {
                            let samples = values.sorted {
                                (Int($0.key) ?? 0, $0.key) < (Int($1.key) ?? 0, $1.key)
                            }.map { "\($0.key) Hz = \($0.value)" }.joined(separator: ", ")
                            lines.append("  \(key) (samples): \(samples)")
                        }
                    }
                    for binding in audioBindings(child) {
                        lines.append("  \(binding)")
                    }
                }
            }
            devices.append(lines.joined(separator: "\n"))
        }
        return devices.isEmpty ? "Duet USB (0C60:0007) absent from registry." : devices.joined(separator: "\n\n")
    }

    private static func audioBindings(_ interface: io_registry_entry_t) -> [String] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(interface, kIOServicePlane, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var bindings: [String] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if IOObjectConformsTo(child, "AppleUSBAudioControlNub") != 0 {
                bindings.append("Apple USB audio control service")
            }
            if let creator = property(child, "IOUserClientCreator") as? String,
               creator.hasSuffix(", usbaudiod") {
                bindings.append("Apple USB audio daemon client")
            }
        }
        return bindings
    }

    private static func audioReport() -> String {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard status == noErr else { return "Core Audio inventory unavailable (\(status))." }
        guard size > 0 else { return "Core Audio exposed zero devices." }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        status = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return "Core Audio inventory read failed (\(status))." }
        return (["Core Audio devices (independent of USB matching)"] + devices.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride).map { device in
            address.mSelector = kAudioObjectPropertyName
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout.size(ofValue: name))
            let nameStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &nameSize, &name)
            let label = nameStatus == noErr ? name?.takeRetainedValue() as String? : nil
            address.mSelector = kAudioDevicePropertyNominalSampleRate
            var rate: Float64 = 0
            var rateSize = UInt32(MemoryLayout.size(ofValue: rate))
            let rateStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &rateSize, &rate)
            let rateLabel = rateStatus == noErr ? "\(rate) Hz" : "rate unavailable"
            let input = channelCount(device, scope: kAudioDevicePropertyScopeInput)
            let output = channelCount(device, scope: kAudioDevicePropertyScopeOutput)
            return "\(label ?? "Audio device \(device)")  \(rateLabel)  \(input) in / \(output) out"
        }).joined(separator: "\n")
    }

    private static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
            return "?"
        }
        guard size > 0 else { return "0" }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else {
            return "?"
        }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return String(buffers.reduce(0) { $0 + Int($1.mNumberChannels) })
    }

}
