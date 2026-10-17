import Foundation

/// A product as the store presents it: always show `displayPrice`, StoreKit's
/// localised, VAT-inclusive total.
public struct ProductInfo: Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var displayPrice: String
    public var kind: ShopProduct.Kind
}

public enum PurchaseOutcome: Equatable, Sendable {
    /// Verified and finished. Bundles, the starter pack and the Housewarming
    /// pack carry Beans; the app records them once per transaction id.
    case purchased(productID: String, transactionID: String)
    /// Waiting for Ask to Buy or a payment issue to clear.
    case pending
    case cancelled
}

public enum StoreError: Error, Equatable {
    case unknownProduct(String)
    /// The store returned a transaction that failed verification: no entitlement.
    case unverified
}

/// The store layer the app talks to. Implemented on StoreKit 2 directly
/// (`StoreKitEntitlementService`) and through RevenueCat
/// (`RevenueCatEntitlementService`); the app picks RevenueCat once an API key
/// is configured.
@MainActor
public protocol EntitlementService: AnyObject {
    /// Every product and what it unlocks.
    var catalog: StoreCatalog { get }
    /// The current entitlements: the Keychain mirror at launch, then the store's.
    var entitlements: Entitlements { get }
    /// Re-derives entitlements from the store's current verified transactions.
    func refresh() async
    func products() async throws -> [ProductInfo]
    func purchase(_ productID: String) async throws -> PurchaseOutcome
    /// The Restore Purchases button (shop, paywall, Settings).
    func restore() async throws
}
