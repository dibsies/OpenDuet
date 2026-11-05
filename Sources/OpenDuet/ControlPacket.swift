/// An offline representation of a one-byte vendor OUT control transfer.
struct ControlPacket {
    let request: UInt8
    let index: UInt8
    let payload: UInt8

    var setupBytes: [UInt8] {
        [0x40, request, 0, 0, index, 0, 1, 0]
    }
}
