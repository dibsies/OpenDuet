#!/bin/bash
# Native window lifecycle checks; no USB session or audio stream is created.
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/check.swift" <<'SWIFT'
import AppKit
@main struct Test {
    @MainActor static func main() {
        func expect(_ condition: @autoclosure () -> Bool) {
            if !condition() {
                FileHandle.standardError.write(Data("Window lifecycle check failed; no trap raised.\n".utf8))
                exit(1)
            }
        }
        let app = NSApplication.shared
        let lifecycle = AppLifecycle()
        app.delegate = lifecycle
        expect(!lifecycle.applicationShouldTerminateAfterLastWindowClosed(app))
        let console = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 140), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        console.identifier = NSUserInterfaceItemIdentifier("console")
        console.isReleasedWhenClosed = false
        let settings = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        // A same-title transient window must never be treated as the console.
        settings.title = "OpenDuet"
        settings.identifier = NSUserInterfaceItemIdentifier("settings")
        settings.isReleasedWhenClosed = false
        console.orderFront(nil); settings.orderFront(nil)
        for _ in 0..<3 {
            // The command-line harness cannot model SwiftUI's application-hide
            // lifecycle. Exercise reveal here; installed hide needs a real app test.
            console.orderOut(nil)
            expect(ConsoleWindowActions.consoleWindows(in: [console, settings]) == [console])
            ConsoleWindowActions.reveal(in: [console, settings])
            expect(console.isVisible && settings.isVisible)
        }
        console.close()
        ConsoleWindowActions.reveal(in: [console, settings])
        expect(console.isVisible && !app.isHidden)
        console.orderOut(nil); settings.orderOut(nil)
        print("Console reveal/closed-window recovery, transient isolation and keep-running policy passed; installed hide check remains separate")
    }
}
SWIFT
swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{ConsoleWindowActions,AppLifecycle}.swift "$scratch/check.swift" -o "$scratch/check"
"$scratch/check"
