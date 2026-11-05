// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDuet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "openduet", targets: ["OpenDuet"]),
        .executable(name: "openduet-identify", targets: ["DuetIdentifier"])
    ],
    targets: [
        .executableTarget(name: "OpenDuet"),
        .executableTarget(
            name: "DuetIdentifier",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        )
    ]
)
