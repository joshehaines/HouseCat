// swift-tools-version: 6.2
import PackageDescription

/// The store layer: every product, the `EntitlementService` protocol, and its
/// StoreKit 2 and RevenueCat implementations. Entitlements are derived from
/// verified transactions, held in memory and mirrored to the Keychain, never
/// written to the synced save.
let package = Package(
    name: "HouseCatStore",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "HouseCatStore", targets: ["HouseCatStore"]),
    ],
    dependencies: [
        .package(path: "../HouseCatCore"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.96.0"),
    ],
    targets: [
        .target(name: "HouseCatStore", dependencies: [
            "HouseCatCore",
            .product(name: "RevenueCat", package: "purchases-ios-spm"),
        ]),
        .testTarget(name: "HouseCatStoreTests", dependencies: ["HouseCatStore"]),
    ]
)
