import Foundation

public enum GiftRarity: String, CaseIterable, Codable, Comparable, Sendable {
    case common
    case uncommon
    case rare
    case legendary

    var index: Int {
        Self.allCases.firstIndex(of: self)!
    }

    public var collectBeans: Int {
        Tuning.Gifts.collectBeans[index]
    }

    public var sellBackBeans: Int {
        Tuning.Gifts.sellBackBeans[index]
    }

    public static func < (lhs: GiftRarity, rhs: GiftRarity) -> Bool {
        lhs.index < rhs.index
    }
}

/// A gift the cat can bring (from Content/gifts.json).
public struct GiftDefinition: Codable, Hashable, Sendable {
    public var id: String
    public var rarity: GiftRarity
    /// Seasonal gifts appear only in these months (1–12); empty = all year.
    public var months: [Int]

    public init(id: String, rarity: GiftRarity, months: [Int] = []) {
        self.id = id
        self.rarity = rarity
        self.months = months
    }
}

/// A gift the cat has decided to bring: drawn when the cat is fed.
public struct GiftDraw: Codable, Hashable, Sendable {
    public var catID: String
    public var fedDay: GameDay
    public var rarity: GiftRarity
    public var giftID: String
    public var dropAt: Date
}

/// The daily gift (SPEC "Gifts"): one a day when fed, earned only, never sold.
/// Paid products never touch these odds; nothing here takes an entitlement.
public enum GiftRules {
    /// Draw weights in percent for a trust tier; always sum to 100.
    public static func weights(for tier: TrustTier) -> [GiftRarity: Int] {
        var weights: [GiftRarity: Int] = [:]
        for rarity in GiftRarity.allCases {
            let shift = Tuning.Gifts.perTierShift[rarity.index] * tier.rawValue
            weights[rarity] = Tuning.Gifts.baseWeights[rarity.index] + shift
        }
        return weights
    }

    /// Decides the gift for a cat fed at `fedAt` on `fedDay`.
    public static func draw(
        household seed: UInt64,
        catID: String,
        fedDay: GameDay,
        fedAt: Date,
        tier: TrustTier,
        pool: [GiftDefinition],
        clock: DayClock
    ) -> GiftDraw {
        var rng = DaySeed(household: seed, day: fedDay, purpose: "gift", salt: catID)
        let weights = weights(for: tier)
        let rarityIndex = rng.pick(weights: GiftRarity.allCases.map { weights[$0] ?? 0 }) ?? 0
        let rarity = GiftRarity.allCases[rarityIndex]

        // Choose from this rarity's gifts in season; fall back to rarer-to-commoner tiers if empty.
        let month = fedDay.month
        let inSeason = pool.filter { $0.months.isEmpty || $0.months.contains(month) }
        var giftID = "placeholder.\(rarity.rawValue)"
        var chosenRarity = rarity
        for candidate in GiftRarity.allCases.reversed() where candidate <= rarity {
            let options = inSeason.filter { $0.rarity == candidate }.sorted { $0.id < $1.id }
            if !options.isEmpty {
                giftID = options[rng.below(options.count)].id
                chosenRarity = candidate
                break
            }
        }

        return GiftDraw(
            catID: catID,
            fedDay: fedDay,
            rarity: chosenRarity,
            giftID: giftID,
            dropAt: dropTime(fedAt: fedAt, fedDay: fedDay, clock: clock, rng: &rng)
        )
    }

    /// A random moment between an hour after feeding and 22:00; next morning if fed late.
    static func dropTime(fedAt: Date, fedDay: GameDay, clock: DayClock, rng: inout DaySeed) -> Date {
        let earliest = fedAt.addingTimeInterval(Tuning.Gifts.earliestAfterFeed)
        let latest = clock.date(on: fedDay, atLocalMinutes: Tuning.Gifts.latestDropMinutes)
        let span = Int(latest.timeIntervalSince(earliest) / 60)
        if span > 0 {
            return earliest.addingTimeInterval(Double(rng.below(span)) * 60)
        }
        let morning = clock.start(of: fedDay.advanced(by: 1))
        return morning.addingTimeInterval(Double(rng.below(Tuning.Gifts.morningDropWindowMinutes)) * 60)
    }
}
