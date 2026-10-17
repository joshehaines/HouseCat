// swift-tools-version: 6.2
import PackageDescription

/// Every game rule lives here. Pure Swift on Foundation: never UIKit, SwiftUI,
/// SpriteKit or SwiftData, so the app, widgets, Watch and Mac compute the same
/// state and every rule is testable without a simulator.
let package = Package(
    name: "HouseCatCore",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "HouseCatCore", targets: ["HouseCatCore"]),
    ],
    targets: [
        .target(name: "HouseCatCore"),
        .testTarget(name: "HouseCatCoreTests", dependencies: ["HouseCatCore"]),
    ]
)
