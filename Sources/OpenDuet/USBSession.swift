import Foundation

/// Owns a single helper process and serializes validated commands with live reads.
actor USBSession {
    static let shared = USBSession()
    enum Event: Sendable {
        case connected
        case meters([Double])
        case hardware(DeviceEvents)
        case diagnostic(String)
        case disconnected(Int32)
    }

    private var process: Process?
    private var input: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var continuation: AsyncStream<Event>.Continuation?
    private var ready = false
    private var generation: UInt64 = 0
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<USBHelperResult, Never>] = [:]
    private var frameID: Int?
    private var frameLines: [String] = []

    var isConnected: Bool { ready && process?.isRunning == true }

    func start() throws -> AsyncStream<Event> {
        guard process == nil else { throw sessionError("A USB session is already open") }
        generation &+= 1
        let generation = generation
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let process = Process(), output = Pipe(), input = Pipe()
        process.executableURL = USBHelper.executableURL
        process.arguments = ["--session"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        self.process = process
        self.input = input.fileHandleForWriting
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.stop(generation: generation) } }
        let handle = output.fileHandleForReading
        readerTask = Task.detached { [weak self] in
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 10) {
                    let line = String(decoding: buffer[..<newline], as: UTF8.self)
                    buffer.removeSubrange(...newline)
                    await self?.receive(line)
                }
                if buffer.count > 65536 { break }
            }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            await self?.ended(process.terminationStatus)
        }
        return stream
    }

    func run(_ arguments: [String]) async -> USBHelperResult {
        guard ready, let input, process?.isRunning == true else {
            return USBHelperResult(exitCode: 1, output: "USB session is not connected.")
        }
        guard arguments.count <= 4, arguments.allSatisfy({ !$0.isEmpty && !$0.contains(where: \.isWhitespace) }), nextID <= 999999999 else {
            return USBHelperResult(exitCode: 64, output: "Invalid session command.")
        }
        let id = nextID
        nextID += 1
        return await withCheckedContinuation { response in
            pending[id] = response
            do {
                try input.write(contentsOf: Data(("\(id) " + arguments.joined(separator: " ") + "\n").utf8))
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    await self?.expire(id)
                }
            } catch {
                pending.removeValue(forKey: id)?.resume(returning: USBHelperResult(exitCode: 1, output: error.localizedDescription))
            }
        }
    }

    func stop() {
        stop(generation: generation)
    }

    private func stop(generation: UInt64) {
        guard generation == self.generation else { return }
        ready = false
        try? input?.write(contentsOf: Data("QUIT\n".utf8))
        try? input?.close()
        input = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.terminateIfNeeded(generation: generation)
        }
    }

    private func terminateIfNeeded(generation: UInt64) {
        guard generation == self.generation else { return }
        if process?.isRunning == true { process?.terminate() }
    }

    private func expire(_ id: Int) {
        guard let response = pending.removeValue(forKey: id) else { return }
        response.resume(returning: USBHelperResult(exitCode: -2, output: "USB command timed out; session is closing."))
        stop()
    }

    private func receive(_ line: String) {
        if line == "SESSION_READY" {
            ready = true
            continuation?.yield(.connected)
        } else if line.hasPrefix("BEGIN "), let id = Int(line.dropFirst(6)) {
            frameID = id; frameLines = []
        } else if line.hasPrefix("END ") {
            let fields = line.split(separator: " ")
            if fields.count == 3, let id = Int(fields[1]), let code = Int32(fields[2]), frameID == id {
                pending.removeValue(forKey: id)?.resume(returning: USBHelperResult(exitCode: code, output: frameLines.joined(separator: "\n")))
            }
            frameID = nil; frameLines = []
        } else if frameID != nil {
            frameLines.append(line)
        } else if line.hasPrefix("METERS "), let bytes = Self.hex(String(line.dropFirst(7)), count: 20), let packet = MeterPacket(bytes: bytes) {
            continuation?.yield(.meters(packet.lanes.map(\.decibels)))
        } else if line.hasPrefix("EVENTS "), let bytes = Self.hex(String(line.dropFirst(7)), count: 29), let report = DeviceEvents(bytes: bytes) {
            continuation?.yield(.hardware(report))
        } else if !line.isEmpty {
            continuation?.yield(.diagnostic(line))
        }
    }

    private func ended(_ code: Int32) {
        ready = false
        for response in pending.values { response.resume(returning: USBHelperResult(exitCode: 1, output: "USB connection closed before the command completed.")) }
        pending.removeAll()
        continuation?.yield(.disconnected(code))
        continuation?.finish()
        continuation = nil
        process = nil
        try? input?.close(); input = nil
        frameID = nil; frameLines = []
        readerTask = nil
    }

    private static func hex(_ value: String, count: Int) -> [UInt8]? {
        guard value.utf8.count == count * 2 else { return nil }
        let characters = Array(value.utf8)
        var result: [UInt8] = []
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(decoding: characters[index...index + 1], as: UTF8.self), radix: 16) else { return nil }
            result.append(byte)
        }
        return result
    }

    private func sessionError(_ description: String) -> NSError {
        NSError(domain: "OpenDuet.USB", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
}
