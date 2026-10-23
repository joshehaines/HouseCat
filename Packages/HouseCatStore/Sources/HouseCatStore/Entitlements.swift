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
    /// Seasons whose premium pass was bought (each season's own product, `housecat.pass.<season>`), by the season's
    /// pass id: it opens every run of that season.
    public var passes: Set<String> = []

    public init() {}

    public static let none = Entitlements()

    public var hasClub: Bool {
        clubSubscription
    }

    /// The premium track of a season (by its pass id): its own pass only (Josh, 23 Oct: not in Cat Club).
    public func ownsPaidTrack(season passID: String) -> Bool {
        passes.contains(passID)
    }

    private enum CodingKeys: String, CodingKey {
        case clubSubscription, starter, bundles, passes
    }

    /// A Keychain mirror written before passes were sold decodes with none.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clubSubscription = try container.decodeIfPresent(Bool.self, forKey: .clubSubscription) ?? false
        starter = try container.decodeIfPresent(Bool.self, forKey: .starter) ?? false
        bundles = try container.decodeIfPresent(Set<String>.self, forKey: .bundles) ?? []
        passes = try container.decodeIfPresent(Set<String>.self, forKey: .passes) ?? []
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
            case let .pass(season): result.passes.insert(season)
            case .beans: break
            }
        }
        return result
    }
}
