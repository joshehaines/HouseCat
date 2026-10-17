import Foundation
import Observation
import RevenueCat

/// `EntitlementService` through RevenueCat (on StoreKit 2). A customer-info
/// verification result of `.failed` means no entitlement at all.
@MainActor
@Observable
public final class RevenueCatEntitlementService: EntitlementService {
    public private(set) var entitlements: Entitlements
    public let catalog: StoreCatalog
    private let cache: EntitlementCache

    public init(apiKey: String, catalog: StoreCatalog, cache: EntitlementCache) {
        self.catalog = catalog
        self.cache = cache
        entitlements = cache.load() ?? .none
        if !Purchases.isConfigured {
            Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey)
                .with(storeKitVersion: .storeKit2)
                .with(entitlementVerificationMode: .informational)
                .build())
        }
    }

    public func refresh() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        apply(info)
    }

    private func apply(_ info: CustomerInfo) {
        let derived = Self.entitlements(from: info, catalog: catalog, now: Date())
        entitlements = derived
        cache.save(derived)
    }

    static func entitlements(from info: CustomerInfo, catalog: StoreCatalog, now: Date) -> Entitlements {
        guard info.entitlements.verification != .failed else { return .none }
        var records = info.nonSubscriptions.map {
            PurchaseRecord(productID: $0.productIdentifier, transactionID: $0.transactionIdentifier, isVerified: true)
        }
        for productID in info.activeSubscriptions {
            records.append(PurchaseRecord(
                productID: productID,
                transactionID: "subscription:\(productID)",
                isVerified: true,
                expiresAt: info.expirationDate(forProductIdentifier: productID)
            ))
        }
        return EntitlementMapper.entitlements(from: records, catalog: catalog, now: now)
    }

    public func products() async throws -> [ProductInfo] {
        await Purchases.shared.products(catalog.productIDs).compactMap { product in
            guard let entry = catalog.product(product.productIdentifier) else { return nil }
            return ProductInfo(
                id: product.productIdentifier,
                displayName: product.localizedTitle,
                displayPrice: product.localizedPriceString,
                kind: entry.kind
            )
        }
    }

    public func purchase(_ productID: String) async throws -> PurchaseOutcome {
        guard catalog.product(productID) != nil, let product = await Purchases.shared.products([productID]).first else {
            throw StoreError.unknownProduct(productID)
        }
        let result = try await Purchases.shared.purchase(product: product)
        if result.userCancelled {
            return .cancelled
        }
        guard result.customerInfo.entitlements.verification != .failed else { throw StoreError.unverified }
        apply(result.customerInfo)
        guard let transaction = result.transaction else { return .pending }
        return .purchased(productID: productID, transactionID: transaction.transactionIdentifier)
    }

    public func restore() async throws {
        try await apply(Purchases.shared.restorePurchases())
    }
}
