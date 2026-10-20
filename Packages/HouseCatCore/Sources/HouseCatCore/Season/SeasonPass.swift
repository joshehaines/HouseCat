/// The season pass, the game's main progression (Josh, 19 Oct 2026: "the 'battle pass' like system with levels and
/// paid/free journies along it"): a season always running (`SeasonSchedule`), thirty tiers climbed with the XP the
/// player earns while it runs plus the goals' bonus pass XP, a free track that ends at tier twenty and a premium
/// track on every tier to thirty. Premium is its own purchase each season and comes with Cat Club; buying it
/// mid-season opens every tier already reached; anything reached can be claimed until the season's real last day;
/// every reward is fixed and shown from the first day; what is claimed is kept forever. A tier on a track is one box,
/// which may hold more than one reward (Josh, 20 Oct: "the boxes need to be better and I think we need more content in
/// them ... less beans and more items"): an item with bonus Beans, or two items, all claimed together.
public enum PassTrack: String, CaseIterable, Codable, Sendable {
    case free
    case paid
}

/// How special a reward is, shown on its box with its word and diamonds (never by colour alone): the gift book's four
/// words.
public enum PassRarity: String, CaseIterable, Codable, Comparable, Sendable {
    case common
    case uncommon
    case rare
    case legendary

    /// The diamonds beside the word: one to four.
    public var rank: Int {
        Self.allCases.firstIndex(of: self).map { $0 + 1 } ?? 1
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct PassReward: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case beans
        case item
        case outfit
        case surface
    }

    public var tier: Int
    public var kind: Kind
    public var id: String?
    public var amount: Int?
    /// Set in content (seasons.json); a reward without one takes its kind's (`grade`).
    public var rarity: PassRarity?

    public init(tier: Int, kind: Kind, id: String? = nil, amount: Int? = nil, rarity: PassRarity? = nil) {
        self.tier = tier
        self.kind = kind
        self.id = id
        self.amount = amount
        self.rarity = rarity
    }

    /// The rarity shown: content's, else Beans are common, a piece uncommon, a wallpaper or floor rare and an outfit
    /// legendary.
    public var grade: PassRarity {
        if let rarity {
            return rarity
        }
        switch kind {
        case .beans: return .common
        case .item: return .uncommon
        case .surface: return .rare
        case .outfit: return .legendary
        }
    }
}

/// A season with its real start and end: one from Content/seasons.json, or a run of one again in a later slot
/// (`SeasonSchedule`).
public struct SeasonDefinition: Codable, Hashable, Sendable {
    /// Unique to this run of the season: what the save's pass events name.
    public var id: String
    public var name: String
    /// The season whose premium pass this run sells: its own id, or the id of the season it runs again. A pass
    /// bought once opens every run of that season.
    public var passID: String
    /// The premium pass's product (`housecat.pass.<passID>`).
    public var sku: String
    public var startDay: GameDay
    /// Exclusive: the season's last day is the day before.
    public var endDay: GameDay
    public var freeTrack: [PassReward]
    public var paidTrack: [PassReward]

    public init(
        id: String,
        name: String? = nil,
        passID: String? = nil,
        sku: String? = nil,
        startDay: GameDay,
        endDay: GameDay,
        freeTrack: [PassReward] = [],
        paidTrack: [PassReward] = []
    ) {
        self.id = id
        self.name = name ?? id
        self.passID = passID ?? id
        self.sku = sku ?? "housecat.pass.\(passID ?? id)"
        self.startDay = startDay
        self.endDay = endDay
        self.freeTrack = freeTrack
        self.paidTrack = paidTrack
    }

    public func contains(_ day: GameDay) -> Bool {
        day >= startDay && day < endDay
    }

    /// The season's last day, the one the pass shows ("Ends Tue 1 December").
    public var lastDay: GameDay {
        endDay.advanced(by: -1)
    }

    /// A run of this season again rather than its first.
    public var isRerun: Bool {
        passID != id
    }

    public func track(_ track: PassTrack) -> [PassReward] {
        track == .free ? freeTrack : paidTrack
    }

    /// Everything in a tier's box on a track, its main reward first (as content lists them).
    public func rewards(track: PassTrack, tier: Int) -> [PassReward] {
        self.track(track).filter { $0.tier == tier }
    }

    /// A box's main reward: the one its picture shows.
    public func reward(track: PassTrack, tier: Int) -> PassReward? {
        self.track(track).first { $0.tier == tier }
    }

    /// The tiers with a box on a track, in order.
    public func tiers(_ track: PassTrack) -> [Int] {
        Array(Set(self.track(track).map(\.tier))).sorted()
    }

    /// Days left including today, for "the last week shows the days left".
    public func daysLeft(on day: GameDay) -> Int {
        max(0, day.distance(to: endDay))
    }
}

/// A player's progress in one season.
public struct SeasonProgress: Codable, Equatable, Sendable {
    /// Pass XP earned in the season.
    public var points = 0
    /// The premium pass is recorded in the save (bought, or a run of a season whose pass was bought).
    public var purchased = false
    public var claimedFree: Set<Int> = []
    public var claimedPaid: Set<Int> = []

    public init() {}

    public var tier: Int {
        PassRules.tier(forPoints: points)
    }

    public func claimed(_ track: PassTrack) -> Set<Int> {
        track == .free ? claimedFree : claimedPaid
    }
}

/// What a track holds, in a line ("20 pieces, a wallpaper and a floor, 4 outfits, 600 Beans").
public struct PassContents: Equatable, Sendable {
    public var pieces = 0
    public var wallpapers = 0
    public var floors = 0
    public var outfits = 0
    public var beans = 0
    /// Every reward, Beans included.
    public var rewards = 0
    /// Tiers with a box.
    public var boxes = 0
    /// Boxes that are Beans and nothing else.
    public var beanBoxes = 0

    /// Pieces, wallpapers, floors and outfits: everything but Beans.
    public var items: Int {
        pieces + wallpapers + floors + outfits
    }
}

public enum PassRules {
    public static func tier(forPoints points: Int) -> Int {
        min(Tuning.Pass.tiers, max(0, points) / Tuning.Pass.pointsPerTier)
    }

    /// Pass XP into the tier being climbed, and what the next tier needs (both 0 at the top).
    public static func toNextTier(_ progress: SeasonProgress) -> (into: Int, needed: Int) {
        guard progress.tier < Tuning.Pass.tiers else { return (0, 0) }
        return (progress.points - progress.tier * Tuning.Pass.pointsPerTier, Tuning.Pass.pointsPerTier)
    }

    /// Whether a tier can be claimed on `day`: reached, in the season, not yet claimed, a reward there, and for the
    /// premium track the pass owned.
    public static func canClaim(
        track: PassTrack,
        tier: Int,
        progress: SeasonProgress,
        season: SeasonDefinition,
        day: GameDay,
        ownsPaidTrack: Bool
    ) -> Bool {
        guard season.contains(day), tier >= 1, tier <= progress.tier, !season.rewards(track: track, tier: tier).isEmpty
        else { return false }
        switch track {
        case .free:
            return !progress.claimedFree.contains(tier)
        case .paid:
            return ownsPaidTrack && !progress.claimedPaid.contains(tier)
        }
    }

    /// Tiers ready to claim on a track.
    public static func claimable(
        track: PassTrack,
        progress: SeasonProgress,
        season: SeasonDefinition,
        day: GameDay,
        ownsPaidTrack: Bool
    ) -> [Int] {
        guard progress.tier >= 1 else { return [] }
        return (1 ... progress.tier).filter {
            canClaim(track: track, tier: $0, progress: progress, season: season, day: day, ownsPaidTrack: ownsPaidTrack)
        }
    }

    /// Premium rewards on tiers already reached and not claimed: what buying the pass opens at once.
    public static func openAtOnce(progress: SeasonProgress, season: SeasonDefinition) -> [Int] {
        season.tiers(.paid).filter { $0 <= progress.tier && !progress.claimedPaid.contains($0) }
    }

    /// The next reward up the road, for the room's badge and the pass's header: the first tier above the one reached
    /// with a reward, its premium reward for a player with the pass, else its free one (the premium one once the
    /// free track has ended, shown locked).
    public static func next(progress: SeasonProgress, season: SeasonDefinition, ownsPaidTrack: Bool) -> (track: PassTrack, reward: PassReward)? {
        guard progress.tier < Tuning.Pass.tiers else { return nil }
        for tier in progress.tier + 1 ... Tuning.Pass.tiers {
            let free = season.reward(track: .free, tier: tier)
            let paid = season.reward(track: .paid, tier: tier)
            if ownsPaidTrack, let paid {
                return (.paid, paid)
            }
            if let free {
                return (.free, free)
            }
            if let paid {
                return (.paid, paid)
            }
        }
        return nil
    }

    /// What a track holds, counted (the premium panel's lines; the shop's tile).
    public static func contents(of track: [PassReward]) -> PassContents {
        var contents = PassContents()
        let boxes = Dictionary(grouping: track, by: \.tier)
        contents.boxes = boxes.count
        contents.beanBoxes = boxes.values.count { box in box.allSatisfy { $0.kind == .beans } }
        for reward in track {
            contents.rewards += 1
            switch reward.kind {
            case .beans: contents.beans += reward.amount ?? 0
            case .item: contents.pieces += 1
            case .outfit: contents.outfits += 1
            case .surface:
                // Surface ids name their kind ("wall_…", "floor_…").
                if reward.id?.hasPrefix("floor") == true {
                    contents.floors += 1
                } else {
                    contents.wallpapers += 1
                }
            }
        }
        return contents
    }
}
