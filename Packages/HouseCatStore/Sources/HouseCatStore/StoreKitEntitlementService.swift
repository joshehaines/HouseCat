import Foundation
import Observation
import StoreKit

/// `EntitlementService` on StoreKit 2. Only `.verified` transactions count;
/// revoked and expired ones are dropped on every refresh.
@MainActor
@Observable
public final class StoreKitEntitlementService: EntitlementService {
    public private(set) var entitlements: Entitlements
    public let catalog: StoreCatalog
    private let cache: EntitlementCache
    @ObservationIgnored private var updates: Task<Void, Never>?

    public init(catalog: StoreCatalog, cache: EntitlementCache) {
        self.catalog = catalog
        self.cache = cache
        // Offline first: the Keychain mirror until the store answers.
        entitlements = cache.load() ?? .none
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
    }

    /// Stops listening for transaction updates (tests create several services).
    public func stopListening() {
        updates?.cancel()
        updates = nil
    }

    public func refresh() async {
        var records: [PurchaseRecord] = []
        for await result in Transaction.currentEntitlements {
            records.append(Self.record(result))
        }
        let derived = EntitlementMapper.entitlements(from: records, catalog: catalog, now: Date())
        entitlements = derived
        cache.save(derived)
    }

    static func record(_ result: VerificationResult<Transaction>) -> PurchaseRecord {
        switch result {
        case let .verified(transaction):
            PurchaseRecord(
                productID: transaction.productID,
                transactionID: String(transaction.id),
                isVerified: true,
                isRevoked: transaction.revocationDate != nil,
                expiresAt: transaction.expirationDate
            )
        case let .unverified(transaction, _):
            PurchaseRecord(productID: transaction.productID, transactionID: String(transaction.id), isVerified: false)
        }
    }

    public func products() async throws -> [ProductInfo] {
        try await Product.products(for: catalog.productIDs).compactMap { product in
            guard let entry = catalog.product(product.id) else { return nil }
            return ProductInfo(id: product.id, displayName: product.displayName, displayPrice: product.displayPrice, kind: entry.kind)
        }
    }

    public func purchase(_ productID: String) async throws -> PurchaseOutcome {
        guard catalog.product(productID) != nil, let product = try await Product.products(for: [productID]).first else {
            throw StoreError.unknownProduct(productID)
        }
        switch try await product.purchase() {
        case let .success(verification):
            guard case let .verified(transaction) = verification else { throw StoreError.unverified }
            await transaction.finish()
            await refresh()
            return .purchased(productID: productID, transactionID: String(transaction.id))
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }
}
