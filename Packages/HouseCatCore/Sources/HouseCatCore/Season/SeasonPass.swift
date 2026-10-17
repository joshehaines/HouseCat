/// Season pass (SPEC "Season pass"): four-week seasons, 20 tiers on a free and a
/// paid track, points from daily actions. Buying mid-season unlocks every tier
/// already earned; unclaimed tiers can be claimed until the season ends; Cat
/// Club includes the paid track; every reward is fixed and visible.
public enum PassTrack: String, CaseIterable, Codable, Sendable {
    case free
    case paid
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

    public init(tier: Int, kind: Kind, id: String? = nil, amount: Int? = nil) {
        self.tier = tier
        self.kind = kind
        self.id = id
        self.amount = amount
    }
}

/// A season from Content/seasons.json, with its real start and end.
public struct SeasonDefinition: Codable, Hashable, Sendable {
    public var id: String
    public var startDay: GameDay
    /// Exclusive: the season's last day is the day before.
    public var endDay: GameDay
    public var freeTrack: [PassReward]
    public var paidTrack: [PassReward]

    public init(id: String, startDay: GameDay, endDay: GameDay, freeTrack: [PassReward] = [], paidTrack: [PassReward] = []) {
        self.id = id
        self.startDay = startDay
        self.endDay = endDay
        self.freeTrack = freeTrack
        self.paidTrack = paidTrack
    }

    public func contains(_ day: GameDay) -> Bool {
        day >= startDay && day < endDay
    }

    public func reward(track: PassTrack, tier: Int) -> PassReward? {
        (track == .free ? freeTrack : paidTrack).first { $0.tier == tier }
    }

    /// Days left including today, for "the last week shows the days left".
    public func daysLeft(on day: GameDay) -> Int {
        max(0, day.distance(to: endDay))
    }
}

/// A player's progress in one season.
public struct SeasonProgress: Codable, Equatable, Sendable {
    public var points = 0
    /// Owned through a pass purchase recorded in the save.
    public var purchased = false
    public var claimedFree: Set<Int> = []
    public var claimedPaid: Set<Int> = []

    public init() {}

    public var tier: Int {
        PassRules.tier(forPoints: points)
    }
}

public enum PassRules {
    public static func tier(forPoints points: Int) -> Int {
        min(Tuning.Pass.tiers, points / Tuning.Pass.pointsPerTier)
    }

    /// Whether a tier can be claimed on `day`.
    public static func canClaim(
        track: PassTrack,
        tier: Int,
        progress: SeasonProgress,
        season: SeasonDefinition,
        day: GameDay,
        ownsPaidTrack: Bool
    ) -> Bool {
        guard season.contains(day), tier >= 1, tier <= progress.tier else { return false }
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
}
