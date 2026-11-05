import AppKit
import Combine
import CoreText
import SwiftUI

/// A live drawing surface: meter ticks never invalidate a SwiftUI view tree.
@MainActor
struct NativeMeterReadout: NSViewRepresentable {
    enum Kind: Equatable { case input(Int), playback, output(headphone: Bool) }
    let model: ConsoleModel
    let kind: Kind
    var compact = false

    func makeNSView(context: Context) -> MeterReadoutNSView {
        let view = MeterReadoutNSView(model: model, kind: kind)
        view.compact = compact
        return view
    }
    func updateNSView(_ view: MeterReadoutNSView, context: Context) { view.compact = compact; view.configure(model: model, kind: kind) }
}

@MainActor
final class MeterReadoutNSView: NSView {
    var compact = false { didSet { if compact != oldValue { lastInvalidation = nil; needsDisplay = true } } }
    private weak var model: ConsoleModel?
    private var kind: NativeMeterReadout.Kind
    private var subscription: AnyCancellable?
    private var visibilitySubscription: AnyCancellable?
    private struct TextKey: Hashable {
        let value: String
        let fontName: String
        let size: CGFloat
        let color: NSColor
    }
    private var textCache: [TextKey: CTLine] = [:]
    private struct RenderKey: Equatable {
        let size: NSSize
        let values: [Int]
        let caption: String
    }
    private var lastInvalidation: RenderKey?
    private static let readoutFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let smallFont = NSFont.systemFont(ofSize: 9)
    private static let scaleFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    override var isFlipped: Bool { true }

    init(model: ConsoleModel, kind: NativeMeterReadout.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        configure(model: model, kind: kind)
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
    }
    required init?(coder: NSCoder) { nil }

    func configure(model: ConsoleModel, kind: NativeMeterReadout.Kind) {
        guard self.model !== model || self.kind != kind else { return }
        if self.model !== model {
            self.model = model
            subscription = model.meterPresentation.objectWillChange.sink { [weak self] _ in
                _ = self?.refreshFromMeters()
            }
        }
        self.kind = kind
        lastInvalidation = nil
        refreshFromMeters()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibilitySubscription = nil
        guard let window else { return }
        let center = NotificationCenter.default
        visibilitySubscription = center.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .merge(with: center.publisher(for: NSApplication.didHideNotification),
                   center.publisher(for: NSApplication.didUnhideNotification))
            .sink { [weak self, weak window] notification in
                if let changedWindow = notification.object as? NSWindow, changedWindow !== window { return }
                self?.lastInvalidation = nil
                _ = self?.refreshFromMeters()
            }
        lastInvalidation = nil
        refreshFromMeters()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        lastInvalidation = nil
        needsDisplay = true
    }

    @discardableResult
    func refreshFromMeters(force: Bool = false) -> Bool {
        guard let model else { return false }
        if !force {
            guard let window, window.isVisible, !window.isMiniaturized,
                  (!NSApplication.shared.isHidden || compact), window.occlusionState.contains(.visible) else {
                lastInvalidation = nil
                return false
            }
        }
        func reading(_ value: Double?, scale: Double) -> Int {
            guard let value else { return Int.min }
            guard value.isFinite else { return Int.min + 1 }
            return Int((value * scale).rounded())
        }
        func pixel(_ value: Double?, extent: CGFloat) -> Int {
            guard let value else { return -2 }
            guard value.isFinite else { return -1 }
            return Int(DuetbarMeterScale.fraction(value) * max(1, extent))
        }
        let key: RenderKey
        switch kind {
        case .input(let index):
            let level = model.inputMeter(index), peak = model.inputPeak(index)
            key = RenderKey(size: bounds.size, values: [reading(level, scale: 10), reading(peak, scale: 10),
                pixel(level, extent: bounds.height - 8), pixel(peak, extent: bounds.height - 8), model.inputOver(index) ? 1 : 0], caption: "input")
        case .playback, .output:
            let levels: [Double]?, peaks: [Double]?, overs: [Bool]?, caption: String
            if case .output(let headphone) = kind {
                levels = model.outputMeters(headphone: headphone); peaks = model.outputPeaks(headphone: headphone)
                overs = model.outputOvers(headphone: headphone); caption = model.outputMeterCaption(headphone: headphone)
            } else {
                levels = model.playbackMeters; peaks = model.playbackPeaks; overs = model.playbackOvers; caption = "Playback signal"
            }
            var values: [Int] = []
            for channel in 0..<2 {
                let level = levels?.count == 2 ? levels?[channel] : nil
                let peak = peaks?.count == 2 ? peaks?[channel] : nil
                let over = overs?.count == 2 ? overs?[channel] ?? false : false
                values += [reading(level, scale: 1), pixel(level, extent: compact ? bounds.height - 25 : bounds.width - 48),
                           pixel(peak, extent: compact ? bounds.height - 25 : bounds.width - 48),
                           peak.map { $0.isFinite && $0 >= -60 } == true ? 1 : 0, over ? 1 : 0]
            }
            key = RenderKey(size: bounds.size, values: values, caption: caption)
        }
        guard key != lastInvalidation else { return false }
        lastInvalidation = key
        needsDisplay = true
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textCache.removeAll(keepingCapacity: true)
        lastInvalidation = nil
        needsDisplay = true
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, font: NSFont? = nil, color: NSColor = .secondaryLabelColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let font = font ?? Self.smallFont
        let key = TextKey(value: text, fontName: font.fontName, size: font.pointSize, color: color)
        let line: CTLine
        if let cached = textCache[key] { line = cached }
        else {
            if textCache.count >= 256 { textCache.removeAll(keepingCapacity: true) }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
            ]
            line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            textCache[key] = line
        }
        context.saveGState()
        context.translateBy(x: x, y: y + font.ascender)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
    private func bar(level: Double, peak: Double, over: Bool, rect: NSRect, vertical: Bool) {
        NSColor.white.withAlphaComponent(0.08).setFill(); rect.fill()
        let amount = DuetbarMeterScale.fraction(level)
        let bounds = [0.0, DuetbarMeterScale.fraction(-12), DuetbarMeterScale.fraction(-3), 1.0]
        let colors: [NSColor] = [.systemGreen, .systemYellow, .systemRed]
        for index in 0..<3 {
            let low = bounds[index], high = min(amount, bounds[index + 1])
            guard high > low else { continue }
            let segment = vertical
                ? NSRect(x: rect.minX, y: rect.maxY - rect.height * high, width: rect.width, height: rect.height * (high - low))
                : NSRect(x: rect.minX + rect.width * low, y: rect.minY, width: rect.width * (high - low), height: rect.height)
            colors[index].setFill(); segment.fill()
        }
        if peak.isFinite && peak >= -60 {
            let position = DuetbarMeterScale.fraction(peak)
            let marker = vertical
                ? NSRect(x: rect.minX, y: max(rect.minY, rect.maxY - rect.height * position - 1), width: rect.width, height: 1)
                : NSRect(x: min(rect.maxX - 1, rect.minX + rect.width * position), y: rect.minY, width: 1, height: rect.height)
            NSColor.white.setFill(); marker.fill()
        }
        if over {
            NSColor.systemRed.setFill()
            (vertical ? NSRect(x: rect.minX, y: rect.minY - 4, width: rect.width, height: 3)
                      : NSRect(x: rect.maxX - 3, y: rect.minY, width: 3, height: rect.height)).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        guard let model else { return }
        if compact {
            let levels: [Double]?, peaks: [Double]?, overs: [Bool]?
            switch kind {
            case .input(let index):
                levels = model.inputMeter(index).map { [$0] }
                peaks = model.inputPeak(index).map { [$0] }
                overs = [model.inputOver(index)]
                setAccessibilityLabel("Input \(index + 1) signal")
            case .output(let headphone):
                levels = model.outputMeters(headphone: headphone)
                peaks = model.outputPeaks(headphone: headphone)
                overs = model.outputOvers(headphone: headphone)
                setAccessibilityLabel(headphone ? "Headphone signal" : "Main output signal")
            case .playback:
                levels = model.playbackMeters; peaks = model.playbackPeaks; overs = model.playbackOvers
            }
            let count = levels?.count ?? (kind == .input(0) || kind == .input(1) ? 1 : 2)
            let left = bounds.midX - CGFloat(count * 14 + (count - 1) * 4) / 2 - 8
            let height = max(1, bounds.height - 25)
            for channel in 0..<count {
                bar(level: levels?[channel] ?? -.infinity, peak: peaks?[channel] ?? -.infinity,
                    over: overs?[channel] ?? false,
                    rect: NSRect(x: left + CGFloat(channel * 18), y: 5, width: 14, height: height), vertical: true)
            }
            for tick in [0.0, -12, -24, -40, -60] {
                let y = 5 + height * (1 - DuetbarMeterScale.fraction(tick))
                label(String(Int(tick)), x: left + CGFloat(count * 18) + 1, y: y - 5, font: Self.scaleFont)
            }
            setAccessibilityValue(levels?.map { $0.isFinite ? String(format: "%.1f", $0) : "−∞" }.joined(separator: ", ").appending(" dBFS") ?? "Unknown")
            return
        }
        switch kind {
        case .input(let index):
            let level = model.inputMeter(index), peak = model.inputPeak(index), over = model.inputOver(index)
            let meter = NSRect(x: 1, y: 4, width: 12, height: max(1, bounds.height - 8))
            bar(level: level ?? -.infinity, peak: peak ?? -.infinity, over: over, rect: meter, vertical: true)
            for tick in [0.0, -6, -12, -24, -40, -60] {
                let y = meter.maxY - meter.height * DuetbarMeterScale.fraction(tick)
                NSColor.secondaryLabelColor.setFill(); NSRect(x: 16, y: y, width: 4, height: 1).fill()
                label(String(Int(tick)), x: 24, y: y - 5, font: Self.scaleFont)
            }
            let value = level.map { $0.isFinite ? String(format: "%.1f dBFS", $0) : "−∞ dBFS" } ?? "Not connected"
            let held = peak.map { $0.isFinite ? String(format: "Peak %.1f", $0) : "Peak −∞" } ?? "Peak —"
            let headroom = over ? "CLIP" : peak.map { $0.isFinite ? String(format: "%.1f dB headroom", max(0, -$0)) : "No signal" } ?? "No signal"
            label(value, x: 60, y: 43, font: Self.readoutFont, color: .labelColor)
            label(held, x: 60, y: 64, font: Self.readoutFont, color: .labelColor)
            label(headroom, x: 60, y: 85, font: Self.readoutFont, color: over ? .systemRed : .secondaryLabelColor)
            setAccessibilityLabel("Input \(index + 1) signal")
            setAccessibilityValue([value, held, headroom].joined(separator: ", "))
        case .playback, .output:
            let levels: [Double]?, peaks: [Double]?, overs: [Bool]?, caption: String
            if case .output(let headphone) = kind {
                levels = model.outputMeters(headphone: headphone); peaks = model.outputPeaks(headphone: headphone)
                overs = model.outputOvers(headphone: headphone); caption = model.outputMeterCaption(headphone: headphone)
                setAccessibilityLabel(headphone ? "Headphone signal" : "Main output signal")
            } else {
                levels = model.playbackMeters; peaks = model.playbackPeaks; overs = model.playbackOvers
                caption = "Playback signal"; setAccessibilityLabel("Playback signal")
            }
            var values: [String] = []
            for channel in 0..<2 {
                let level = levels?.count == 2 ? levels![channel] : -.infinity
                let peak = peaks?.count == 2 ? peaks![channel] : -.infinity
                let over = overs?.count == 2 ? overs![channel] : false
                let y = CGFloat(channel * 18 + 2)
                label(channel == 0 ? "L" : "R", x: 0, y: y)
                bar(level: level, peak: peak, over: over, rect: NSRect(x: 14, y: y + 2, width: max(12, bounds.width - 48), height: 9), vertical: false)
                let value = levels == nil ? "—" : level.isFinite ? String(format: "%.0f", level) : "−∞"
                label(value, x: bounds.width - 27, y: y, font: Self.scaleFont, color: .labelColor)
                values.append(value)
            }
            label(levels == nil ? "Apply output routes to show source meters" : caption, x: 0, y: 38)
            setAccessibilityValue(values.joined(separator: ", ") + " dBFS")
        }
    }
}
