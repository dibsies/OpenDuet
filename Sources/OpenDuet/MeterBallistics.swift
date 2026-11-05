import Foundation

/// Fast attack, 20 dB/s release, with independently held peaks and full-scale warnings.
/// Input values are already after the preamp/ADC; no input gain is added here.
struct MeterBallistics {
    private(set) var levels: [Double]
    private(set) var peaks: [Double]
    private(set) var overs: [Bool]
    private var peakUntil: [Double]
    private var overUntil: [Double]
    private var lastTime: Double?
    var peakHold = 2.0 {
        didSet { peakUntil = .init(repeating: peakHold.isInfinite ? .infinity : 0, count: levels.count) }
    }
    var overHold = 2.0 {
        didSet {
            overUntil = overs.map { $0 && overHold.isInfinite ? .infinity : 0 }
            if overHold == 0 { overs = .init(repeating: false, count: levels.count) }
        }
    }

    init(count: Int) {
        levels = .init(repeating: -.infinity, count: count)
        peaks = levels; overs = .init(repeating: false, count: count)
        peakUntil = .init(repeating: 0, count: count); overUntil = peakUntil
    }

    mutating func update(_ targets: [Double], at time: Double, silent: Set<Int> = []) {
        guard targets.count == levels.count, time.isFinite else { return }
        let elapsed = min(1, max(0, time - (lastTime ?? time)))
        lastTime = time
        for index in targets.indices {
            if silent.contains(index) {
                levels[index] = -.infinity; peaks[index] = -.infinity; overs[index] = false
                peakUntil[index] = 0; overUntil[index] = 0
                continue
            }
            let target = targets[index].isFinite ? min(0, targets[index]) : -Double.infinity
            let released = levels[index] - 20 * elapsed
            levels[index] = max(target, released)
            if levels[index] < -90 { levels[index] = -.infinity }
            if target >= peaks[index] {
                peaks[index] = target; peakUntil[index] = time + peakHold
            } else if time >= peakUntil[index] {
                peaks[index] = max(levels[index], peaks[index] - 20 * elapsed)
                if peaks[index] < -90 { peaks[index] = -.infinity }
            }
            if target >= 0 { overUntil[index] = time + overHold }
            overs[index] = target >= 0 || overUntil[index] > time
        }
    }

    mutating func clearHolds() {
        peaks = .init(repeating: -.infinity, count: levels.count); overs = .init(repeating: false, count: levels.count)
        peakUntil = .init(repeating: 0, count: levels.count); overUntil = peakUntil
    }
}

enum MeterHold: String, CaseIterable, Identifiable {
    case off = "Off", twoSeconds = "2 seconds", infinite = "Infinite"
    var id: Self { self }
    var seconds: Double { switch self { case .off: 0; case .twoSeconds: 2; case .infinite: .infinity } }
}
