/// Duet II source meter selection traced in Glue's 0x100009588.
/// Values precede the output level and mute; they do not measure analog loudness.
enum MeterRouting {
    static func source(_ route: OutputControlPacket.RouteSelector?, lanes: [Double]) -> [Double]? {
        guard lanes.count == 10, let route else { return nil }
        let start: Int
        switch route { case .playback12: start = 0; case .playback34: start = 2; case .mixer: start = 6 }
        return Array(lanes[start..<start + 2])
    }
}

extension MeterRouting {
    /// Calculated post-control signal, not an electrical output measurement.
    /// Mono uses a conservative peak bound; source peaks contain no phase information.
    static func output(_ source: [Double]?, level: Int, dimmed: Bool, muted: Bool, mono: Bool) -> [Double]? {
        guard let source, source.count == 2 else { return nil }
        if muted { return [-.infinity, -.infinity] }
        let attenuation = Double(min(0, max(-64, level)) - (dimmed ? 15 : 0))
        let signal = mono ? Array(repeating: max(source[0], source[1]), count: 2) : source
        return signal.map { $0.isFinite ? min(0, $0 + attenuation) : -.infinity }
    }
}
