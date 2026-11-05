import SwiftUI
import AppKit

struct UserGuideView: View {
    private struct Section: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }
    private let sections: [Section]

    init() {
        let url = Bundle.main.url(forResource: "GUIDE", withExtension: "md")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("GUIDE.md")
        let document = (try? String(contentsOf: url, encoding: .utf8)) ?? "# OpenDuet Guide\n\nThe guide could not be loaded. Reinstall the complete application bundle."
        sections = document.components(separatedBy: "\n## ").enumerated().map { index, block in
            let lines = block.components(separatedBy: "\n")
            return Section(title: index == 0 ? "Overview" : (lines.first ?? ""),
                           text: lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    if let mark = OpenDuet.brandMark { Image(nsImage: mark).resizable().frame(width: 36, height: 36) }
                    Text("OpenDuet Guide").font(.largeTitle.weight(.semibold))
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.title3.weight(.semibold))
                        Text((try? AttributedString(markdown: section.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(section.text))
                            .font(.body).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(30)
        }.preferredColorScheme(.dark).tint(.mint)
            .frame(minWidth: 560, minHeight: 460)
    }
}

struct GuideCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("OpenDuet Guide") { UserGuidePresenter.show() }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

@MainActor
private enum UserGuidePresenter {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let guide = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 760),
                                 styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            guide.title = "OpenDuet Guide"
            guide.identifier = NSUserInterfaceItemIdentifier("guide")
            guide.isReleasedWhenClosed = false
            guide.isRestorable = false
            guide.contentView = NSHostingView(rootView: UserGuideView())
            guide.center()
            window = guide
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
