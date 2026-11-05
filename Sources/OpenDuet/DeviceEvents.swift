/// Prefix of the Duet II's 29-byte change report, traced in Glue's callback.
/// These are observations only. Dispatching them requires an initialized session.
struct DeviceEvents: Equatable, Sendable {
    let available: Bool
    let touchpadA: Bool
    let touchpadB: Bool
    let encoderPressed: Bool
    let clockwiseSteps: UInt8
    let counterclockwiseSteps: UInt8

    init?(bytes: [UInt8]) {
        guard bytes.count == 29 else { return nil }
        available = bytes[0] != 0
        touchpadA = available && bytes[1] & 1 != 0
        touchpadB = available && bytes[2] & 1 != 0
        encoderPressed = available && bytes[3] & 1 != 0
        // Physical test: byte 4 is counterclockwise; byte 5 clockwise.
        clockwiseSteps = available ? bytes[5] : 0
        counterclockwiseSteps = available ? bytes[4] : 0
    }
}
