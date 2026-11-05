/// Offline encoding of the Duet II input commands traced in ApogeeGlue.
enum InputControlPacket {
    enum Channel: UInt8 { case one = 0, two = 1 }
    enum Mode: UInt8, Codable, Sendable { case plus4 = 0, minus10 = 1, mic = 2, instrument = 3 }
    enum GainMode { case mic, instrument }

    static func mode(_ mode: Mode, channel: Channel) -> ControlPacket {
        ControlPacket(request: 0x16, index: channel.rawValue, payload: mode.rawValue)
    }

    static func gain(_ decibels: UInt8, mode: GainMode, channel: Channel) -> ControlPacket? {
        let maximum: UInt8 = mode == .mic ? 75 : 65
        guard decibels <= maximum else { return nil }
        return ControlPacket(request: mode == .mic ? 0x34 : 0x3e,
                    index: channel.rawValue + 1, payload: decibels)
    }

    static func phantom(_ enabled: Bool, channel: Channel) -> ControlPacket {
        ControlPacket(request: 0x15, index: channel.rawValue, payload: enabled ? 1 : 0)
    }

    static func softLimit(_ enabled: Bool, channel: Channel) -> ControlPacket {
        ControlPacket(request: 0x11, index: channel.rawValue, payload: enabled ? 1 : 0)
    }

    static func phaseInverted(_ enabled: Bool, channel: Channel) -> ControlPacket {
        ControlPacket(request: 0x13, index: channel.rawValue, payload: enabled ? 1 : 0)
    }
}
