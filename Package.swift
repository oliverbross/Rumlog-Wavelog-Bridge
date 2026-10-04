// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RumlogWavelogBridge",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
        .executable(name: "rumlog-probe", targets: ["RumlogProbe"]),
        .executable(name: "rumlog-wavelog-bridge", targets: ["BridgeAgent"]),
        .executable(name: "bridge-bootstrap", targets: ["BridgeBootstrap"]),
        .executable(name: "bridge-audit", targets: ["BridgeAudit"]),
        .executable(name: "bridge-repair", targets: ["BridgeRepair"]),
    ],
    targets: [
        .target(
            name: "BridgeCore",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "RumlogProbe",
            dependencies: ["BridgeCore"]
        ),
        .executableTarget(
            name: "BridgeAgent",
            dependencies: ["BridgeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "BridgeBootstrap",
            dependencies: ["BridgeCore"]
        ),
        .executableTarget(
            name: "BridgeAudit",
            dependencies: ["BridgeCore"]
        ),
        .executableTarget(
            name: "BridgeRepair",
            dependencies: ["BridgeCore"]
        ),
        .testTarget(
            name: "BridgeCoreTests",
            dependencies: ["BridgeCore"]
        ),
    ]
)
