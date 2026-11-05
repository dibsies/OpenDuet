/// Host-side physical control behavior. Unknown settings cannot be toggled or raised.
struct PhysicalController {
    enum Target: Int, CaseIterable {
        case input1, input2, main, headphones
        var title: String { ["Input 1", "Input 2", "Main Out", "Headphones"][rawValue] }
    }
    enum TouchpadAction: String, CaseIterable, Codable, Identifiable {
        case none = "None"
        case clearMeters = "Clear meter holds"
        case muteMain = "Main mute", muteHeadphones = "Headphone mute", muteBoth = "Mute both"
        case dimMain = "Main dim", dimHeadphones = "Headphone dim"
        case monoMain = "Main mono", monoHeadphones = "Headphone mono"
        case headphonePlayback = "Headphones: Playback 1–2 / 3–4"
        case headphoneMixer = "Headphones: Playback / Mixer"
        var id: Self { self }
    }
    struct Input {
        var mode: InputControlPacket.Mode?
        var gain: Int?
        var phantom: Bool?
        var softLimit: Bool?
        var phase: Bool?
    }
    struct Output {
        var known = false
        var level = -64
        var muted = true
        var dimmed = false
        var mono: Bool?
        var route: OutputControlPacket.RouteSelector?
    }
    enum Action: Equatable {
        case inputGain(channel: Int, gain: Int, instrument: Bool)
        case output(index: Int, level: Int, muted: Bool, dimmed: Bool)
        case mono(main: Bool, headphones: Bool)
        case routes(main: UInt8, headphones: UInt8)
        case message(String)
        case clearMeters
    }
    var selected = Target.main
    var inputs = [Input(), Input()]
    var outputs = [Output(), Output()]
    var actionA = TouchpadAction.none
    var actionB = TouchpadAction.none
    var linkInputs = false

    mutating func handle(_ event: DeviceEvents) -> [Action] {
        guard event.available else { return [] }
        var actions: [Action] = []
        if event.touchpadA { actions += touch(actionA) }
        if event.touchpadB { actions += touch(actionB) }
        if event.encoderPressed { selected = Target(rawValue: (selected.rawValue + 1) % 4)! }
        let steps = Int(event.clockwiseSteps) - Int(event.counterclockwiseSteps)
        guard steps != 0 else { return actions }
        if selected.rawValue < 2 {
            let index = selected.rawValue
            guard let mode = inputs[index].mode, let gain = inputs[index].gain,
                  mode == .mic || mode == .instrument else {
                return actions + [.message("Apply \(selected.title) settings before using its hardware gain control.")]
            }
            let maximum = mode == .mic ? 75 : 65
            if linkInputs {
                let peer = 1 - index
                guard inputs[peer].mode == mode, let peerGain = inputs[peer].gain else {
                    return actions + [.message("Apply matching input settings before using linked hardware gain.")]
                }
                var gains = [0, 0]; gains[index] = gain; gains[peer] = peerGain
                guard let shifted = GainLink.shifting(gains, by: steps, maximum: maximum) else {
                    return actions + [.message("Apply valid input gains before using linked hardware gain.")]
                }
                if shifted[index] != gain {
                    for channel in [index, peer] {
                        inputs[channel].gain = shifted[channel]
                        actions.append(.inputGain(channel: channel + 1, gain: shifted[channel], instrument: mode == .instrument))
                    }
                }
            } else {
                let next = min(maximum, max(0, gain + steps))
                if next != gain {
                    inputs[index].gain = next
                    actions.append(.inputGain(channel: index + 1, gain: next, instrument: mode == .instrument))
                }
            }
        } else {
            let index = selected == .main ? 0 : 1
            guard outputs[index].known else {
                return actions + [.message("Initialize or apply output settings before using the hardware level control.")]
            }
            let next = min(0, max(-64, outputs[index].level + steps))
            if next != outputs[index].level {
                outputs[index].level = next
                actions.append(outputAction(index))
            }
        }
        return actions
    }

    mutating func invalidate() {
        inputs = [Input(), Input()]
        outputs = [Output(), Output()]
    }

    private func outputAction(_ index: Int) -> Action {
        let output = outputs[index]
        return .output(index: index, level: output.level, muted: output.muted, dimmed: output.dimmed)
    }

    private mutating func touch(_ action: TouchpadAction) -> [Action] {
        if action == .none { return [] }
        if action == .clearMeters { return [.clearMeters] }
        if action == .muteBoth {
            guard outputs.allSatisfy(\.known) else { return [.message("Apply both output settings before toggling their mute state.")] }
            let muted = !outputs.allSatisfy(\.muted)
            for index in 0..<2 { outputs[index].muted = muted }
            return [outputAction(0), outputAction(1)]
        }
        if action == .headphonePlayback || action == .headphoneMixer {
            guard let main = outputs[0].route, let headphones = outputs[1].route else {
                return [.message("Apply output routes before assigning source toggles.")]
            }
            let alternate: OutputControlPacket.RouteSelector = action == .headphonePlayback ? .playback34 : .mixer
            let next: OutputControlPacket.RouteSelector = headphones == .playback12 ? alternate : .playback12
            outputs[1].route = next
            return [.routes(main: main.rawValue, headphones: next.rawValue)]
        }
        let index = [.muteMain, .dimMain, .monoMain].contains(action) ? 0 : 1
        guard outputs[index].known else { return [.message("Apply output settings before using this touchpad action.")] }
        switch action {
        case .muteMain, .muteHeadphones: outputs[index].muted.toggle()
        case .dimMain, .dimHeadphones: outputs[index].dimmed.toggle()
        case .monoMain, .monoHeadphones:
            guard let main = outputs[0].mono, let headphones = outputs[1].mono else {
                return [.message("Apply mono settings before assigning a mono toggle.")]
            }
            outputs[index].mono = !(index == 0 ? main : headphones)
            return [.mono(main: outputs[0].mono!, headphones: outputs[1].mono!)]
        default: return []
        }
        return [outputAction(index)]
    }
}
