import AppKit
import SwiftUI

@MainActor
final class VolumeSafetyPresenter: NSObject, NSWindowDelegate {
    private static let shared = VolumeSafetyPresenter()
    private var window: NSWindow?
    private var completion: ((Bool) -> Void)?

    static func present(_ request: OutputIncreaseRequest, completion: @escaping (Bool) -> Void) {
        shared.show(request, completion: completion)
    }

    private func show(_ request: OutputIncreaseRequest, completion: @escaping (Bool) -> Void) {
        guard window == nil else { completion(false); return }
        self.completion = completion
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 230),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "OpenDuet · Volume guard"
        panel.identifier = NSUserInterfaceItemIdentifier("volume-guard")
        panel.isReleasedWhenClosed = false; panel.isRestorable = false
        panel.hidesOnDeactivate = false; panel.level = .floating
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: Prompt(request: request, resolve: { [weak self] in self?.resolve($0) }))
        window = panel
        panel.center(); panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resolve(_ approved: Bool) {
        let callback = completion; completion = nil
        window?.close(); window = nil
        callback?(approved)
    }

    func windowWillClose(_ notification: Notification) {
        let callback = completion; completion = nil; window = nil
        callback?(false)
    }

    private struct Prompt: View {
        let request: OutputIncreaseRequest
        let resolve: (Bool) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Label(request.isMaximum ? "Maximum output held" : "Large volume increase held", systemImage: "speaker.badge.exclamationmark")
                    .font(.headline)
                Text("\(request.title): \(request.from) → \(request.target) dB (+\(request.target - request.from) dB)")
                    .font(.title3).monospacedDigit()
                Text(request.isMaximum ? "0 dB applies no master attenuation. Confirm to use full output." : "Use smaller adjustments, or confirm this increase.").foregroundStyle(.secondary)
                HStack {
                    Button("Keep current level") { resolve(false) }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Raise to \(request.target) dB") { resolve(true) }
                }
            }.padding(24).frame(width: 440).preferredColorScheme(.dark)
        }
    }
}
