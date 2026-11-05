import Foundation

enum RouteSnapshot {
    static func report(at url: URL) throws -> String {
        let document = try XMLDocument(contentsOf: url, options: [.nodeLoadExternalEntitiesNever])
        let paths = [
            ("Main Out", "//hwout0/@routeSource"),
            ("Headphones", "//hwout1/@routeSource"),
            ("Mixer playback return", "//mixer0/channels/channel2/@routeSource")
        ]
        return try paths.map { label, path in
            let values = try document.nodes(forXPath: path)
            guard values.count == 1, let value = values.first?.stringValue,
                  let route = UInt32(value) else {
                return "\(label)  unavailable"
            }
            let raw = String(format: "0x%08X", route)
            let source = OutputControlPacket.RouteSelector(sourceID: route)?.title ?? "Unmapped route"
            return "\(label)  \(source) (\(raw))"
        }.joined(separator: "\n")
    }
}
