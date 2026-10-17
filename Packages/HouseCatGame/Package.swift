// swift-tools-version: 6.2
import PackageDescription

/// SpriteKit scenes (exterior, rooms, the cat puppet, furniture). Scenes read
/// state from HouseCatCore and never compute rules.
let package = Package(
    name: "HouseCatGame",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "HouseCatGame", targets: ["HouseCatGame"]),
    ],
    dependencies: [
        .package(path: "../HouseCatCore"),
    ],
    targets: [
        .target(name: "HouseCatGame", dependencies: ["HouseCatCore"]),
        .testTarget(name: "HouseCatGameTests", dependencies: ["HouseCatGame"]),
    ]
)
