/// What an outfit is to a household in the outfit catalogue (Josh, 19 Oct: see the cat in it before buying): on the
/// cat, in its wardrobe, for sale for Beans, or what it comes from. Only paid outfits are sold, a seasonal one in its
/// months (`ShopRules`); the rest are earned in play or are season pass rewards.
public enum OutfitAvailability: Equatable, Sendable {
    case wearing
    case owned
    case forSale(beans: Int)
    /// Sold in its months only (the pumpkin hat in October).
    case outOfSeason(months: [Int])
    /// Earned in play (outfits.json `earnedBy`: "streak_30", "referral", "launch_event", "level_<n>").
    case earned(source: String)
    /// A season pass reward, on the free track or Cat Club's paid one.
    case pass(club: Bool)

    public static func of(_ outfit: OutfitsFile.Outfit, owned: Set<String>, worn: String?, on day: GameDay) -> OutfitAvailability {
        if outfit.id == worn {
            return .wearing
        }
        if owned.contains(outfit.id) {
            return .owned
        }
        switch outfit.pool {
        case .paid:
            return ShopRules
                .isOnSale(months: outfit.months, on: day) ? .forSale(beans: Tuning.Beans.outfit) : .outOfSeason(months: outfit.months)
        case .passFree: return .pass(club: false)
        case .passPaid: return .pass(club: true)
        case .earned, .founders: return .earned(source: outfit.earnedBy ?? outfit.pool.rawValue)
        }
    }

    /// The catalogue's order: on the cat, owned, for sale, then the rest.
    public var rank: Int {
        switch self {
        case .wearing: 0
        case .owned: 1
        case .forSale: 2
        case .outOfSeason: 3
        case .pass: 4
        case .earned: 5
        }
    }
}
