import Foundation

/// A product as the store presents it: always show `displayPrice`, StoreKit's
/// localised, VAT-inclusive total.
public struct ProductInfo: Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var displayPrice: String
    public var kind: ShopProduct.Kind
    /// The price as a number and its currency, for sums the shop shows ("bought one by one, £81.74").
    public var price: Decimal?
    public var currencyCode: String?
    /// A free trial's length in days, only when the product has one AND this player may take it (StoreKit's
    /// `Product.SubscriptionInfo.isEligibleForIntroOffer`: a current or former subscriber gets no trial, so the
    /// paywall must not promise one). Nil means the plain renewal price is all there is to say.
    public var trialDays: Int?

    public init(
        id: String,
        displayName: String,
        displayPrice: String,
        kind: ShopProduct.Kind,
        price: Decimal? = nil,
        currencyCode: String? = nil,
        trialDays: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.kind = kind
        self.price = price
        self.currencyCode = currencyCode
        self.trialDays = trialDays
    }
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

/// Something a purchase puts in the save (Beans, a room look's pieces), once per transaction. The app records it
/// as an event keyed by the transaction, so hearing it twice changes nothing.
public struct StoreGrant: Equatable, Sendable {
    public var productID: String
    public var transactionID: String

    public init(productID: String, transactionID: String) {
        self.productID = productID
        self.transactionID = transactionID
    }
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
    /// Told about every purchase that puts something in the save: as it happens, Bean packs bought while the
    /// app was closed (finished only once handed over), and room looks and the starter on each refresh.
    var onGrant: (@MainActor (StoreGrant) -> Void)? { get set }
}
