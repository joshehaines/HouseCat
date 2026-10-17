import Foundation

/// What the player owns through purchases. Derived on launch from verified
/// transactions only, held in memory, mirrored to the Keychain for offline
/// use, and never written to the synced save (a share participant could
/// otherwise mint items). Revoked or refunded transactions drop out on the
/// next refresh.
public struct Entitlements: Codable, Equatable, Sendable {
    public var clubSubscription = false
    public var lifetime = false
    public var founders = false
    public var passes: Set<String> = []
    public var outfits: Set<String> = []
    public var sets: Set<String> = []
    public var catSlots: Set<Int> = []
    public var starter = false
    public var housewarmingPack = false

    public init() {}

    public static let none = Entitlements()

    /// Cat Club benefits: an active subscription, Forever Home (lifetime) or the founders' pack.
    public var hasClub: Bool {
        clubSubscription || lifetime || founders
    }

    /// Extra cats beyond the first: adopted slots plus the one inside Cat Club.
    public var extraCatSlots: Int {
        catSlots.count + (hasClub ? 1 : 0)
    }

    /// Cat Club includes every season's paid track.
    public func ownsPaidTrack(season: String) -> Bool {
        hasClub || passes.contains(season)
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
            case let .outfit(id): result.outfits.insert(id)
            case let .set(id): result.sets.insert(id)
            case let .bundle(set, outfit, _):
                result.sets.insert(set)
                result.outfits.insert(outfit)
            case let .catSlot(slot): result.catSlots.insert(slot)
            case .starter: result.starter = true
            case .housewarmingPack: result.housewarmingPack = true
            case .club: result.clubSubscription = true
            case .lifetime: result.lifetime = true
            case .founders: result.founders = true
            case let .seasonPass(season): result.passes.insert(season)
            case .gift: break
            }
        }
        return result
    }
}
