import SwiftUI
import AppKit

@main
@MainActor
struct OpenDuet {

    static func main() {
        if CommandLine.arguments.contains("--discover") {
            print(Discovery.report())
        } else if CommandLine.arguments.dropFirst().first == "--preview-attenuation" {
            let arguments = Array(CommandLine.arguments.dropFirst(2))
            guard arguments.count == 2 || (arguments.count == 3 && arguments[2] == "--dim"),
                  ["main", "headphones"].contains(arguments[0]),
                  let level = Double(arguments[1]),
                  let packets = OutputControlPacket.attenuation(
                    level: level, dimmed: arguments.count == 3,
                    output: arguments[0] == "main" ? .main : .headphones
                  ) else {
                FileHandle.standardError.write(Data(
                    "Usage: openduet --preview-attenuation <main|headphones> <dB from -64 to 0> [--dim]\n".utf8
                ))
                exit(64)
            }
            for packet in packets {
                print((packet.setupBytes + [packet.payload]).map {
                    String(format: "%02X", $0)
                }.joined(separator: " "))
            }
        } else if CommandLine.arguments.dropFirst().first == "--saved-routes" {
            guard CommandLine.arguments.count == 3 else {
                FileHandle.standardError.write(Data("Usage: openduet --saved-routes <DuetII settings XML>\n".utf8))
                exit(64)
            }
            do {
                print(try RouteSnapshot.report(at: URL(fileURLWithPath: CommandLine.arguments[2])))
            } catch {
                FileHandle.standardError.write(Data("Unable to read route snapshot: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        } else {
            launch()
        }
    }

    static let brandMark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "OpenDuetMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    private static let dockIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "OpenDuet", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    static func configureAppIcon() {
        if let icon = dockIcon {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    private static func launch() {
        configureAppIcon()
        // Launch through a separate SwiftUI App to use SwiftUI's default entry point.
        DiscoveryWindow.main()
    }

}

private struct DiscoveryWindow: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @StateObject private var model = DiscoveryModel()
    @StateObject private var controller = ConsoleModel(safetyPrompt: VolumeSafetyPresenter.present)
    @AppStorage("menuBarMixerEnabled") private var menuBarMixerEnabled = true

    var body: some Scene {
        Window("OpenDuet", id: "console") {
            TabView {
                ConsoleView(model: controller).tabItem { Label("Console", systemImage: "slider.horizontal.3") }
                ConsoleDiagnosticsView(model: controller, report: model.report, refresh: { model.report = Discovery.report() })
                    .tabItem { Label("Diagnostics", systemImage: "wrench.and.screwdriver") }
            }
                .onAppear {
                    OpenDuet.configureAppIcon()
                    model.report = Discovery.report()
                }
        }
        .commands { GuideCommands() }
        Settings {
            Form {
                Toggle("Show quick mixer in menu bar", isOn: $menuBarMixerEnabled)
                Divider()
                Toggle("Keyboard volume controls Main Out", isOn: $controller.keyboardVolumeEnabled)
                    .help("Fixed 2 dB steps while Duet USB is the default output. Headphones remain independent.")
                Text(controller.keyboardVolumeStatus).font(.caption).foregroundStyle(.secondary)

            }.padding(24).frame(width: 380).preferredColorScheme(.dark)
        }
        MenuBarExtra("OpenDuet", systemImage: "slider.vertical.3", isInserted: $menuBarMixerEnabled) {
            MenuBarControls(model: controller)
        }
        .menuBarExtraStyle(.window)
    }

}

@MainActor
private final class DiscoveryModel: ObservableObject {
    @Published var report = ""
}
