import AppKit
import SwiftUI

/// The popover shares the console's controller; only native meter surfaces observe meter ticks.
struct MenuBarControls: View {
    @ObservedObject var model: ConsoleModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private var ready: Bool { model.usbConnected && !model.outputsNeedSetup && !model.running }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if let mark = OpenDuet.brandMark {
                    Image(nsImage: mark).resizable().frame(width: 28, height: 28)
                }
                Text("OpenDuet").font(.title3.weight(.semibold))
                Spacer()
                Circle().fill(model.usbConnected ? Color.mint : Color.secondary).frame(width: 6, height: 6)
                Text(model.usbConnected ? "Connected" : "Disconnected").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                input(0)
                input(1)
                output(headphone: true)
                output(headphone: false)
            }
            if model.outputsNeedSetup && model.usbConnected {
                Text("Set up outputs in the full mixer to enable output controls.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(model.audio.map { String(format: "%g kHz", $0.sampleRate / 1000) } ?? "No audio device").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show mixer", action: showMixer)
                    .accessibilityIdentifier("quick-mixer-show-console")
                Button("Hide mixer") {
                    AppLifecycle.noteHideRequest()
                    dismissWindow(id: "console")
                }
                    .accessibilityIdentifier("quick-mixer-hide-console")
                SettingsLink { Image(systemName: "gearshape") }.help("OpenDuet settings")
                Menu {
                    Button("Quit OpenDuet", role: .destructive) { AppLifecycle.quitFromQuickMixer() }
                        .accessibilityIdentifier("quick-mixer-quit")
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("More actions")
            }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(18).frame(width: 660)
        .background(Color(red: 0.075, green: 0.085, blue: 0.10))
        .preferredColorScheme(.dark)
    }

    private func showMixer() {
        openWindow(id: "console")
        // A newly created SwiftUI Window may not be in NSApp.windows until the next turn.
        Task { @MainActor in
            await Task.yield()
            ConsoleWindowActions.reveal()
        }
    }

    private func input(_ index: Int) -> some View {
        let draft = model.inputs[index]
        let gain = Binding<Double>(get: {
            model.inputs[index].mode == .instrument ? model.inputs[index].instrumentGain : model.inputs[index].micGain
        }, set: { model.setQuickInputGain($0, input: index) })
        return VStack(spacing: 10) {
            Label("Input \(index + 1)", systemImage: draft.mode == .instrument ? "guitars" : "mic")
                .font(.subheadline.weight(.medium))
            NativeMeterReadout(model: model, kind: .input(index), compact: true).frame(height: 155)
            ConsoleDial(value: gain, range: 0...(draft.mode == .instrument ? 65 : 75), label: "GAIN", compact: true)
                .disabled(!model.usbConnected || model.running || (draft.mode != .mic && draft.mode != .instrument))
            Picker("Input \(index + 1) source", selection: Binding(get: { model.inputs[index].mode }, set: { model.setInputMode($0, input: index) })) {
                Text("Mic").tag(InputControlPacket.Mode.mic)
                Text("Instrument").tag(InputControlPacket.Mode.instrument)
                Text("+4 dBu").tag(InputControlPacket.Mode.plus4)
                Text("−10 dBV").tag(InputControlPacket.Mode.minus10)
            }.labelsHidden()
            Toggle("48 V", isOn: Binding(get: { model.inputs[index].phantom ?? false }, set: { model.setPhantom($0, input: index) }))
                .disabled(draft.mode != .mic)
            Toggle("Soft Limit", isOn: inputSwitch(index, key: \.softLimit))
            Toggle("Phase", isOn: inputSwitch(index, key: \.phase))
        }
        .toggleStyle(.button).controlSize(.small)
        .disabled(!model.usbConnected || model.running)
        .frame(maxWidth: .infinity).padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func inputSwitch(_ index: Int, key: WritableKeyPath<ConsoleModel.InputDraft, Bool?>) -> Binding<Bool> {
        Binding(get: { model.inputs[index][keyPath: key] ?? false }, set: {
            model.setQuickInputSwitch($0, input: index, phase: key == \.phase)
        })
    }

    private func output(headphone: Bool) -> some View {
        let draft = headphone ? model.headphones : model.main
        return VStack(spacing: 10) {
            Label(headphone ? "Headphones" : "Speakers", systemImage: headphone ? "headphones" : "speaker.wave.2")
                .font(.subheadline.weight(.medium))
            NativeMeterReadout(model: model, kind: .output(headphone: headphone), compact: true).frame(height: 155)
            ConsoleDial(value: Binding(get: { headphone ? model.headphones.level : model.main.level },
                                      set: { model.setOutputLevel($0, headphone: headphone) }),
                        range: -64...0, label: "LEVEL", compact: true)
            Toggle("Mute", isOn: Binding(get: { headphone ? model.headphones.muted : model.main.muted },
                                        set: { model.setOutputMute($0, headphone: headphone) }))
            Toggle("Dim", isOn: Binding(get: { headphone ? model.headphones.dimmed : model.main.dimmed },
                                       set: { model.setOutputDim($0, headphone: headphone) }))
            Toggle("Mono", isOn: Binding(get: { headphone ? model.headphones.mono : model.main.mono }, set: {
                model.setQuickOutputMono($0, headphone: headphone)
            }))
            Text(draft.route.title).font(.caption2).foregroundStyle(.secondary)
        }
        .toggleStyle(.button).controlSize(.small)
        .disabled(!ready)
        .frame(maxWidth: .infinity).padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}
