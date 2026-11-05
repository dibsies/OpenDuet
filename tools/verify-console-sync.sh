#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/mock.swift" <<'SWIFT'
import Foundation
@MainActor final class CoreAudioVolumeBackend: SystemVolumeBackend {
    static var latest: CoreAudioVolumeBackend?
    var onChange: (@MainActor @Sendable () -> Void)?
    var onDefaultOutputChange: (@MainActor @Sendable () -> Void)?
    var selected: UInt32?
    var value = SystemVolumeState(level: -3, muted: false)
    init() { Self.latest = self }
    func defaultOutput() -> UInt32? { selected }
    func track(_ device: UInt32?) -> Bool { true }
    func read(_ device: UInt32) -> SystemVolumeState? { selected == device ? value : nil }
    func scalar(_ device: UInt32) -> Double? { pow(Double(value.level + 64) / 64, 2) }
    func write(_ state: SystemVolumeState, to device: UInt32) -> Bool {
        guard selected == device else { return false }; value = state; return true
    }
    func emit(_ value: SystemVolumeState) { self.value = value; onChange?() }
}
struct USBHelperResult: Sendable { let exitCode: Int32; let output: String }
enum USBHelper {
    static func run(_ args: [String]) async -> USBHelperResult { await USBSession.shared.run(args) }
}
actor USBSession {
    static let shared = USBSession()
    enum Event: Sendable { case connected, meters([Double]), hardware(DeviceEvents), diagnostic(String), disconnected(Int32) }
    var continuation: AsyncStream<Event>.Continuation?
    var writes: [[String]] = []
    var modes = [2, 3]
    var delayStartup = false
    func delayNextStartup() { delayStartup = true }
    func start() throws -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.continuation = continuation; continuation.yield(.connected); return stream
    }
    func stop() { continuation?.yield(.disconnected(0)); continuation?.finish() }
    func run(_ args: [String]) async -> USBHelperResult {
        if args == ["--input-modes"] { return .init(exitCode: 0, output: "INPUT_MODES \(modes[0]) \(modes[1])") }
        writes.append(args)
        if args.first == "--experimental-mode", let channel = Int(args[1]), let mode = Int(args[2]) { modes[channel - 1] = mode }
        if args.first == "--experimental-startup-muted", delayStartup {
            delayStartup = false
            try? await Task.sleep(for: .milliseconds(250))
        }
        return .init(exitCode: 0, output: "accepted")
    }
    func emitMeters(_ values: [Double]) { continuation?.yield(.meters(values)) }
    func emit(_ bytes: [UInt8]) { continuation?.yield(.hardware(DeviceEvents(bytes: bytes)!)) }
    func recorded() -> [[String]] { writes }
    func clear() { writes = [] }
}
enum NativeAudioDevice {
    struct Snapshot { var id: UInt32 = 1; var sampleRate: Double = 44100; var supportedRates = [44100.0] }
    static func snapshot() throws -> Snapshot { Snapshot() }
    @MainActor static var failRate = false
    @MainActor static func setSampleRate(_ rate: Double) async throws -> Snapshot {
        if failRate { throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Rate fixture failure"]) }
        return Snapshot()
    }
}
@MainActor final class NativeAudioMonitor {
    static var sleep: (@Sendable () -> Void)?
    static var wake: (@Sendable () -> Void)?
    init(onChange: @escaping @Sendable () -> Void, onSleep: @escaping @Sendable () -> Void, onWake: @escaping @Sendable () -> Void) {
        Self.sleep = onSleep; Self.wake = onWake
    }
    func trackRate(_ id: UInt32?) {}
}
SWIFT
cat > "$scratch/harness.swift" <<'SWIFT'
import Foundation
import Combine
@main struct Test {
    @MainActor static func main() async throws {
        // Isolate startup from profiles saved by earlier harness runs.
        UserDefaults.standard.setVolatileDomain(["OpenDuet.keyboardVolume": true, "OpenDuet.profile.v1": Data(), "OpenDuet.autoConnect": false, "OpenDuet.liveScreen": false], forName: UserDefaults.argumentDomain)
        let model = ConsoleModel(safetyEnabled: false)
        model.connectUSB()
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.usbConnected && !model.running)
        NativeAudioDevice.failRate = true; model.selectedRate = 96000
        model.applyRate()
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.audio?.sampleRate == 44100 && model.selectedRate == 44100 && model.status == "Rate fixture failure")
        NativeAudioDevice.failRate = false
        model.inputs[0].micGain = 24; model.inputs[1].instrumentGain = 12
        model.enableHardwareControls(true)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.hardwareEnabled && !model.running)
        let setup = await USBSession.shared.recorded()
        precondition(setup.contains(["--experimental-mic-gain", "1", "24", "--apply"]))
        precondition(setup.contains(["--experimental-instrument-gain", "2", "12", "--apply"]))
        precondition(!setup.contains { $0.first == "--experimental-phantom" })
        model.main.dimmed = true; model.headphones.dimmed = true
        model.setPhantom(true, input: 0)
        try await Task.sleep(for: .milliseconds(100))
        let phantomWrites = await USBSession.shared.recorded()
        precondition(phantomWrites.last == ["--experimental-phantom", "1", "1", "--apply"])
        model.initializeMuted()
        try await Task.sleep(for: .milliseconds(100))
        precondition(!model.main.dimmed && !model.headphones.dimmed && model.hardwareEnabled)
        let initialized = Array((await USBSession.shared.recorded()).dropFirst(phantomWrites.count))
        precondition(initialized.first?.first == "--experimental-startup-muted")
        precondition(initialized.contains(["--experimental-mic-gain", "1", "24", "--apply"]))
        precondition(initialized.contains(["--experimental-instrument-gain", "2", "12", "--apply"]))
        precondition(!initialized.contains { $0.first == "--experimental-phantom" || $0.first == "--experimental-mode" })
        precondition(model.displayEnabled) // Muted startup must leave the boot logo without another opt-in.
        model.setDisplayEnabled(false) // Isolate output-write assertions from display traffic.
        await USBSession.shared.emitMeters((-20 ..< -10).map(Double.init))
        try await Task.sleep(for: .milliseconds(70))
        precondition(model.outputMeters(headphone: false) == [-.infinity, -.infinity])
        precondition(model.outputMeters(headphone: true) == [-.infinity, -.infinity])
        model.main.level = -20; model.main.muted = false
        model.setOutputLevel(model.main.level, headphone: false)
        model.setOutputMute(model.main.muted, headphone: false)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.outputMeters(headphone: false) == [-40, -39])
        await USBSession.shared.clear()
        model.setLiveOutputRoute(.playback34, headphone: true)
        model.setLiveOutputRoute(.mixer, headphone: false)
        try await Task.sleep(for: .milliseconds(100))
        let liveRoutes = await USBSession.shared.recorded()
        precondition(liveRoutes == [["--experimental-routing", "outputs", "18", "--apply"]])
        precondition(model.main.route == .mixer && model.headphones.route == .playback34)
        model.setLiveOutputRoute(.playback12, headphone: true)
        model.setLiveOutputRoute(.playback12, headphone: false)
        try await Task.sleep(for: .milliseconds(100))
        await USBSession.shared.clear()
        for level in 0...12 { model.mixer.masterLevel = Double(level); model.enqueueLiveMixer() }
        try await Task.sleep(for: .milliseconds(100))
        let liveMix = await USBSession.shared.recorded()
        precondition(liveMix.count == 2 && liveMix[0].first == "--experimental-mixer-source" && liveMix[1].first == "--experimental-mixer")
        precondition(liveMix[1][1].count == 16 && liveMix[1][2].count == 16)
        model.mixer.masterLevel = 0; model.enqueueLiveMixer()
        try await Task.sleep(for: .milliseconds(100))
        await USBSession.shared.clear()
        let systemVolume = CoreAudioVolumeBackend.latest!
        systemVolume.selected = 1; systemVolume.onChange?()
        model.refreshAudio()
        precondition(systemVolume.value == .init(level: -20, muted: false))
        systemVolume.emit(.init(level: -24, muted: false))
        try await Task.sleep(for: .milliseconds(120))
        precondition(model.main.level == -22 && !model.main.muted && model.headphones.level == -64 && model.headphones.muted)
        let keyboardWrites = await USBSession.shared.recorded()
        precondition(!keyboardWrites.isEmpty && keyboardWrites.allSatisfy { $0[1] == "main" })
        await USBSession.shared.clear()
        systemVolume.selected = 2; systemVolume.onChange?()
        systemVolume.emit(.init(level: 0, muted: false))
        try await Task.sleep(for: .milliseconds(100))
        let otherDeviceWrites = await USBSession.shared.recorded()
        precondition(otherDeviceWrites.isEmpty && model.main.level == -22)
        model.keyboardVolumeEnabled = false
        systemVolume.selected = 1; systemVolume.onChange?()
        systemVolume.emit(.init(level: 0, muted: false))
        try await Task.sleep(for: .milliseconds(100))
        let disabledWrites = await USBSession.shared.recorded()
        precondition(disabledWrites.isEmpty && model.main.level == -22)
        systemVolume.selected = nil
        model.setOutputLevel(-20, headphone: false)
        try await Task.sleep(for: .milliseconds(100))
        model.setOutputDim(true, headphone: false)
        try await Task.sleep(for: .milliseconds(900))
        precondition(model.outputMeters(headphone: false) == [-55, -54])
        model.setOutputDim(false, headphone: false)
        model.setOutputMute(true, headphone: false)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.outputMeters(headphone: false) == [-.infinity, -.infinity])
        await USBSession.shared.clear()
        let status = model.status
        // Fast UI changes coalesce into the final complete output state.
        for value in -64 ... -10 { model.setOutputLevel(Double(value), headphone: false); precondition(!model.running) }
        try await Task.sleep(for: .milliseconds(150))
        let writes = await USBSession.shared.recorded()
        precondition(writes.count == 2 && writes.last == ["--experimental-attenuation", "main", "10", "--apply"])
        precondition(model.status == status && !model.running)
        // Input selection is initialized, and encoder events never enter global busy state.
        var press = [UInt8](repeating: 0, count: 29); press[0] = 1; press[3] = 1
        await USBSession.shared.emit(press); await USBSession.shared.emit(press)
        try await Task.sleep(for: .milliseconds(50))
        precondition(model.selectedControl == .input1)
        var turn = [UInt8](repeating: 0, count: 29); turn[0] = 1; turn[5] = 3
        await USBSession.shared.emit(turn)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.inputs[0].micGain == 27 && !model.running)
        precondition(model.inputMeter(0) == -16) // ADC level must not have preamp gain added twice.
        model.inputs[1].mode = .mic; model.inputs[1].micGain = 33
        model.applyInput(1)
        try await Task.sleep(for: .milliseconds(100))
        model.linkInputs = true; model.inputs[0].micGain = 30
        model.applyInput(0)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.inputs[0].micGain == 30 && model.inputs[1].micGain == 36)
        model.inputs[0].micGain = 75; model.applyInput(0)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.inputs[0].micGain == 69 && model.inputs[1].micGain == 75)
        await USBSession.shared.clear()
        model.setQuickInputGain(60, input: 0)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.inputs[0].micGain == 60 && model.inputs[1].micGain == 66)
        let quickGain = await USBSession.shared.recorded()
        precondition(quickGain.count == 2 && quickGain.allSatisfy { $0.first == "--experimental-mic-gain" })
        await USBSession.shared.clear()
        model.setQuickInputSwitch(true, input: 0, phase: true)
        try await Task.sleep(for: .milliseconds(100))
        let quickPhase = await USBSession.shared.recorded()
        precondition(quickPhase == [["--experimental-phase", "1", "1", "--apply"]])
        model.linkInputs = false
        await USBSession.shared.clear()
        model.setInputMode(.instrument, input: 1)
        try await Task.sleep(for: .milliseconds(120))
        precondition(model.observedModes?.modes[1] == .instrument && model.selectedControl == .input2)
        let source = await USBSession.shared.recorded()
        precondition(source.contains(["--experimental-mode", "2", "3", "--apply"]))
        precondition(source.contains { $0.first == "--experimental-instrument-gain" })
        precondition(!source.contains { ["--experimental-phantom", "--experimental-phase", "--experimental-soft-limit"].contains($0.first ?? "") })
        await USBSession.shared.clear()
        model.setInputMode(.instrument, input: 0)
        try await Task.sleep(for: .milliseconds(120))
        let leavingMic = await USBSession.shared.recorded()
        precondition(leavingMic.first == ["--experimental-phantom", "1", "0", "--apply"])
        precondition(model.inputs[0].phantom == false)
        await USBSession.shared.clear()
        model.setInputMode(.mic, input: 0)
        try await Task.sleep(for: .milliseconds(120))
        let returningMic = await USBSession.shared.recorded()
        precondition(!returningMic.contains { $0.first == "--experimental-phantom" })
        // Steady meter samples must invalidate only the small live-readout views.
        var consoleChanges = 0, meterChanges = 0
        let consoleObserver = model.objectWillChange.sink { consoleChanges += 1 }
        let meterObserver = model.meterPresentation.objectWillChange.sink { meterChanges += 1 }
        await USBSession.shared.emitMeters((-30 ..< -20).map(Double.init))
        try await Task.sleep(for: .milliseconds(100))
        precondition(consoleChanges == 0 && meterChanges > 0)
        consoleObserver.cancel(); meterObserver.cancel()
        await USBSession.shared.emitMeters((-20 ..< -10).map(Double.init))
        try await Task.sleep(for: .milliseconds(70))
        // Sleep closes the transport, but must preserve the user's screen intent.
        model.setDisplayEnabled(true)
        try await Task.sleep(for: .milliseconds(120))
        await USBSession.shared.clear()
        await USBSession.shared.delayNextStartup()
        model.initializeMuted()
        try await Task.sleep(for: .milliseconds(20))
        NativeAudioMonitor.sleep?()
        try await Task.sleep(for: .milliseconds(300))
        precondition(!model.usbConnected && !model.displayEnabled && !model.hardwareEnabled)
        precondition(model.outputsNeedSetup) // Late startup ACK must not revive old state.
        let interrupted = await USBSession.shared.recorded()
        precondition(!interrupted.contains { $0.first == "--experimental-routing" || $0.first == "--experimental-mono" })
        await USBSession.shared.clear()
        NativeAudioMonitor.wake?(); NativeAudioMonitor.wake?()
        try await Task.sleep(for: .milliseconds(2300))
        precondition(model.usbConnected && model.displayEnabled && !model.hardwareEnabled)
        let beforeSelection = model.selectedControl
        await USBSession.shared.emit(press)
        await USBSession.shared.emit(turn)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.selectedControl != beforeSelection && !model.hardwareEnabled)
        let recovery = await USBSession.shared.recorded()
        precondition(!recovery.isEmpty)
        precondition(recovery.allSatisfy { $0.first == "--experimental-display" }) // No audio setting replay.
        // An intentional release stops retries but a later connect resumes the screen.
        model.disconnectUSB()
        try await Task.sleep(for: .milliseconds(120))
        precondition(!model.usbConnected && !model.connectionRequested && !model.displayEnabled)
        model.connectUSB()
        try await Task.sleep(for: .milliseconds(120))
        precondition(model.usbConnected && model.displayEnabled)
        // Explicitly turning the screen off must also survive reconnect.
        model.setDisplayEnabled(false)
        model.disconnectUSB()
        try await Task.sleep(for: .milliseconds(120))
        model.connectUSB()
        try await Task.sleep(for: .milliseconds(120))
        precondition(model.usbConnected && !model.displayEnabled)
        model.disconnectUSB()
        try await Task.sleep(for: .milliseconds(120))
        // Reopening the application restores only connection/screen intent.
        UserDefaults.standard.setVolatileDomain(["OpenDuet.keyboardVolume": true, "OpenDuet.profile.v1": Data(), "OpenDuet.autoConnect": true, "OpenDuet.liveScreen": true], forName: UserDefaults.argumentDomain)
        await USBSession.shared.clear()
        let reopened = ConsoleModel(safetyEnabled: false)
        try await Task.sleep(for: .milliseconds(150))
        precondition(reopened.usbConnected && reopened.displayEnabled && !reopened.hardwareEnabled)
        let launch = await USBSession.shared.recorded()
        precondition(!launch.isEmpty && launch.allSatisfy { $0.first == "--experimental-display" })
        reopened.disconnectUSB()
        try await Task.sleep(for: .milliseconds(100))
        // Exercise the production guard through the model, with USB fully mocked.
        UserDefaults.standard.setVolatileDomain(["OpenDuet.keyboardVolume": true, "OpenDuet.profile.v1": Data(), "OpenDuet.autoConnect": false, "OpenDuet.liveScreen": false, "OpenDuet.mainOutputCeiling": -12, "OpenDuet.headphoneOutputCeiling": -12], forName: UserDefaults.argumentDomain)
        let guarded = ConsoleModel()
        guarded.connectUSB()
        try await Task.sleep(for: .milliseconds(100))
        guarded.initializeMuted()
        try await Task.sleep(for: .milliseconds(150))
        guarded.setDisplayEnabled(false)
        try await Task.sleep(for: .milliseconds(100))
        await USBSession.shared.clear()
        func check(_ success: Bool, _ message: String) {
            if !success { print("Guard regression: \(message)"); exit(1) }
        }
        check(!guarded.setOutputLevel(0, headphone: false), "large jump must be held")
        check(guarded.main.level == -64 && guarded.pendingOutputIncrease?.target == 0, "full range and no optimistic jump")
        try await Task.sleep(for: .milliseconds(100))
        let heldWrites = await USBSession.shared.recorded()
        check(heldWrites.isEmpty, "held jump must not reach USB")
        guarded.resolveOutputIncrease(false)
        check(guarded.main.level == -64 && guarded.pendingOutputIncrease == nil, "cancel retains current level")
        check(guarded.setOutputLevel(-62, headphone: false), "normal keyboard-sized step")
        _ = guarded.setOutputLevel(-12, headphone: false)
        guarded.resolveOutputIncrease(true)
        check(guarded.main.level == -12 && guarded.main.muted, "explicit confirmation preserves mute")
        check(guarded.setOutputLevel(-10, headphone: false), "ordinary increase above -12 must be allowed")
        check(guarded.main.level == -10, "no unintended output ceiling")
        _ = guarded.setOutputLevel(-30, headphone: false)
        // A burst from the physical knob uses the same guard and cache rollback.
        var largeTurn = [UInt8](repeating: 0, count: 29); largeTurn[0] = 1; largeTurn[5] = 40
        await USBSession.shared.emit(largeTurn)
        try await Task.sleep(for: .milliseconds(100))
        check(guarded.pendingOutputIncrease != nil && guarded.main.level == -30, "hardware burst held")
        guarded.resolveOutputIncrease(false)
        check(guarded.setOutputLevel(-32, headphone: false), "attenuation remains available")
        // Changing current state invalidates a previously proposed increase.
        _ = guarded.setOutputLevel(0, headphone: false)
        _ = guarded.setOutputLevel(-34, headphone: false)
        guarded.resolveOutputIncrease(true)
        check(guarded.main.level == -34, "stale confirmation after attenuation rejected")
        _ = guarded.setOutputLevel(-12, headphone: true)
        guarded.disconnectUSB()
        guarded.resolveOutputIncrease(true)
        check(guarded.headphones.level == -64, "disconnect invalidates pending increase")
        try await Task.sleep(for: .milliseconds(100))
        print("Console controls, lifecycle recovery and guarded output integration checks passed")
    }
}
SWIFT
swiftc -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{ConsoleModel,OutputSafety,SystemVolumeBridge,ControlUpdateQueue,ControlPacket,InputControlPacket,OutputControlPacket,InputModeSnapshot,MixerCoefficients,GainLink,PhysicalController,DeviceEvents,DeviceDisplayRenderer,DuetbarMeterScale,MeterPacket,MeterRouting,MeterBallistics}.swift "$scratch/mock.swift" "$scratch/harness.swift" -o "$scratch/check"
"$scratch/check"
