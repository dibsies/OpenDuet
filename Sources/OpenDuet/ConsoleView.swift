import SwiftUI
import AppKit

struct ConsoleView: View {
    @ObservedObject var model: ConsoleModel
    @AppStorage("OpenDuet.monitorMixerExpanded") private var monitorMixerExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.usbConnected && (model.outputsNeedSetup || !model.hardwareEnabled) {
                HStack(spacing: 12) {
                    Label("Set up Duet", systemImage: "slider.horizontal.3")
                    Text("Starts muted with the shown gains and routing. 48 V is unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Initialize muted", action: model.initializeMuted).disabled(model.running)
                }.padding(.horizontal, 22).padding(.vertical, 10)
                    .background(.mint.opacity(0.08))
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView { sidebar }.frame(width: 215)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("CHANNELS").consoleLabel()
                            Spacer()
                            Toggle("Link input gains", isOn: $model.linkInputs).toggleStyle(.switch).controlSize(.small)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(0..<2) { index in
                                InputStrip(number: index + 1, draft: $model.inputs[index],
                                           model: model,
                                           phantomChanged: { model.setPhantom($0, input: index) },
                                           modeChanged: { model.setInputMode($0, input: index) })
                            }
                            VStack(alignment: .leading, spacing: 16) {
                                stripHeading("PLAYBACK", symbol: "play.rectangle")
                                Text("Stereo return").font(.title3.weight(.semibold))
                                Picker("Mixer return", selection: Binding(get: { model.mixerSource }, set: model.setLiveMixerSource)) {
                                    ForEach(MixerCoefficients.PlaybackSource.allCases) { Text($0.title).tag($0) }
                                }.labelsHidden().disabled(!model.usbConnected || model.outputsNeedSetup)
                                NativeMeterReadout(model: model, kind: .playback, compact: true).frame(height: 235)
                                Spacer(minLength: 0)
                            }.consoleCard().frame(maxWidth: .infinity, minHeight: 400)
                            VStack(spacing: 14) {
                                OutputStrip(title: "HEADPHONES", symbol: "headphones", draft: $model.headphones,
                                            model: model, headphone: true,
                                            levelChanged: { model.setOutputLevel($0, headphone: true) },
                                            muteChanged: { model.setOutputMute($0, headphone: true) },
                                            dimChanged: { model.setOutputDim($0, headphone: true) })
                                OutputStrip(title: "MAIN OUT", symbol: "hifispeaker.2", draft: $model.main,
                                            model: model, headphone: false,
                                            levelChanged: { model.setOutputLevel($0, headphone: false) },
                                            muteChanged: { model.setOutputMute($0, headphone: false) },
                                            dimChanged: { model.setOutputDim($0, headphone: false) })
                            }.frame(width: 235)
                        }
                        DisclosureGroup("Direct monitor mixer", isExpanded: $monitorMixerExpanded) {
                            if monitorMixerExpanded {
                                MixerPanel(state: $model.mixer, running: model.running || !model.usbConnected || model.outputsNeedSetup,
                                           changed: model.enqueueLiveMixer)
                            }
                        }.font(.subheadline.weight(.medium))
                    }.padding(20).disabled(model.running)
                }
            }
            Divider()
            HStack {
                if model.running { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).lineLimit(1).help(model.status)
                Spacer()
                Text("BETA 0.4.28").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.08))
        .tint(.mint)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1120, minHeight: 740)
        .onAppear { model.refreshAudio() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let mark = OpenDuet.brandMark {
                Image(nsImage: mark).resizable().interpolation(.high).frame(width: 34, height: 34)
            } else {
                Image(systemName: "waveform.circle.fill").font(.system(size: 32)).foregroundStyle(.mint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenDuet").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("DUET 2 · USB AUDIO CONTROL").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.audio == nil ? "Audio unavailable" : "Core Audio connected", systemImage: "circle.fill")
                .font(.caption).foregroundStyle(model.audio == nil ? .orange : .mint)
            Button(model.usbConnected ? "Release USB" : model.connectionRequested ? "Cancel connection" : "Connect USB") {
                if model.connectionRequested { model.disconnectUSB() } else { model.connectUSB() }
            }.disabled(model.running)
        }.padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            stripHeading("SYSTEM", symbol: "slider.horizontal.3")
            VStack(alignment: .leading, spacing: 6) {
                Text("Duet USB").font(.headline)
                Text("2 inputs · 4 outputs").font(.caption).foregroundStyle(.secondary)
                if let audio = model.audio {
                    Picker("Sample rate", selection: Binding(get: { model.selectedRate }, set: {
                        model.selectedRate = $0; model.applyRate()
                    })) {
                        ForEach(audio.supportedRates, id: \.self) { rate in
                            Text("\(rate / 1000, specifier: "%.1f") kHz").tag(rate)
                        }
                    }.labelsHidden().help("Changing sample rate interrupts audio. Stop recording and playback first.")
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("METERS").consoleLabel()
                Picker("Peak hold", selection: $model.peakHold) {
                    ForEach(MeterHold.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Over hold", selection: $model.overHold) {
                    ForEach(MeterHold.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("Clear peaks & clips", action: model.clearMeterHolds)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("MAIN LINE LEVEL").consoleLabel()
                Picker("Reference", selection: Binding(get: { model.mainPlus4 }, set: model.setLiveReference)) {
                    Text("+4 dBu").tag(true)
                    Text("−10 dBV").tag(false)
                }.labelsHidden().disabled(!model.usbConnected || model.outputsNeedSetup)
                    .help("Changes the analog main-output reference level.")
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("HARDWARE").consoleLabel()
                Label(model.hardwareEnabled ? "Knob ready" : "Needs setup", systemImage: model.hardwareEnabled ? "checkmark.circle" : "circle")
                    .font(.caption).foregroundStyle(model.hardwareEnabled ? .mint : .secondary)
                Text(model.selectedControl.title).font(.caption).foregroundStyle(.secondary)
                Picker("Touchpad A", selection: $model.touchpadA) {
                    ForEach(PhysicalController.TouchpadAction.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Touchpad B", selection: $model.touchpadB) {
                    ForEach(PhysicalController.TouchpadAction.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Hardware screen", isOn: Binding(get: { model.displayEnabled }, set: model.setDisplayEnabled))
                    .disabled(!model.usbConnected).font(.caption)
            }
            Spacer(minLength: 12)
        }.padding(20).disabled(model.running)
    }
}

private struct InputStrip: View {
    let number: Int
    @Binding var draft: ConsoleModel.InputDraft
    let model: ConsoleModel
    let phantomChanged: (Bool) -> Void
    let modeChanged: (InputControlPacket.Mode) -> Void

    private var gain: Binding<Double> {
        Binding(get: { draft.mode == .instrument ? draft.instrumentGain : draft.micGain },
                set: { model.setQuickInputGain($0, input: number - 1) })
    }
    private func switchValue(_ key: WritableKeyPath<ConsoleModel.InputDraft, Bool?>) -> Binding<Bool> {
        Binding(get: { draft[keyPath: key] ?? false }, set: { model.setQuickInputSwitch($0, input: number - 1, phase: key == \.phase) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            stripHeading("ANALOG IN \(number)", symbol: draft.mode == .instrument ? "guitars" : "mic")
            Picker("Source", selection: Binding(get: { draft.mode }, set: { modeChanged($0) })) {
                Text("Mic").tag(InputControlPacket.Mode.mic)
                Text("Instrument").tag(InputControlPacket.Mode.instrument)
                Text("+4 dBu").tag(InputControlPacket.Mode.plus4)
                Text("−10 dBV").tag(InputControlPacket.Mode.minus10)
            }.labelsHidden()
            ConsoleDial(value: gain, range: 0...(draft.mode == .instrument ? 65 : 75), label: "GAIN")
                .disabled(draft.mode == .plus4 || draft.mode == .minus10)
            NativeMeterReadout(model: model, kind: .input(number - 1)).frame(height: 142)
            Toggle("48 V", isOn: Binding(get: { draft.phantom ?? false }, set: { phantomChanged($0) })).disabled(draft.mode != .mic)
            Toggle("Soft Limit", isOn: switchValue(\.softLimit))
            Toggle("Invert phase", isOn: switchValue(\.phase))
            Spacer(minLength: 8)
        }.consoleCard().frame(maxWidth: .infinity, minHeight: 400).disabled(!model.usbConnected)
    }
}

private struct OutputStrip: View {
    let title: String
    let symbol: String
    @Binding var draft: ConsoleModel.OutputDraft
    let model: ConsoleModel
    let headphone: Bool
    let levelChanged: (Double) -> Void
    let muteChanged: (Bool) -> Void
    let dimChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stripHeading(title, symbol: symbol)
            Picker("Source", selection: Binding(get: { draft.route }, set: { model.setLiveOutputRoute($0, headphone: headphone) })) {
                ForEach(OutputControlPacket.RouteSelector.allCases) { Text($0.title).tag($0) }
            }.labelsHidden()
            ConsoleDial(value: Binding(get: { draft.level }, set: { levelChanged($0) }), range: -64...0, label: "LEVEL", compact: true)
            HStack {
                Toggle("Mute", isOn: Binding(get: { draft.muted }, set: { muteChanged($0) }))
                Toggle("Dim", isOn: Binding(get: { draft.dimmed }, set: { dimChanged($0) }))
                Toggle("Mono", isOn: Binding(get: { draft.mono }, set: { model.setQuickOutputMono($0, headphone: headphone) }))
            }.toggleStyle(.button).controlSize(.small)
            NativeMeterReadout(model: model, kind: .output(headphone: headphone)).frame(height: 55)
        }.consoleCard().disabled(!model.usbConnected || model.outputsNeedSetup)
    }
}

private struct RawMeterReadout: View {
    @ObservedObject var presentation: MeterPresentation
    let model: ConsoleModel
    var body: some View {
        GroupBox("Raw meter snapshot") {
            HStack {
                ForEach(model.meters.indices, id: \.self) { index in
                    VStack {
                        Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                        ProgressView(value: DuetbarMeterScale.fraction(model.meters[index])).tint(.mint)
                        Text(model.meters[index].isFinite ? String(format: "%.1f", model.meters[index]) : "−∞")
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
    }
}

@MainActor private final class DialDragState: ObservableObject { var start: Double? }

struct ConsoleDial: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    var compact = false
    @StateObject private var drag = DialDragState()
    @GestureState private var dragging = false
    private var diameter: Double { compact ? 68 : 94 }
    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.white.opacity(0.10), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().trim(from: 0, to: 0.75).stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * fraction).stroke(.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(135))
                VStack(spacing: 2) {
                    Text("\(Int(value))").font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("dB").font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 3).updating($dragging) { _, active, _ in active = true }.onChanged { gesture in
                    if drag.start == nil { drag.start = value }
                    value = RelativeDial.value(start: drag.start ?? value, verticalTranslation: gesture.translation.height,
                                               fine: NSEvent.modifierFlags.contains(.shift), range: range)
                }.onEnded { _ in drag.start = nil })
                .onChange(of: dragging) { _, active in if !active { drag.start = nil } }
                .help("Drag up/down to adjust. Hold Shift for fine adjustment.")
                .padding(6)
            Text(label).consoleLabel()
            Slider(value: $value, in: range).accessibilityLabel(label)
        }.frame(maxWidth: .infinity)
    }
}

private func stripHeading(_ title: String, symbol: String) -> some View {
    HStack {
        Image(systemName: symbol).foregroundStyle(.mint)
        Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.8)
    }
}

private extension View {
    func consoleCard() -> some View {
        padding(16).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07), lineWidth: 1))
    }
    func consoleLabel() -> some View {
        font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
    }
}

struct ConsoleDiagnosticsView: View {
    @ObservedObject var model: ConsoleModel
    let report: String
    let refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Diagnostics").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Refresh") { model.refreshAudio(); model.readModes(); refresh() }
                        .disabled(model.running)
                }
                Text(model.status).textSelection(.enabled)
                if !model.details.isEmpty {
                    DisclosureGroup("Last operation") {
                        Text(model.details).font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GroupBox("Device inventory") {
                    Text(report).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if model.metersAvailable {
                    DisclosureGroup("Raw meter lanes", isExpanded: $model.showRawMeters) {
                        if model.showRawMeters { RawMeterReadout(presentation: model.meterPresentation, model: model) }
                    }
                }
                Text("Review device names and paths before sharing diagnostics.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.preferredColorScheme(.dark)
    }
}
