// swift-tools-version: 6.2
import PackageDescription

/// SwiftData persistence for the player's own save: the append-only event log
/// and its snapshot, stored in the App Group and mirrored to the CloudKit
/// private database. Holds no rules; HouseCatCore derives all state.
let package = Package(
    name: "HouseCatModels",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "HouseCatModels", targets: ["HouseCatModels"]),
    ],
    dependencies: [
        .package(path: "../HouseCatCore"),
    ],
    targets: [
        .target(name: "HouseCatModels", dependencies: ["HouseCatCore"]),
        .testTarget(name: "HouseCatModelsTests", dependencies: ["HouseCatModels"]),
    ]
)
