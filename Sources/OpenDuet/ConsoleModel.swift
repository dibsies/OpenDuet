import Foundation
import Combine

/// A dedicated invalidation channel for live meters; static controls do not observe it.
@MainActor
final class MeterPresentation: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    func refresh() { revision &+= 1 }
}

@MainActor
final class ConsoleModel: ObservableObject {
    struct InputDraft: Codable {
        var mode = InputControlPacket.Mode.mic
        var micGain: Double = 0
        var instrumentGain: Double = 0
        var phantom: Bool?
        var softLimit: Bool?
        var phase: Bool?
    }
    struct OutputDraft: Codable {
        var level: Double = -64
        var muted = true
        var dimmed = false
        var mono = false
        var route = OutputControlPacket.RouteSelector.playback12
    }

    @Published var inputs = [InputDraft(), InputDraft(mode: .instrument)]
    @Published var main = OutputDraft()
    @Published var headphones = OutputDraft()
    @Published private(set) var pendingOutputIncrease: OutputIncreaseRequest?
    private let safetyEnabled: Bool
    private let safetyPrompt: (@MainActor (OutputIncreaseRequest, @escaping (Bool) -> Void) -> Void)?
    @Published var mainPlus4 = true
    @Published var mixer = MixerCoefficients.State()
    @Published var mixerSource = MixerCoefficients.PlaybackSource.playback12
    @Published var linkInputs = false
    @Published var audio: NativeAudioDevice.Snapshot?
    @Published var selectedRate: Double = 44100
    @Published var observedModes: InputModeSnapshot?
    @Published var running = false { didSet { synchronizeSystemVolume() } }
    @Published var status = "Controls are pending until applied. Read device state before testing."
    @Published var details = ""
    private(set) var meters: [Double] = []
    let meterPresentation = MeterPresentation()
    @Published private(set) var metersAvailable = false
    @Published var showRawMeters = false
    private(set) var meterLevels: [Double] = []
    private(set) var meterPeaks: [Double] = []
    private(set) var meterOvers: [Bool] = []
    private var presentedRawMeters: [Double] = []
    @Published var peakHold = MeterHold.twoSeconds {
        didSet { meterBank.peakHold = peakHold.seconds; UserDefaults.standard.set(peakHold.rawValue, forKey: "meterPeakHold") }
    }
    @Published var overHold = MeterHold.twoSeconds {
        didSet { meterBank.overHold = overHold.seconds; UserDefaults.standard.set(overHold.rawValue, forKey: "meterOverHold") }
    }
    private var meterBank = MeterBallistics(count: 14)
    private var meterTask: Task<Void, Never>?
    @Published var keyboardVolumeEnabled = true {
        didSet {
            UserDefaults.standard.set(keyboardVolumeEnabled, forKey: "OpenDuet.keyboardVolume")
            synchronizeSystemVolume()
        }
    }
    @Published private(set) var keyboardVolumeStatus = "Keyboard volume waits for an initialized Main Out."
    private var volumeBridge: SystemVolumeBridge?
    @Published var usbConnected = false { didSet { synchronizeSystemVolume() } }
    @Published private(set) var connectionRequested = false
    @Published var lastHardwareEvent = "No hardware events received."
    @Published var hardwareEnabled = false
    @Published var selectedControl = PhysicalController.Target.main
    @Published var touchpadA = PhysicalController.TouchpadAction.none {
        didSet { UserDefaults.standard.set(touchpadA.rawValue, forKey: "touchpadA") }
    }
    @Published var touchpadB = PhysicalController.TouchpadAction.none {
        didSet { UserDefaults.standard.set(touchpadB.rawValue, forKey: "touchpadB") }
    }
    private var physical = PhysicalController()
    private var controlGeneration: UInt64 = 0
    private var controlUpdates = ControlUpdateQueue()
    private var controlWriteTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var audioMonitor: NativeAudioMonitor?
    private var sleeping = false
    // User intent survives transport loss; displayEnabled describes the active stream.
    private var displayRequested = UserDefaults.standard.object(forKey: "OpenDuet.liveScreen") as? Bool ?? true
    @Published private(set) var displayEnabled = false
    private var displayTask: Task<Void, Never>?
    private var displayGeneration: UInt64 = 0
    private var lastDisplayPixels: [UInt8]?
    private var focusDeadline = ContinuousClock.now

    init(safetyEnabled: Bool = true, safetyPrompt: (@MainActor (OutputIncreaseRequest, @escaping (Bool) -> Void) -> Void)? = nil) {
        self.safetyEnabled = safetyEnabled; self.safetyPrompt = safetyPrompt
        keyboardVolumeEnabled = UserDefaults.standard.object(forKey: "OpenDuet.keyboardVolume") as? Bool ?? true
        volumeBridge = SystemVolumeBridge(backend: CoreAudioVolumeBackend(), changed: { [weak self] value in
            guard let self, self.keyboardVolumeEnabled, self.connectionRequested, self.usbConnected, !self.running,
                  !self.sleeping, self.physical.outputs[0].known else { return }
            if self.setOutputLevel(Double(value.level), headphone: false) {
                self.setOutputMute(value.muted, headphone: false)
            } else { self.synchronizeSystemVolume() }
        }, status: { [weak self] message in
            if self?.keyboardVolumeStatus != message { self?.keyboardVolumeStatus = message }
        })
        touchpadA = UserDefaults.standard.string(forKey: "touchpadA").flatMap(PhysicalController.TouchpadAction.init(rawValue:)) ?? .none
        touchpadB = UserDefaults.standard.string(forKey: "touchpadB").flatMap(PhysicalController.TouchpadAction.init(rawValue:)) ?? .none
        restoreProfile()
        peakHold = UserDefaults.standard.string(forKey: "meterPeakHold").flatMap(MeterHold.init(rawValue:)) ?? .twoSeconds
        overHold = UserDefaults.standard.string(forKey: "meterOverHold").flatMap(MeterHold.init(rawValue:)) ?? .twoSeconds
        meterBank.peakHold = peakHold.seconds; meterBank.overHold = overHold.seconds
        audioMonitor = NativeAudioMonitor(onChange: { [weak self] in
            Task { @MainActor in self?.refreshAudio() }
        }, onSleep: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = true
                self.synchronizeSystemVolume()
                self.reconnectTask?.cancel(); self.reconnectTask = nil
                self.hardwareEnabled = false
                self.controlGeneration &+= 1
                self.controlWriteTask?.cancel(); self.controlWriteTask = nil; self.controlUpdates.clear()
                self.suspendDisplay()
                await USBSession.shared.stop()
            }
        }, onWake: { [weak self] in
            Task { @MainActor in
                self?.sleeping = false
                self?.refreshAudio()
                self?.scheduleReconnect()
            }
        })
        // Opening the control lease and drawing the screen never replays audio settings.
        if UserDefaults.standard.object(forKey: "OpenDuet.autoConnect") as? Bool ?? true {
            Task { [weak self] in self?.connectUSB() }
        }
    }

    var outputsNeedSetup: Bool { physical.outputs.contains { !$0.known } }

    func connectUSB() {
        connectionRequested = true
        UserDefaults.standard.set(true, forKey: "OpenDuet.autoConnect")
        guard !sleeping, sessionTask == nil else { return }
        status = "Opening the Duet control connection…"
        sessionTask = Task { [weak self] in
            var ownershipBusy = false
            do {
                let stream = try await USBSession.shared.start()
                for await event in stream {
                    guard let self else { await USBSession.shared.stop(); return }
                    switch event {
                    case .connected:
                        usbConnected = true
                        startMeterAnimation()
                        status = "USB control connected. Startup and settings are applied only when requested."
                        readModes()
                        resumeDisplay()
                    case .meters(let values):
                        if meters != values { meters = values }
                        advanceMeters(publish: false)
                    case .hardware(let report):
                        if report.encoderPressed || report.touchpadA || report.touchpadB || report.clockwiseSteps != 0 || report.counterclockwiseSteps != 0 {
                            lastHardwareEvent = "A: \(report.touchpadA) · B: \(report.touchpadB) · Press: \(report.encoderPressed) · Turn: +\(report.clockwiseSteps)/−\(report.counterclockwiseSteps)"
                        }
                        handleHardware(report)
                    case .diagnostic(let line):
                        details = String((details + "\n" + line).suffix(8192))
                        if line.contains("0xe00002c5") {
                            ownershipBusy = true
                            status = "The Duet is in use by another application or service."
                        }
                    case .disconnected(let code):
                        usbConnected = false; meters = []; observedModes = nil
                        meterTask?.cancel(); meterTask = nil
                        meterBank = MeterBallistics(count: 14)
                        meterBank.peakHold = peakHold.seconds; meterBank.overHold = overHold.seconds
                        meterLevels = []; meterPeaks = []; meterOvers = []
                        metersAvailable = false; presentedRawMeters = []
                        meterPresentation.refresh()
                        hardwareEnabled = false; physical.invalidate()
                        controlGeneration &+= 1
                        controlWriteTask?.cancel(); controlWriteTask = nil; controlUpdates.clear()
                        suspendDisplay()
                        refreshAudio()
                        if ownershipBusy { status = "The Duet is in use by another application or service. Release Glue before connecting; Cancel connection stops retries." }
                        else if code != 0 { status = "USB control disconnected. See device details." }
                        else { status = "USB control released." }
                    }
                }
            } catch { self?.status = error.localizedDescription }
            self?.usbConnected = false
            self?.sessionTask = nil
            self?.scheduleReconnect()
        }
    }

    func disconnectUSB() {
        connectionRequested = false
        synchronizeSystemVolume()
        UserDefaults.standard.set(false, forKey: "OpenDuet.autoConnect")
        controlGeneration &+= 1
        controlWriteTask?.cancel(); controlWriteTask = nil; controlUpdates.clear()
        hardwareEnabled = false
        suspendDisplay()
        reconnectTask?.cancel(); reconnectTask = nil
        Task { await USBSession.shared.stop() }
    }

    private func scheduleReconnect() {
        guard connectionRequested, !sleeping, reconnectTask == nil, sessionTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            reconnectTask = nil
            if connectionRequested && !sleeping && sessionTask == nil { connectUSB() }
        }
    }

    func initializeMuted() {
        guard let modes = observedModes, modes.modes == inputs.map(\.mode) else {
            status = "Wait for input sources to be read before initializing."
            return
        }
        let inputDrafts = inputs
        let mainRoute = main.route, headphoneRoute = headphones.route
        let mainMono = main.mono, headphoneMono = headphones.mono
        let route = OutputControlPacket.routing(main: mainRoute, headphones: headphoneRoute)
        let mono = OutputControlPacket.sumToMono(main: mainMono, headphones: headphoneMono)
        guard let banks = MixerCoefficients.encode(mixer) else { status = "Mixer values are out of range."; return }
        var commands = [["--experimental-startup-muted", "device", "1", "--apply"],
                        ["--experimental-routing", "outputs", String(route.payload), "--apply"],
                        ["--experimental-mono", "outputs", String(mono.payload), "--apply"],
                        ["--experimental-reference", "main", mainPlus4 ? "1" : "0", "--apply"],
                        ["--experimental-mixer-source", "mixer", String(mixerSource.rawValue), "--apply"],
                        ["--experimental-mixer", banks[0].payload.map { String(format: "%02x", $0) }.joined(), banks[1].payload.map { String(format: "%02x", $0) }.joined(), "--apply"]]
        for index in 0..<2 {
            let draft = inputDrafts[index]
            if draft.mode == .mic || draft.mode == .instrument {
                commands.append([draft.mode == .mic ? "--experimental-mic-gain" : "--experimental-instrument-gain", String(index + 1),
                                 String(Int(draft.mode == .mic ? draft.micGain : draft.instrumentGain)), "--apply"])
            }
        }
        run(commands, label: "Device setup") { [weak self] in
            guard let self else { return }
            main.level = -64; main.muted = true; main.dimmed = false
            headphones.level = -64; headphones.muted = true; headphones.dimmed = false
            lastDisplayPixels = nil
            physical.outputs = [
                .init(known: true, level: -64, muted: true, dimmed: false, mono: mainMono, route: mainRoute),
                .init(known: true, level: -64, muted: true, dimmed: false, mono: headphoneMono, route: headphoneRoute)
            ]
            for index in 0..<2 {
                let draft = inputDrafts[index]
                physical.inputs[index].mode = draft.mode
                physical.inputs[index].gain = draft.mode == .mic ? Int(draft.micGain) : draft.mode == .instrument ? Int(draft.instrumentGain) : nil
            }
            hardwareEnabled = true
            setDisplayEnabled(true)
            status = "Ready"
        }
    }

    func setDisplayEnabled(_ enabled: Bool) {
        displayRequested = enabled
        UserDefaults.standard.set(enabled, forKey: "OpenDuet.liveScreen")
        if enabled { resumeDisplay() } else { suspendDisplay() }
    }

    private func suspendDisplay() {
        displayGeneration &+= 1
        displayTask?.cancel(); displayTask = nil
        displayEnabled = false
        lastDisplayPixels = nil
    }

    private func resumeDisplay() {
        displayGeneration &+= 1
        let generation = displayGeneration
        displayTask?.cancel(); displayTask = nil
        displayEnabled = displayRequested && usbConnected && !sleeping
        lastDisplayPixels = nil
        guard displayEnabled else { return }
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, usbConnected, generation == displayGeneration else { break }
                if !running {
                    let result = await sendDisplayFrame(force: false)
                    guard generation == displayGeneration else { break }
                    if result.exitCode != 0 {
                        details = result.output
                        status = "Device screen update failed; display streaming stopped."
                        break
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let self, generation == displayGeneration {
                displayEnabled = false; displayTask = nil
            }
        }
    }

    func updateDeviceDisplay() {
        guard usbConnected, !running else { return }
        running = true
        Task {
            defer { running = false }
            let result = await sendDisplayFrame(force: true)
            details = result.output
            status = result.exitCode == 0 ? "Device screen data sent. Verify the physical display during testing." : "Device screen update did not complete."
        }
    }

    var playbackMeters: [Double]? {
        MeterRouting.source(mixerSource == .playback12 ? .playback12 : .playback34, lanes: Array(meterLevels.prefix(10)))
    }

    var playbackPeaks: [Double]? {
        MeterRouting.source(mixerSource == .playback12 ? .playback12 : .playback34, lanes: Array(meterPeaks.prefix(10)))
    }

    var playbackOvers: [Bool]? {
        guard meterOvers.count == 14 else { return nil }
        let start = mixerSource == .playback12 ? 0 : 2
        return Array(meterOvers[start..<start + 2])
    }

    func inputMeter(_ index: Int) -> Double? { meterLevels.count == 14 ? meterLevels[index + 4] : nil }
    func inputPeak(_ index: Int) -> Double? { meterPeaks.count == 14 ? meterPeaks[index + 4] : nil }
    func inputOver(_ index: Int) -> Bool { meterOvers.count == 14 && meterOvers[index + 4] }

    func outputMeters(headphone: Bool) -> [Double]? {
        let output = physical.outputs[headphone ? 1 : 0]
        guard output.known, output.route != nil, meterLevels.count == 14 else { return nil }
        let start = headphone ? 12 : 10
        return Array(meterLevels[start..<start + 2])
    }

    func outputMeterCaption(headphone: Bool) -> String {
        physical.outputs[headphone ? 1 : 0].mono == true ? "After controls · mono peak bound" : "After level/mute · calculated"
    }

    func outputPeaks(headphone: Bool) -> [Double]? {
        guard outputMeters(headphone: headphone) != nil, meterPeaks.count == 14 else { return nil }
        let start = headphone ? 12 : 10
        return Array(meterPeaks[start..<start + 2])
    }

    func outputOvers(headphone: Bool) -> [Bool]? {
        guard outputMeters(headphone: headphone) != nil, meterOvers.count == 14 else { return nil }
        let start = headphone ? 12 : 10
        return Array(meterOvers[start..<start + 2])
    }

    private func startMeterAnimation() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, usbConnected else { return }
                advanceMeters()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func advanceMeters(publish: Bool = true) {
        guard meters.count == 10 else { return }
        var targets = meters
        var silent: Set<Int> = []
        for index in 0..<2 {
            let output = physical.outputs[index]
            let source = MeterRouting.source(output.route, lanes: meters)
            let values = output.known ? MeterRouting.output(source, level: output.level,
                dimmed: output.dimmed, muted: output.muted, mono: output.mono ?? false) : nil
            targets += values ?? [-.infinity, -.infinity]
            if output.muted || values == nil { silent.formUnion([10 + index * 2, 11 + index * 2]) }
        }
        meterBank.update(targets, at: ProcessInfo.processInfo.systemUptime, silent: silent)
        guard publish else { return }
        let changed = meterLevels != meterBank.levels || meterPeaks != meterBank.peaks
            || meterOvers != meterBank.overs || presentedRawMeters != meters
        meterLevels = meterBank.levels; meterPeaks = meterBank.peaks; meterOvers = meterBank.overs
        presentedRawMeters = meters
        if !metersAvailable { metersAvailable = true }
        if changed { meterPresentation.refresh() }
    }

    func clearMeterHolds() {
        meterBank.clearHolds()
        meterPeaks = meterBank.peaks; meterOvers = meterBank.overs
        meterPresentation.refresh()
    }

    private func sendDisplayFrame(force: Bool) async -> USBHelperResult {
        let generation = displayGeneration
        var snapshot = DeviceDisplayRenderer.Snapshot()
        snapshot.selected = selectedControl.rawValue
        snapshot.focused = ContinuousClock.now < focusDeadline
        snapshot.grouped = linkInputs && physical.inputs[0].mode == physical.inputs[1].mode && physical.inputs.allSatisfy { $0.gain != nil }
        for index in 0..<2 {
            let input = physical.inputs[index]
            let mode: String
            switch input.mode {
            case .mic: mode = "MIC"
            case .instrument: mode = "INST"
            case .plus4: mode = "+4"
            case .minus10: mode = "-10"
            case nil: mode = "?"
            }
            snapshot.inputs[index] = .init(mode: mode, gain: input.gain, phantom: input.phantom, softLimit: input.softLimit, phase: input.phase,
                meter: inputMeter(index) ?? -.infinity,
                peak: inputPeak(index) ?? -.infinity, over: inputOver(index))
            let output = physical.outputs[index]
            snapshot.outputs[index] = .init(level: output.known ? output.level : nil,
                                            muted: output.known ? output.muted : nil,
                                            meters: outputMeters(headphone: index == 1),
                                            peaks: meterPeaks.count == 14 ? Array(meterPeaks[(10 + index * 2)..<(12 + index * 2)]) : nil,
                                            overs: meterOvers.count == 14 ? Array(meterOvers[(10 + index * 2)..<(12 + index * 2)]) : nil)
        }
        guard let pixels = DeviceDisplayRenderer.render(snapshot) else {
            return USBHelperResult(exitCode: 1, output: "Device display could not be rendered.")
        }
        if !force && pixels == lastDisplayPixels { return USBHelperResult(exitCode: 0, output: "Display unchanged.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenDuet-\(UUID().uuidString).rgb565")
        defer { try? FileManager.default.removeItem(at: url) }
        do { try Data(pixels).write(to: url, options: .atomic) }
        catch { return USBHelperResult(exitCode: 1, output: error.localizedDescription) }
        let result = await USBSession.shared.run(["--experimental-display", "device", url.path, "--apply"])
        if result.exitCode == 0, generation == displayGeneration { lastDisplayPixels = pixels }
        return result
    }

    func refreshAudio() {
        do {
            let snapshot = try NativeAudioDevice.snapshot()
            audio = snapshot
            selectedRate = snapshot.sampleRate
            audioMonitor?.trackRate(snapshot.id)
            synchronizeSystemVolume()
        } catch {
            audio = nil; audioMonitor?.trackRate(nil)
            synchronizeSystemVolume()
            status = error.localizedDescription
        }
    }

    private func synchronizeSystemVolume() {
        let output = physical.outputs[0]
        let ready = keyboardVolumeEnabled && connectionRequested && usbConnected && !running && !sleeping && output.known
        if !ready {
            let text = keyboardVolumeEnabled ? "Keyboard volume waits for an initialized Main Out." : "Keyboard volume bridge is off."
            if keyboardVolumeStatus != text { keyboardVolumeStatus = text }
        }
        volumeBridge?.update(device: audio?.id, state: ready ? .init(level: output.level, muted: output.muted) : nil)
        if !keyboardVolumeEnabled && keyboardVolumeStatus != "Keyboard volume bridge is off." {
            keyboardVolumeStatus = "Keyboard volume bridge is off."
        }
    }

    func applyRate() {
        guard !running else { return }
        let rate = selectedRate
        running = true
        Task {
            defer { running = false }
            do {
                audio = try await NativeAudioDevice.setSampleRate(rate)
                status = "Core Audio confirmed \(Int(rate)) Hz."
            } catch {
                let message = error.localizedDescription
                refreshAudio()
                status = message
            }
        }
    }

    func readModes() {
        guard !running else { return }
        running = true
        observedModes = nil
        let generation = controlGeneration
        Task {
            defer { running = false }
            let result = await USBHelper.run(["--input-modes"])
            guard generation == controlGeneration, !sleeping else { return }
            details = result.output
            if result.exitCode == 0, let snapshot = InputModeSnapshot(output: result.output) {
                observedModes = snapshot
                for index in 0..<2 {
                    inputs[index].mode = snapshot.modes[index]
                    if physical.inputs[index].mode != snapshot.modes[index] { physical.inputs[index].gain = nil }
                    physical.inputs[index].mode = snapshot.modes[index]
                }
                status = outputsNeedSetup
                    ? "Connected. Start Duet muted to initialize output controls; saved settings have not been applied."
                    : "Input sources read. Enable hardware controls to apply the displayed input gains."
            } else { status = failureMessage(result) }
        }
    }

    func setPhantom(_ enabled: Bool, input index: Int) {
        guard inputs.indices.contains(index) else { return }
        inputs[index].phantom = enabled
        guard usbConnected else { return }
        guard inputs[index].mode == .mic, physical.inputs[index].mode == .mic else {
            status = "Apply the Mic source before changing phantom power."
            return
        }
        run([["--experimental-phantom", String(index + 1), enabled ? "1" : "0", "--apply"]], label: "Input \(index + 1) phantom power") { [weak self] in
            guard let self else { return }
            physical.inputs[index].phantom = enabled
            selectedControl = index == 0 ? .input1 : .input2
            physical.selected = selectedControl
            focusDeadline = ContinuousClock.now.advanced(by: .seconds(4))
            status = "Input \(index + 1) phantom power \(enabled ? "enabled" : "disabled")."
        }
    }

    func setInputMode(_ mode: InputControlPacket.Mode, input index: Int) {
        guard inputs.indices.contains(index), !running else { return }
        inputs[index].mode = mode
        guard usbConnected else {
            status = "Input source is pending. Connect USB to apply it."
            return
        }
        let draft = inputs[index]
        let disablePhantom = mode != .mic && physical.inputs[index].phantom == true
        var commands: [[String]] = []
        if disablePhantom {
            commands.append(["--experimental-phantom", String(index + 1), "0", "--apply"])
        }
        commands.append(["--experimental-mode", String(index + 1), String(mode.rawValue), "--apply"])
        let gain = mode == .mic ? Int(draft.micGain) : mode == .instrument ? Int(draft.instrumentGain) : nil
        if let gain {
            commands.append([mode == .mic ? "--experimental-mic-gain" : "--experimental-instrument-gain", String(index + 1), String(gain), "--apply"])
        }
        commands.append(["--input-modes"])
        observedModes = nil
        run(commands, label: "Input \(index + 1) source") { [weak self] in
            guard let self else { return }
            guard let snapshot = InputModeSnapshot(output: details), snapshot.modes[index] == mode else {
                physical.inputs[index] = .init()
                hardwareEnabled = false
                status = "The input source could not be confirmed. Read inputs before using the knob."
                return
            }
            observedModes = snapshot
            physical.inputs[index].mode = mode
            physical.inputs[index].gain = gain
            if disablePhantom {
                physical.inputs[index].phantom = false
                inputs[index].phantom = false
            }
            if linkInputs && inputs[0].mode != inputs[1].mode { linkInputs = false }
            selectedControl = index == 0 ? .input1 : .input2
            physical.selected = selectedControl
            focusDeadline = ContinuousClock.now.advanced(by: .seconds(4))
            status = snapshot.description + ". Source confirmed; gain applied for the selected mode."
        }
    }

    func applyInput(_ index: Int) {
        guard inputs.indices.contains(index) else { return }
        let draft = inputs[index]
        let linked = linkInputs
        if linked && (inputs[0].mode != inputs[1].mode || (draft.mode != .mic && draft.mode != .instrument)) {
            status = "Linked gain requires both inputs to use the same mic or instrument source."
            return
        }
        let channels = linked ? [0, 1] : [index]
        var targetGains = inputs.map { draft.mode == .mic ? Int($0.micGain) : Int($0.instrumentGain) }
        if linked && physical.inputs.allSatisfy({ $0.mode == draft.mode && $0.gain != nil }) {
            let baseline = physical.inputs.compactMap(\.gain)
            guard let shifted = GainLink.shifting(baseline, by: targetGains[index] - baseline[index], maximum: draft.mode == .mic ? 75 : 65) else {
                status = "Input gain state is invalid. Apply the inputs independently first."
                return
            }
            targetGains = shifted
        }
        var commands: [[String]] = []
        for channel in channels {
            let target = String(channel + 1)
            commands.append(["--experimental-mode", target, String(draft.mode.rawValue), "--apply"])
            if draft.mode == .mic {
                commands.append(["--experimental-mic-gain", target, String(targetGains[channel]), "--apply"])
            } else if draft.mode == .instrument {
                commands.append(["--experimental-instrument-gain", target, String(targetGains[channel]), "--apply"])
            }
        }
        for (name, choice) in [("phantom", draft.phantom.map { $0 && draft.mode == .mic }), ("soft-limit", draft.softLimit), ("phase", draft.phase)] {
            guard let enabled = choice else { continue }
            commands.append(["--experimental-\(name)", String(index + 1), enabled ? "1" : "0", "--apply"])
        }
        observedModes = nil
        run(commands, label: "Input \(index + 1)") { [weak self] in
            guard let self else { return }
            for channel in channels {
                physical.inputs[channel] = .init(mode: draft.mode,
                    gain: draft.mode == .mic || draft.mode == .instrument ? targetGains[channel] : nil,
                    phantom: channel == index ? (draft.phantom.map { $0 && draft.mode == .mic } ?? physical.inputs[channel].phantom) : physical.inputs[channel].phantom,
                    softLimit: channel == index ? (draft.softLimit ?? physical.inputs[channel].softLimit) : physical.inputs[channel].softLimit,
                    phase: channel == index ? (draft.phase ?? physical.inputs[channel].phase) : physical.inputs[channel].phase)
                if linked {
                    if draft.mode == .mic { inputs[channel].micGain = Double(targetGains[channel]) }
                    else { inputs[channel].instrumentGain = Double(targetGains[channel]) }
                }
            }
        }
    }

    func applyRouting() {
        let route = OutputControlPacket.routing(main: main.route, headphones: headphones.route)
        let mono = OutputControlPacket.sumToMono(main: main.mono, headphones: headphones.mono)
        run([["--experimental-routing", "outputs", String(route.payload), "--apply"],
             ["--experimental-mono", "outputs", String(mono.payload), "--apply"]], label: "Output routing and mono") { [weak self] in
            guard let self else { return }
            physical.outputs[0].route = main.route; physical.outputs[1].route = headphones.route
            physical.outputs[0].mono = main.mono; physical.outputs[1].mono = headphones.mono
        }
    }

    func setLiveOutputRoute(_ route: OutputControlPacket.RouteSelector, headphone: Bool) {
        guard usbConnected, !running, !outputsNeedSetup,
              let mainRoute = physical.outputs[0].route, let headphoneRoute = physical.outputs[1].route else { return }
        if headphone { headphones.route = route } else { main.route = route }
        physical.outputs[headphone ? 1 : 0].route = route
        let packet = OutputControlPacket.routing(main: headphone ? mainRoute : route, headphones: headphone ? route : headphoneRoute)
        enqueueControl("routes", commands: [["--experimental-routing", "outputs", String(packet.payload), "--apply"]])
    }

    func setLiveReference(_ plus4: Bool) {
        guard usbConnected, !running, !outputsNeedSetup else { return }
        mainPlus4 = plus4
        enqueueControl("reference", commands: [["--experimental-reference", "main", plus4 ? "1" : "0", "--apply"]])
    }

    func setLiveMixerSource(_ source: MixerCoefficients.PlaybackSource) {
        guard usbConnected, !running, !outputsNeedSetup else { return }
        mixerSource = source
        enqueueLiveMixer()
    }

    func enqueueLiveMixer() {
        guard usbConnected, !running, !outputsNeedSetup, let banks = MixerCoefficients.encode(mixer) else { return }
        let hex = banks.map { $0.payload.map { String(format: "%02x", $0) }.joined() }
        enqueueControl("mixer", commands: [["--experimental-mixer-source", "mixer", String(mixerSource.rawValue), "--apply"],
                                           ["--experimental-mixer", hex[0], hex[1], "--apply"]])
    }

    func applyReference() {
        run([["--experimental-reference", "main", mainPlus4 ? "1" : "0", "--apply"]], label: "Main line reference")
    }

    func applyMixer() {
        guard let banks = MixerCoefficients.encode(mixer) else { status = "Mixer values are out of range."; return }
        let hex = banks.map { $0.payload.map { String(format: "%02x", $0) }.joined() }
        run([["--experimental-mixer-source", "mixer", String(mixerSource.rawValue), "--apply"],
             ["--experimental-mixer", hex[0], hex[1], "--apply"]], label: "Direct monitor mix")
    }

    func readMeters() {
        guard !running else { return }
        running = true
        Task {
            defer { running = false }
            let result = await USBHelper.run(["--meters"])
            meters = []
            details = result.output
            if result.exitCode == 0, let line = result.output.split(separator: "\n").first(where: { $0.hasPrefix("METERS ") }) {
                let hex = Array(line.dropFirst(7))
                let bytes = stride(from: 0, to: max(0, hex.count - 1), by: 2).compactMap {
                    UInt8(String(hex[$0...($0 + 1)]), radix: 16)
                }
                meters = MeterPacket(bytes: bytes)?.lanes.map(\.decibels) ?? []
                metersAvailable = meters.count == 10
                meterPresentation.refresh()
                status = meters.count == 10 ? "Raw meter snapshot read." : "Meter response was incomplete."
            } else { status = failureMessage(result) }
        }
    }

    private func run(_ commands: [[String]], label: String, onSuccess: (() -> Void)? = nil) {
        guard !running else { return }
        controlGeneration &+= 1
        controlWriteTask?.cancel(); controlWriteTask = nil; controlUpdates.clear()
        let generation = controlGeneration
        running = true
        status = "Applying \(label.lowercased())…"
        details = ""
        Task {
            defer { running = false }
            for command in commands {
                guard generation == controlGeneration, !sleeping else { return }
                let result = await USBHelper.run(command)
                guard generation == controlGeneration, !sleeping else { return }
                details += result.output + "\n"
                guard result.exitCode == 0 else {
                    physical.invalidate()
                    status = failureMessage(result) + " Earlier commands in this update may have completed."
                    return
                }
            }
            status = "\(label) updated."
            onSuccess?()
            meterPresentation.refresh()
            saveProfile()
        }
    }

    func enableHardwareControls(_ enabled: Bool) {
        guard enabled else { hardwareEnabled = false; return }
        guard usbConnected, !running else { return }
        let drafts = inputs
        var commands: [[String]] = []
        for index in 0..<2 {
            guard physical.inputs[index].mode == drafts[index].mode else {
                status = "Read inputs or apply their source settings before enabling hardware controls."
                return
            }
            let mode = drafts[index].mode
            if mode == .mic || mode == .instrument {
                let gain = mode == .mic ? drafts[index].micGain : drafts[index].instrumentGain
                commands.append([mode == .mic ? "--experimental-mic-gain" : "--experimental-instrument-gain", String(index + 1), String(Int(gain)), "--apply"])
            }
        }
        run(commands, label: "Input gains for hardware control") { [weak self] in
            guard let self else { return }
            for index in 0..<2 {
                let draft = drafts[index]
                physical.inputs[index].gain = draft.mode == .mic ? Int(draft.micGain) : draft.mode == .instrument ? Int(draft.instrumentGain) : nil
            }
            hardwareEnabled = true
            status = "Hardware controls enabled at the displayed input gains. Phantom power unchanged."
        }
    }

    private func handleHardware(_ report: DeviceEvents) {
        guard !running else { return }
        if !hardwareEnabled {
            // Selection is display-only and remains useful while audio settings need setup.
            if report.encoderPressed {
                physical.selected = PhysicalController.Target(rawValue: (physical.selected.rawValue + 1) % 4)!
                selectedControl = physical.selected
            }
            if report.encoderPressed || report.clockwiseSteps != 0 || report.counterclockwiseSteps != 0 {
                focusDeadline = ContinuousClock.now.advanced(by: .seconds(4))
                status = "Apply input gains and initialize outputs in the app before adjusting hardware levels."
            }
            return
        }
        if report.encoderPressed || report.clockwiseSteps != 0 || report.counterclockwiseSteps != 0 {
            focusDeadline = ContinuousClock.now.advanced(by: .seconds(4))
        }
        physical.actionA = touchpadA; physical.actionB = touchpadB
        physical.linkInputs = linkInputs
        let actions = physical.handle(report)
        if selectedControl != physical.selected { selectedControl = physical.selected }
        for action in actions {
            switch action {
            case .inputGain(let channel, let gain, let instrument):
                if instrument { inputs[channel - 1].instrumentGain = Double(gain) }
                else { inputs[channel - 1].micGain = Double(gain) }
                enqueueControl("input-\(channel)", commands: [[instrument ? "--experimental-instrument-gain" : "--experimental-mic-gain", String(channel), String(gain), "--apply"]])
            case .output(let index, let level, let muted, let dimmed):
                if setOutputLevel(Double(level), headphone: index == 1) {
                    setOutputMute(muted, headphone: index == 1)
                    setOutputDim(dimmed, headphone: index == 1)
                } else {
                    let previous = index == 0 ? main : headphones
                    physical.outputs[index].level = Int(previous.level)
                    physical.outputs[index].muted = previous.muted; physical.outputs[index].dimmed = previous.dimmed
                }
            case .mono(let mainMono, let headphoneMono):
                main.mono = mainMono; headphones.mono = headphoneMono
                enqueueControl("mono", commands: [["--experimental-mono", "outputs", String((mainMono ? 1 : 0) | (headphoneMono ? 16 : 0)), "--apply"]])
            case .routes(let mainRaw, let headphoneRaw):
                guard let mainRoute = OutputControlPacket.RouteSelector(rawValue: mainRaw),
                      let headphoneRoute = OutputControlPacket.RouteSelector(rawValue: headphoneRaw) else { continue }
                main.route = mainRoute; headphones.route = headphoneRoute
                enqueueControl("routes", commands: [["--experimental-routing", "outputs", String(mainRaw | headphoneRaw << 4), "--apply"]])
            case .message(let message): if status != message { status = message }
            case .clearMeters: clearMeterHolds()
            }
        }
    }

    private func enqueueOutput(_ index: Int) {
        let output = physical.outputs[index], target = index == 0 ? "main" : "headphones"
        let mute = ["--experimental-output-mute", target, output.muted ? "1" : "0", "--apply"]
        let gain = ["--experimental-attenuation", target, String(-output.level + (output.dimmed ? 15 : 0)), "--apply"]
        enqueueControl("output-\(index)", commands: output.muted ? [mute, gain] : [gain, mute])
    }

    func setQuickInputSwitch(_ enabled: Bool, input index: Int, phase: Bool) {
        guard inputs.indices.contains(index), usbConnected, !running else { return }
        if phase { inputs[index].phase = enabled; physical.inputs[index].phase = enabled }
        else { inputs[index].softLimit = enabled; physical.inputs[index].softLimit = enabled }
        let name = phase ? "phase" : "soft-limit"
        enqueueControl("\(name)-\(index)", commands: [["--experimental-\(name)", String(index + 1), enabled ? "1" : "0", "--apply"]])
    }

    func setQuickOutputMono(_ enabled: Bool, headphone: Bool) {
        guard usbConnected, !outputsNeedSetup, !running else { return }
        guard let mainMono = physical.outputs[0].mono, let headphoneMono = physical.outputs[1].mono else {
            status = "Apply output routes in the full mixer before adjusting mono."
            return
        }
        if headphone { headphones.mono = enabled } else { main.mono = enabled }
        physical.outputs[headphone ? 1 : 0].mono = enabled
        enqueueControl("mono", commands: [["--experimental-mono", "outputs", String(((headphone ? mainMono : enabled) ? 1 : 0) | ((headphone ? enabled : headphoneMono) ? 16 : 0)), "--apply"]])
    }

    /// Quick mixer gains use the same coalescing writer as the hardware encoder.
    func setQuickInputGain(_ value: Double, input index: Int) {
        guard inputs.indices.contains(index), usbConnected, !running else { return }
        let mode = inputs[index].mode
        guard mode == .mic || mode == .instrument,
              physical.inputs[index].mode == mode else { return }
        let maximum = mode == .mic ? 75 : 65
        let gain = max(0, min(maximum, Int(value.rounded())))
        var targets = [(index, gain)]
        if linkInputs {
            guard physical.inputs.allSatisfy({ $0.mode == mode && $0.gain != nil }),
                  let baseline = physical.inputs[index].gain,
                  let shifted = GainLink.shifting(physical.inputs.compactMap(\.gain), by: gain - baseline, maximum: maximum) else {
                status = "Apply linked input gains in the mixer before adjusting them here."
                return
            }
            targets = Array(shifted.enumerated()).map { ($0.offset, $0.element) }
        }
        for (channel, target) in targets {
            if mode == .mic { inputs[channel].micGain = Double(target) }
            else { inputs[channel].instrumentGain = Double(target) }
            physical.inputs[channel].gain = target
            enqueueControl("input-\(channel + 1)", commands: [[mode == .mic ? "--experimental-mic-gain" : "--experimental-instrument-gain", String(channel + 1), String(target), "--apply"]])
        }
        selectedControl = index == 0 ? .input1 : .input2
        physical.selected = selectedControl
        focusDeadline = ContinuousClock.now.advanced(by: .seconds(4))
    }

    func setOutputMute(_ enabled: Bool, headphone: Bool) {
        if headphone { headphones.muted = enabled } else { main.muted = enabled }
        let index = headphone ? 1 : 0
        guard usbConnected, physical.outputs[index].known else { return }
        physical.outputs[index].muted = enabled
        enqueueOutput(index)
    }

    func setOutputDim(_ enabled: Bool, headphone: Bool) {
        if headphone { headphones.dimmed = enabled } else { main.dimmed = enabled }
        let index = headphone ? 1 : 0
        guard usbConnected, physical.outputs[index].known else { return }
        physical.outputs[index].dimmed = enabled
        enqueueOutput(index)
    }

    @discardableResult
    func setOutputLevel(_ value: Double, headphone: Bool, confirmed: Bool = false) -> Bool {
        guard value.isFinite else { return false }
        let index = headphone ? 1 : 0
        let draft = headphone ? headphones : main
        let ceiling = 0
        let level = max(-64, min(ceiling, Int(max(-64, min(0, value)).rounded())))
        guard usbConnected, physical.outputs[index].known else {
            status = "Initialize the device before adjusting outputs."
            return false
        }
        if safetyEnabled && !confirmed {
            if pendingOutputIncrease != nil && level > Int(draft.level) { return false }
            let decision = OutputSafety.evaluate(requested: level, current: Int(draft.level), ceiling: ceiling)
            if case .confirm(let target) = decision {
                let request = OutputIncreaseRequest(generation: controlGeneration, headphone: headphone, from: Int(draft.level), target: target)
                pendingOutputIncrease = request
                // The hardware encoder may already have changed its host-side cache.
                physical.outputs[index].level = Int(draft.level)
                physical.outputs[index].muted = draft.muted; physical.outputs[index].dimmed = draft.dimmed
                status = request.isMaximum ? "Maximum output held for confirmation." : "Large volume increase held for confirmation."
                safetyPrompt?(request) { [weak self] approved in self?.resolveOutputIncrease(approved) }
                return false
            }
        }
        if headphone { headphones.level = Double(level) } else { main.level = Double(level) }
        physical.outputs[index].level = level
        selectedControl = headphone ? .headphones : .main
        physical.selected = selectedControl
        focusDeadline = ContinuousClock.now.advanced(by: .seconds(4))
        enqueueOutput(index)
        return true
    }

    func resolveOutputIncrease(_ approved: Bool) {
        guard let request = pendingOutputIncrease else { return }
        pendingOutputIncrease = nil
        let index = request.headphone ? 1 : 0
        let current = request.headphone ? headphones : main
        guard approved, request.generation == controlGeneration, physical.outputs[index].known, Int(current.level) == request.from, request.target <= 0 else {
            status = "Volume increase cancelled; current level retained."
            synchronizeSystemVolume(); return
        }
        _ = setOutputLevel(Double(request.target), headphone: request.headphone, confirmed: true)
        status = "Volume increase confirmed."
    }

    private func enqueueControl(_ key: String, commands: [[String]]) {
        guard usbConnected, !commands.isEmpty else { return }
        controlUpdates.put(key, commands: commands)
        guard controlWriteTask == nil else { return }
        let generation = controlGeneration
        controlWriteTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == controlGeneration { controlWriteTask = nil } }
            while !Task.isCancelled && usbConnected && generation == controlGeneration {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
                if running { continue }
                guard let batch = controlUpdates.take() else { saveProfile(); synchronizeSystemVolume(); return }
                for command in batch {
                    let result = await USBSession.shared.run(command)
                    if Task.isCancelled { return }
                    guard result.exitCode == 0 else {
                        controlUpdates.clear(); physical.invalidate()
                        hardwareEnabled = false
                        synchronizeSystemVolume()
                        details = result.output
                        status = failureMessage(result)
                        return
                    }
                }
            }
        }
    }

    private func failureMessage(_ result: USBHelperResult) -> String {
        if result.output.contains("0xe00002c5") { return "The Duet is in use by another application or service." }
        if result.output.contains("Duet not found") { return "Connect the Duet USB interface." }
        if result.output.contains("Gain not sent") { return "Gain was not changed because the active input source could not be confirmed." }
        return "The device operation did not complete. See details."
    }

    private struct Profile: Codable {
        let version: Int
        let inputs: [InputDraft]
        let main: OutputDraft
        let headphones: OutputDraft
        let mainPlus4: Bool
        let linkInputs: Bool
        let mixerSource: MixerCoefficients.PlaybackSource
        let mixer: MixerCoefficients.State

        var valid: Bool {
            version == 1 && inputs.count == 2 && inputs.allSatisfy {
                $0.micGain.isFinite && (0...75).contains($0.micGain) && $0.micGain.rounded() == $0.micGain &&
                $0.instrumentGain.isFinite && (0...65).contains($0.instrumentGain) && $0.instrumentGain.rounded() == $0.instrumentGain
            } && [main, headphones].allSatisfy {
                $0.level.isFinite && (-64...0).contains($0.level) && $0.level.rounded() == $0.level
            } && MixerCoefficients.encode(mixer) != nil
        }
    }

    private func saveProfile() {
        let profile = Profile(version: 1, inputs: inputs, main: main, headphones: headphones,
                              mainPlus4: mainPlus4, linkInputs: linkInputs, mixerSource: mixerSource, mixer: mixer)
        guard profile.valid, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: "OpenDuet.profile.v1")
    }

    private func restoreProfile() {
        guard let data = UserDefaults.standard.data(forKey: "OpenDuet.profile.v1") else { return }
        guard data.count <= 65536, let profile = try? JSONDecoder().decode(Profile.self, from: data), profile.valid else {
            status = "Saved settings were invalid and were not loaded."
            return
        }
        inputs = profile.inputs; main = profile.main; headphones = profile.headphones
        mainPlus4 = profile.mainPlus4; linkInputs = profile.linkInputs
        mixerSource = profile.mixerSource; mixer = profile.mixer
        status = "Saved choices loaded as pending settings. No hardware settings have been applied."
    }
}
