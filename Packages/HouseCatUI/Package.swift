// swift-tools-version: 6.2
import PackageDescription

/// Shared SwiftUI views used by the app, widgets, Watch and Mac. Views read
/// state from HouseCatCore and never compute rules.
let package = Package(
    name: "HouseCatUI",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "HouseCatUI", targets: ["HouseCatUI"]),
    ],
    dependencies: [
        .package(path: "../HouseCatCore"),
        .package(path: "../HouseCatGame"),
    ],
    targets: [
        .target(name: "HouseCatUI", dependencies: ["HouseCatCore", "HouseCatGame"]),
        .testTarget(name: "HouseCatUITests", dependencies: ["HouseCatUI"]),
    ]
)
