// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Nexus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NexusCore", targets: ["NexusCore"]),
        .executable(name: "NexusMac", targets: ["NexusMac"]),
        .executable(name: "nexus-debug", targets: ["nexus-debug"])
    ],
    targets: [
        .target(
            name: "NexusCore",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "NexusMac",
            dependencies: ["NexusCore"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "nexus-debug",
            dependencies: ["NexusCore"]
        ),
        .testTarget(
            name: "NexusCoreTests",
            dependencies: ["NexusCore"]
        )
    ]
)
