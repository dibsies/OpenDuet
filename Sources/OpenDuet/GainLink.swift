/// Move a stereo pair together, preserving its gain offset at either limit.
enum GainLink {
    static func shifting(_ gains: [Int], by requestedDelta: Int, maximum: Int) -> [Int]? {
        guard gains.count == 2, maximum >= 0, gains.allSatisfy({ (0...maximum).contains($0) }) else { return nil }
        let delta = min(maximum - max(gains[0], gains[1]), max(-min(gains[0], gains[1]), requestedDelta))
        return gains.map { $0 + delta }
    }
}
