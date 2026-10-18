import Foundation

/// What the player owns through purchases. Derived on launch from verified
/// transactions only, held in memory, mirrored to the Keychain for offline
/// use, and never written to the synced save (a share participant could
/// otherwise mint items). Revoked or refunded transactions drop out on the
/// next refresh.
public struct Entitlements: Codable, Equatable, Sendable {
    public var clubSubscription = false
    /// The once-only starter offer was bought.
    public var starter = false
    /// Room looks bought (their pieces are granted into the save once per transaction; this says which the
    /// player has, for the shop's Owned).
    public var bundles: Set<String> = []

    public init() {}

    public static let none = Entitlements()

    public var hasClub: Bool {
        clubSubscription
    }

    /// Cat Club includes every season's paid track.
    public func ownsPaidTrack(season _: String) -> Bool {
        hasClub
    }
}

/// A transaction as the store reported it, before any trust is given.
public struct PurchaseRecord: Equatable, Sendable {
    public var productID: String
    public var transactionID: String
    /// StoreKit's `.verified`, or RevenueCat's verification not `.failed`.
    public var isVerified: Bool
    public var isRevoked: Bool
    public var expiresAt: Date?

    public init(productID: String, transactionID: String, isVerified: Bool, isRevoked: Bool = false, expiresAt: Date? = nil) {
        self.productID = productID
        self.transactionID = transactionID
        self.isVerified = isVerified
        self.isRevoked = isRevoked
        self.expiresAt = expiresAt
    }
}

public enum EntitlementMapper {
    /// Entitlements from the current transactions: unverified, revoked and
    /// expired ones count for nothing.
    public static func entitlements(from records: [PurchaseRecord], catalog: StoreCatalog, now: Date) -> Entitlements {
        var result = Entitlements()
        for record in records where record.isVerified && !record.isRevoked {
            guard let product = catalog.product(record.productID) else { continue }
            if product.kind == .autoRenewable, let expiresAt = record.expiresAt, expiresAt <= now {
                continue
            }
            switch product.unlock {
            case .club: result.clubSubscription = true
            case .starter: result.starter = true
            case let .bundle(id): result.bundles.insert(id)
            case .beans: break
            }
        }
        return result
    }
}
