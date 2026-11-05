/// Offline display encoding from the Duet II OLED implementation.
/// No display command is sent by this encoding type.
struct OLEDTransfer: Equatable {
    let request: UInt8
    let value: UInt16
    let index: UInt16
    let payload: [UInt8]

    var setupBytes: [UInt8] {
        [0x40, request, UInt8(value & 255), UInt8(value >> 8),
         UInt8(index & 255), UInt8(index >> 8),
         UInt8(payload.count & 255), UInt8(payload.count >> 8)]
    }

    static func fill(x: Int, y: Int, width: Int, height: Int, color: UInt16) -> OLEDTransfer? {
        guard x >= 0, y >= 0, width > 0, height > 0,
              x < 160, y < 128, width <= 160 - x, height <= 128 - y else { return nil }
        let start = UInt16(x << 8 | y)
        let end = UInt16((x + width - 1) << 8 | (y + height - 1))
        return OLEDTransfer(request: 0x23, value: start, index: end,
                            payload: [UInt8(color >> 8), UInt8(color & 255)])
    }

    static func frameTiles(_ pixels: [UInt8]) -> [OLEDTransfer]? {
        guard pixels.count == 160 * 128 * 2 else { return nil }
        var commands: [OLEDTransfer] = []
        for y in stride(from: 0, to: 128, by: 8) {
            for x in stride(from: 0, to: 160, by: 16) {
                var tile: [UInt8] = []
                tile.reserveCapacity(256)
                for row in 0..<8 {
                    let start = (y + row) * 320 + x * 2
                    tile.append(contentsOf: pixels[start..<start + 32])
                }
                for offset in stride(from: 0, to: tile.count, by: 64) {
                    commands.append(OLEDTransfer(request: offset == 0 ? 0x21 : 0x22,
                        value: offset == 0 ? UInt16(x << 8 | y) : 0,
                        index: offset == 0 ? UInt16((x + 15) << 8 | (y + 7)) : 0,
                        payload: Array(tile[offset..<offset + 64])))
                }
            }
        }
        return commands
    }
}
