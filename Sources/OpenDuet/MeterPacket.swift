import Foundation

/// Raw Duet II meter lanes. Lane-to-output selection depends on routing.
struct MeterPacket {
    struct Lane {
        let raw: UInt16
        var overloaded: Bool { raw > 0x3ffe }
        var decibels: Double {
            guard raw > 0 else { return -.infinity }
            return overloaded ? 0 : 20 * log10(Double(raw) / 16384)
        }
    }

    let lanes: [Lane]

    init?(bytes: [UInt8]) {
        guard bytes.count == 20 else { return nil }
        lanes = stride(from: 0, to: 20, by: 2).map {
            Lane(raw: (UInt16(bytes[$0]) << 8) | UInt16(bytes[$0 + 1]))
        }
    }
}
