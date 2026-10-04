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
    ],
    targets: [
        .target(name: "BridgeCore"),
        .executableTarget(
            name: "RumlogProbe",
            dependencies: ["BridgeCore"]
        ),
        .executableTarget(
            name: "BridgeAgent",
            dependencies: ["BridgeCore"]
        ),
        .testTarget(
            name: "BridgeCoreTests",
            dependencies: ["BridgeCore"]
        ),
    ]
)
