/// Packet encoding traced in ApogeeGlue. Device writes require live validation.
enum OutputControlPacket {
    enum RouteSelector: UInt8, CaseIterable, Identifiable, Codable {
        case playback12 = 0
        case playback34 = 1
        case mixer = 2

        var id: Self { self }
        var title: String {
            switch self {
            case .playback12: "Playback 1–2"
            case .playback34: "Playback 3–4"
            case .mixer: "Mixer"
            }
        }
        var sourceID: UInt32 {
            switch self {
            case .playback12: 0x18000000
            case .playback34: 0x18000002
            case .mixer: 0x28000000
            }
        }
        init?(sourceID: UInt32) {
            guard let value = Self.allCases.first(where: { $0.sourceID == sourceID }) else { return nil }
            self = value
        }
    }

    enum Output { case main, headphones }

    static func mute(_ enabled: Bool, output: Output) -> [ControlPacket] {
        let first: UInt8 = output == .main ? 1 : 3
        return [first, first + 1].map { ControlPacket(request: 0x35, index: $0, payload: enabled ? 1 : 0) }
    }

    static func mainReference(plus4: Bool) -> [ControlPacket] {
        [UInt8(0), 1].map { ControlPacket(request: 0x18, index: $0, payload: plus4 ? 1 : 0) }
    }

    static func routing(main: RouteSelector, headphones: RouteSelector) -> ControlPacket {
        ControlPacket(request: 0x37, index: 0, payload: main.rawValue | (headphones.rawValue << 4))
    }

    static func sumToMono(main: Bool, headphones: Bool) -> ControlPacket {
        ControlPacket(request: 0x38, index: 0, payload: (main ? 1 : 0) | (headphones ? 0x10 : 0))
    }

    static func attenuation(level: Double, dimmed: Bool, output: Output) -> [ControlPacket]? {
        guard (-64.0...0.0).contains(level) else { return nil }
        let payload = UInt8((-level + (dimmed ? 15 : 0)).rounded())
        let first: UInt8 = output == .main ? 1 : 3
        return [first, first + 1].map { ControlPacket(request: 0x33, index: $0, payload: payload) }
    }

}
