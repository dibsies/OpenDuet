/// Only accepts the complete two-input response from the direct USB helper.
struct InputModeSnapshot: Equatable {
    let modes: [InputControlPacket.Mode]

    init?(output: String) {
        let lines = output.split(separator: "\n").filter { $0.hasPrefix("INPUT_MODES ") }
        guard lines.count == 1 else { return nil }
        let fields = lines[0].split(separator: " ")
        guard fields.count == 3 else { return nil }
        let modes = fields.dropFirst().compactMap { UInt8($0).flatMap(InputControlPacket.Mode.init(rawValue:)) }
        guard modes.count == 2 else { return nil }
        self.modes = modes
    }

    var description: String {
        modes.enumerated().map { index, mode in
            let name: String
            switch mode {
            case .plus4: name = "+4 dBu"
            case .minus10: name = "−10 dBV"
            case .mic: name = "Mic"
            case .instrument: name = "Instrument"
            }
            return "Input \(index + 1): \(name)"
        }.joined(separator: " · ")
    }
}
