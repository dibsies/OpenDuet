import AppKit

/// Keep visibility changes independent of application termination and USB lifetime.
@MainActor
enum ConsoleWindowActions {
    static func consoleWindows(in windows: [NSWindow]) -> [NSWindow] {
        windows.filter { $0.identifier?.rawValue == "console" }
    }

    static func reveal(in windows: [NSWindow]? = nil) {
        NSApp.unhide(nil)
        for window in consoleWindows(in: windows ?? NSApp.windows) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
