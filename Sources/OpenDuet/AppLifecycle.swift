import AppKit
import OSLog

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "org.openduet.experimental", category: "Lifecycle")

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.log.info("Last window closed; hardware controller remains running")
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.log.info("Application termination requested")
        return .terminateNow
    }

    static func noteHideRequest() {
        log.info("Hide console requested through SwiftUI scene dismissal")
    }

    static func quitFromQuickMixer() {
        log.info("Explicit Quit selected in quick mixer")
        NSApp.terminate(nil)
    }
}
