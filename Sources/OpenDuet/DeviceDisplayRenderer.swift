import Foundation
import CoreGraphics
import CoreText

/// Original artwork, composed for the Duet II's native 160 × 128 display.
enum DeviceDisplayRenderer {
    struct Input {
        var mode: String = "?"
        var gain: Int?
        var phantom: Bool?
        var softLimit: Bool?
        var phase: Bool?
        var meter: Double = -.infinity
        var peak: Double = -.infinity
        var over = false
    }
    struct Output {
        var level: Int?
        var muted: Bool?
        var meters: [Double]?
        var peaks: [Double]?
        var overs: [Bool]?
    }
    struct Snapshot {
        var inputs = [Input(), Input()]
        var outputs = [Output(), Output()]
        var selected = 2
        var focused = false
        var grouped = false
    }

    static func render(_ snapshot: Snapshot) -> [UInt8]? {
        guard snapshot.inputs.count == 2, snapshot.outputs.count == 2 else { return nil }
        let width = 160, height = 128
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        return rgba.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return nil }
            let mint = CGColor(red: 0.25, green: 0.88, blue: 0.76, alpha: 1)
            let blue = CGColor(red: 0.12, green: 0.48, blue: 1, alpha: 1)
            let white = CGColor(gray: 0.94, alpha: 1)
            let muted = CGColor(red: 0.40, green: 0.56, blue: 0.59, alpha: 1)
            let gray = CGColor(gray: 0.48, alpha: 1)
            let dark = CGColor(gray: 0.10, alpha: 1)
            let red = CGColor(red: 1, green: 0.18, blue: 0.12, alpha: 1)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setShouldAntialias(true)
            context.setLineCap(.round); context.setLineJoin(.round)

            func rectangle(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: CGColor) {
                context.setFillColor(color)
                context.fill(CGRect(x: x, y: height - y - h, width: w, height: h))
            }
            func text(_ value: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 9,
                      color: CGColor? = nil, centered: Bool = false) {
                let base = CTFontCreateUIFontForLanguage(.system, size, nil)
                    ?? CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
                let font = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color ?? white
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
                let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                context.textPosition = CGPoint(x: centered ? x - lineWidth / 2 : x,
                                                y: CGFloat(height) - y - CTFontGetAscent(font))
                CTLineDraw(line, context)
            }
            func ring(_ center: CGPoint, radius: CGFloat, color: CGColor, fraction: CGFloat? = nil) {
                context.setStrokeColor(color); context.setLineWidth(3)
                context.beginPath()
                if let fraction {
                    let start = -CGFloat.pi * 0.75
                    context.addArc(center: CGPoint(x: center.x, y: CGFloat(height) - center.y), radius: radius,
                        startAngle: start, endAngle: start - 1.5 * .pi * fraction, clockwise: true)
                } else {
                    context.addEllipse(in: CGRect(x: center.x - radius, y: CGFloat(height) - center.y - radius,
                                                  width: radius * 2, height: radius * 2))
                }
                context.strokePath()
            }
            // All channel symbols share the same 24 × 32 coordinate system.
            // Keep silhouettes legible at native resolution rather than drawing tiny details.
            func icon(_ kind: String, center: CGFloat, top: CGFloat, size: CGFloat, color: CGColor) {
                context.saveGState()
                let scale = size / 32
                context.translateBy(x: center - 12 * scale, y: CGFloat(height) - top)
                context.scaleBy(x: scale, y: -scale)
                context.setFillColor(color); context.setStrokeColor(color)
                context.setLineWidth(2.2)
                switch kind {
                case "MIC":
                    context.addPath(CGPath(roundedRect: CGRect(x: 8, y: 1, width: 8, height: 17), cornerWidth: 4, cornerHeight: 4, transform: nil))
                    context.fillPath()
                    context.move(to: CGPoint(x: 4, y: 12)); context.addLine(to: CGPoint(x: 4, y: 16))
                    context.addCurve(to: CGPoint(x: 20, y: 16), control1: CGPoint(x: 4, y: 27), control2: CGPoint(x: 20, y: 27))
                    context.addLine(to: CGPoint(x: 20, y: 12)); context.strokePath()
                    context.move(to: CGPoint(x: 12, y: 24)); context.addLine(to: CGPoint(x: 12, y: 30))
                    context.move(to: CGPoint(x: 7, y: 30)); context.addLine(to: CGPoint(x: 17, y: 30)); context.strokePath()
                case "INST":
                    context.fill(CGRect(x: 11, y: 2, width: 3, height: 21))
                    context.fill(CGRect(x: 10, y: 0, width: 5, height: 6))
                    let body = CGMutablePath()
                    body.move(to: CGPoint(x: 10, y: 17))
                    body.addCurve(to: CGPoint(x: 6, y: 16), control1: CGPoint(x: 8, y: 20), control2: CGPoint(x: 7, y: 18))
                    body.addCurve(to: CGPoint(x: 5, y: 23), control1: CGPoint(x: 2, y: 15), control2: CGPoint(x: 7, y: 21))
                    body.addCurve(to: CGPoint(x: 3, y: 29), control1: CGPoint(x: 2, y: 25), control2: CGPoint(x: 2, y: 27))
                    body.addCurve(to: CGPoint(x: 21, y: 29), control1: CGPoint(x: 5, y: 34), control2: CGPoint(x: 20, y: 34))
                    body.addCurve(to: CGPoint(x: 19, y: 23), control1: CGPoint(x: 23, y: 26), control2: CGPoint(x: 21, y: 25))
                    body.addCurve(to: CGPoint(x: 18, y: 16), control1: CGPoint(x: 17, y: 21), control2: CGPoint(x: 22, y: 15))
                    body.addCurve(to: CGPoint(x: 14, y: 17), control1: CGPoint(x: 17, y: 18), control2: CGPoint(x: 16, y: 20))
                    body.closeSubpath(); context.addPath(body); context.fillPath()
                case "MAIN":
                    context.move(to: CGPoint(x: 1, y: 13)); context.addLine(to: CGPoint(x: 6, y: 13))
                    context.addLine(to: CGPoint(x: 12, y: 7)); context.addLine(to: CGPoint(x: 12, y: 25))
                    context.addLine(to: CGPoint(x: 6, y: 19)); context.addLine(to: CGPoint(x: 1, y: 19))
                    context.closePath(); context.fillPath()
                    for offset in [CGFloat(0), 5] {
                        context.move(to: CGPoint(x: 16 + offset, y: 10 - offset))
                        context.addCurve(to: CGPoint(x: 16 + offset, y: 22 + offset),
                            control1: CGPoint(x: 21 + offset, y: 13 - offset / 2),
                            control2: CGPoint(x: 21 + offset, y: 19 + offset / 2))
                        context.strokePath()
                    }
                case "HP":
                    context.move(to: CGPoint(x: 3, y: 22))
                    context.addLine(to: CGPoint(x: 3, y: 14))
                    context.addArc(center: CGPoint(x: 12, y: 14), radius: 9,
                                   startAngle: .pi, endAngle: 0, clockwise: false)
                    context.addLine(to: CGPoint(x: 21, y: 22)); context.strokePath()
                    for x in [CGFloat(2), 18] {
                        context.addPath(CGPath(roundedRect: CGRect(x: x, y: 17, width: 4, height: 9), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                        context.fillPath()
                    }
                default:
                    context.addPath(CGPath(roundedRect: CGRect(x: 4, y: 7, width: 16, height: 18), cornerWidth: 4, cornerHeight: 4, transform: nil))
                    context.strokePath()
                    context.fillEllipse(in: CGRect(x: 10, y: 13, width: 4, height: 4))
                }
                context.restoreGState()
            }
            func meter(_ value: Double?, peak: Double? = nil, over: Bool = false,
                       x: Int, y: Int, width: Int, height: Int) {
                rectangle(x, y, width, height, dark)
                let fill = Int(Double(height) * DuetbarMeterScale.fraction(value ?? -.infinity))
                let greenEnd = Int(Double(height) * DuetbarMeterScale.fraction(-12))
                let yellowEnd = Int(Double(height) * DuetbarMeterScale.fraction(-3))
                for (low, high, color) in [(0, greenEnd, CGColor(red: 0.12, green: 0.85, blue: 0.3, alpha: 1)),
                    (greenEnd, yellowEnd, CGColor(red: 1, green: 0.75, blue: 0.1, alpha: 1)),
                    (yellowEnd, height, red)] {
                    let top = min(fill, high)
                    if top > low { rectangle(x, y + height - top, width, top - low, color) }
                }
                if let peak, peak.isFinite && peak >= -60 {
                    let position = min(height - 1, Int(Double(height) * DuetbarMeterScale.fraction(peak)))
                    rectangle(x, y + height - 1 - position, width, 1, white)
                }
                if over { rectangle(x, y - 4, width, 2, red) }
            }
            let selected = min(3, max(0, snapshot.selected))
            if !snapshot.focused {
                // Overview is deliberately text-free: icons and meters only.
                for column in 0..<4 {
                    let center = column * 40 + 20
                    let color = column == selected ? white : muted
                    let kind = column < 2 ? snapshot.inputs[column].mode : column == 2 ? "MAIN" : "HP"
                    icon(kind, center: CGFloat(center), top: 4, size: 25, color: color)
                    if column < 2 {
                        let input = snapshot.inputs[column]
                        if input.phantom == true && input.mode == "MIC" {
                            ring(CGPoint(x: center, y: 16), radius: 14, color: blue)
                        }
                        meter(input.meter, peak: input.peak, over: input.over,
                              x: center - 5, y: 39, width: 10, height: 80)
                    } else {
                        let output = snapshot.outputs[column - 2]
                        meter(output.meters?.first, peak: output.peaks?.first, over: output.overs?.first ?? false,
                              x: center - 6, y: 39, width: 5, height: 80)
                        meter(output.meters?.last, peak: output.peaks?.last, over: output.overs?.last ?? false,
                              x: center + 1, y: 39, width: 5, height: 80)
                        if output.muted == true { rectangle(center - 6, 32, 12, 2, muted) }
                    }
                }
            } else {
                let isInput = selected < 2
                let input = snapshot.inputs[min(selected, 1)]
                let output = snapshot.outputs[max(0, selected - 2)]
                text(["IN 1", "IN 2", "OUT", "HP"][selected], 80, 4, size: 14, color: white, centered: true)
                let kind = isInput ? input.mode : selected == 2 ? "MAIN" : "HP"
                icon(kind, center: 132, top: 38, size: 34, color: white)
                if isInput && input.phantom == true && input.mode == "MIC" {
                    ring(CGPoint(x: 132, y: 55), radius: 21, color: blue)
                }
                if isInput {
                    meter(input.meter, peak: input.peak, over: input.over, x: 6, y: 36, width: 9, height: 82)
                    for tick in [-6.0, -12, -24, -48] {
                        let y = 36 + Int(82 * (1 - DuetbarMeterScale.fraction(tick)))
                        rectangle(17, y, 3, 1, gray)
                    }
                } else {
                    meter(output.meters?.first, peak: output.peaks?.first, over: output.overs?.first ?? false,
                          x: 6, y: 36, width: 5, height: 82)
                    meter(output.meters?.last, peak: output.peaks?.last, over: output.overs?.last ?? false,
                          x: 13, y: 36, width: 5, height: 82)
                }
                let value = isInput ? input.gain : output.level
                let fraction = value.map { isInput ? CGFloat($0) / (input.mode == "INST" ? 65 : 75) : CGFloat($0 + 64) / 64 }
                let center = CGPoint(x: 78, y: 61)
                ring(center, radius: 26, color: dark, fraction: 1)
                if let fraction, fraction > 0 {
                    ring(center, radius: 26, color: mint, fraction: min(1, max(0, fraction)))
                }
                let valueText = value.map(String.init)
                    ?? (isInput && ["+4", "-10"].contains(input.mode) ? input.mode : "—")
                text(valueText, 78, 49, size: 24, centered: true)
                if isInput {
                    text("Ø", 57, 96, size: 14, color: input.phase == true ? mint : gray, centered: true)
                    text("SL", 89, 98, size: 11, color: input.softLimit == true ? mint : gray, centered: true)
                    text("GP", 123, 98, size: 11, color: snapshot.grouped ? mint : gray, centered: true)
                    let peak = input.over ? "CLIP" : input.peak.isFinite ? String(format: "PK %.1f", input.peak) : "PK −∞"
                    text(peak, 87, 114, size: 11, color: input.over ? red : white, centered: true)
                } else {
                    text(value == nil ? "Set in app" : output.muted == true ? "MUTE" : "dB", 78, 100,
                         size: value == nil ? 11 : 13, color: white, centered: true)
                }
            }
            context.flush()
            let bytes = storage.bindMemory(to: UInt8.self)
            var pixels: [UInt8] = []
            pixels.reserveCapacity(width * height * 2)
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let color = UInt16(bytes[offset] >> 3) << 11 |
                    UInt16(bytes[offset + 1] >> 2) << 5 | UInt16(bytes[offset + 2] >> 3)
                pixels.append(UInt8(color >> 8)); pixels.append(UInt8(color & 255))
            }
            return pixels
        }
    }
}
