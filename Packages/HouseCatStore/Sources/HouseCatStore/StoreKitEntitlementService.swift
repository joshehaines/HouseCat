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
    @ObservationIgnored public var onGrant: (@MainActor (StoreGrant) -> Void)? {
        didSet { deliverUnfinished() }
    }

    public init(catalog: StoreCatalog, cache: EntitlementCache) {
        self.catalog = catalog
        self.cache = cache
        // Offline first: the Keychain mirror until the store answers.
        entitlements = cache.load() ?? .none
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await self?.deliver(transaction)
                }
                await self?.refresh()
            }
        }
    }

    /// Hands over what a verified transaction gives, then finishes it (a pack is finished only once its Beans
    /// are in the save, so a crash in between delivers it again next launch).
    private func deliver(_ transaction: Transaction) async {
        if let product = catalog.product(transaction.productID), product.beans != nil || product.kind == .nonConsumable,
           transaction.revocationDate == nil, let onGrant
        {
            onGrant(StoreGrant(productID: transaction.productID, transactionID: String(transaction.id)))
        } else if onGrant == nil, catalog.product(transaction.productID)?.kind == .consumable {
            return // nobody to give the Beans to yet: left unfinished for deliverUnfinished
        }
        await transaction.finish()
    }

    /// Bean packs bought while the app was closed, or not yet handed over.
    private func deliverUnfinished() {
        guard onGrant != nil else { return }
        Task {
            for await result in Transaction.unfinished {
                if case let .verified(transaction) = result {
                    await deliver(transaction)
                }
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
        // Room looks and the starter: their pieces and Beans reach the save on any device (the save dedupes).
        for record in records where record.isVerified && !record.isRevoked {
            if let product = catalog.product(record.productID), product.kind == .nonConsumable {
                onGrant?(StoreGrant(productID: record.productID, transactionID: record.transactionID))
            }
        }
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
            return ProductInfo(
                id: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                kind: entry.kind,
                price: product.price,
                currencyCode: product.priceFormatStyle.currencyCode
            )
        }
    }

    public func purchase(_ productID: String) async throws -> PurchaseOutcome {
        guard catalog.product(productID) != nil, let product = try await Product.products(for: [productID]).first else {
            throw StoreError.unknownProduct(productID)
        }
        switch try await product.purchase() {
        case let .success(verification):
            guard case let .verified(transaction) = verification else { throw StoreError.unverified }
            await deliver(transaction)
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
