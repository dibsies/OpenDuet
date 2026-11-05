import SwiftUI

struct MixerPanel: View {
    @Binding var state: MixerCoefficients.State
    let running: Bool
    let changed: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Link analog inputs as a stereo pair", isOn: $state.stereoLinked)
                    .onChange(of: state.stereoLinked) { _, linked in
                        if linked { state.input1.pan = 0.5 }
                    }
                HStack(alignment: .top, spacing: 18) {
                    channel(state.stereoLinked ? "Inputs 1–2" : "Input 1", value: $state.input1)
                    if !state.stereoLinked { channel("Input 2", value: $state.input2) }
                    channel("Playback return", value: $state.playback)
                }
                Divider()
                HStack {
                    Text("Master").font(.headline)
                    Slider(value: $state.masterLevel, in: -64...12, step: 1)
                    Text("\(Int(state.masterLevel)) dB").monospacedDigit().frame(width: 60)
                    Toggle("Mute", isOn: $state.masterMuted).toggleStyle(.button)
                }
            }.padding(8).disabled(running)
                .onChange(of: state) { _, _ in if !running { changed() } }
        }
    }

    private func channel(_ title: String, value: Binding<MixerCoefficients.Channel>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text("\(Int(value.wrappedValue.level)) dB").monospacedDigit()
            Slider(value: value.level, in: -64...12, step: 1)
            HStack {
                Text("L")
                Slider(value: value.pan, in: 0...1)
                Text("R")
            }
            HStack {
                Toggle("Mute", isOn: value.muted)
                Toggle("Solo", isOn: value.solo)
            }.toggleStyle(.button)
            Toggle("Solo safe", isOn: value.soloSafe).font(.caption)
        }.frame(maxWidth: .infinity)
    }
}
