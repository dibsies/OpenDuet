import Foundation

struct OutputIncreaseRequest: Identifiable, Equatable {
    let id = UUID()
    let generation: UInt64
    let headphone: Bool
    let from: Int
    let target: Int
    var title: String { headphone ? "Headphones" : "Main Out" }
    var isMaximum: Bool { target == 0 && from < 0 }
}

/// Guards control mistakes, not acoustic exposure. Ceilings remain user-configurable.
struct OutputSafety {
    enum Decision: Equatable { case allow(Int), confirm(Int) }
    static func evaluate(requested: Int, current: Int, ceiling: Int) -> Decision {
        let target = max(-64, min(min(0, ceiling), requested))
        return target > current && (target == 0 || target - current > 25) ? .confirm(target) : .allow(target)
    }
}

/// Clicks alone do nothing; movement is relative to where the drag began.
enum RelativeDial {
    static func value(start: Double, verticalTranslation: Double, fine: Bool, range: ClosedRange<Double>) -> Double {
        guard start.isFinite, verticalTranslation.isFinite else { return range.lowerBound }
        return max(range.lowerBound, min(range.upperBound, (start - verticalTranslation / (fine ? 16 : 4)).rounded()))
    }
}
