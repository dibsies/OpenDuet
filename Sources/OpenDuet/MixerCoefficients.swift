import Foundation

/// Duet II mixer math, reconstructed from the vendor's coefficient path.
/// Values describe desired state; they do not claim hardware readback.
enum MixerCoefficients {
    enum PlaybackSource: UInt8, CaseIterable, Identifiable, Codable {
        case playback12 = 0, playback34 = 1
        var id: Self { self }
        var title: String { self == .playback12 ? "Playback 1–2" : "Playback 3–4" }
        var packet: ControlPacket { ControlPacket(request: 0x36, index: 0, payload: rawValue) }
    }
    struct Channel: Codable, Equatable, Sendable {
        var level: Double = 0
        var pan: Double = 0.5
        var muted = false
        var solo = false
        var soloSafe = false
    }

    struct State: Codable, Equatable, Sendable {
        var stereoLinked = false
        var input1 = Channel()
        var input2 = Channel()
        var playback = Channel()
        var masterLevel: Double = 0
        var masterMuted = false
    }

    struct Bank: Equatable, Sendable {
        let index: UInt8
        let coefficients: [UInt16]
        var payload: [UInt8] {
            coefficients.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] }
        }
        var setupBytes: [UInt8] { [0x40, 0x10, 0, 0, index, 0, 8, 0] }
    }

    static func encode(_ state: State) -> [Bank]? {
        let channels = [state.input1, state.input2, state.playback]
        guard state.masterLevel.isFinite, (-64...12).contains(state.masterLevel),
              channels.allSatisfy({ $0.level.isFinite && (-64...12).contains($0.level)
                  && $0.pan.isFinite && (0...1).contains($0.pan) }) else { return nil }
        let anySolo = (state.stereoLinked ? [state.input1, state.playback] : channels).contains { $0.solo }
        func amplitude(_ channel: Channel) -> Double {
            guard !state.masterMuted, !channel.muted,
                  !anySolo || channel.solo || channel.soloSafe,
                  state.masterLevel > -60, channel.level > -60 else { return 0 }
            return pow(10, min(12, state.masterLevel + channel.level) / 20)
        }
        func quantize(_ value: Double) -> UInt16 {
            UInt16(min(32768, max(0, value * 8192)).rounded(.toNearestOrEven))
        }
        let a = amplitude(state.input1)
        let b = amplitude(state.input2)
        let p = amplitude(state.playback)
        // Mono sources use equal-power pan; the stereo return uses balance.
        var left = [a * cos(state.input1.pan * .pi / 2),
                    b * cos(state.input2.pan * .pi / 2),
                    p * pow(1 - 2 * max(state.playback.pan - 0.5, 0), 2), 0]
        var right = [a * sin(state.input1.pan * .pi / 2),
                     b * sin(state.input2.pan * .pi / 2), 0,
                     p * pow(1 - 2 * max(0.5 - state.playback.pan, 0), 2)]
        if state.stereoLinked {
            left[0] = a * pow(1 - 2 * max(state.input1.pan - 0.5, 0), 2)
            left[1] = 0
            right[0] = 0
            right[1] = a * pow(1 - 2 * max(0.5 - state.input1.pan, 0), 2)
        }
        return [Bank(index: 0, coefficients: left.map(quantize)),
                Bank(index: 1, coefficients: right.map(quantize))]
    }
}
