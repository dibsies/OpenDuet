import Foundation

struct USBHelperResult: Sendable {
    let exitCode: Int32
    let output: String
}

enum USBHelper {
    static var executableURL: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().appendingPathComponent("openduet-identify")
    }
    static func run(_ arguments: [String]) async -> USBHelperResult {
        if await USBSession.shared.isConnected { return await USBSession.shared.run(arguments) }
        let executable = executableURL
        return await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return USBHelperResult(exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
            } catch {
                return USBHelperResult(exitCode: -1, output: error.localizedDescription)
            }
        }.value
    }
}
