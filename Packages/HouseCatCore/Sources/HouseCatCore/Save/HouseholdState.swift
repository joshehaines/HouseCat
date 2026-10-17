import Foundation

/// Content the rules need to derive state (from Content/*.json). Kept separate
/// from Tuning because it is data Josh reviews, not constants.
public struct RulesContext: Sendable {
    public var gifts: [GiftDefinition]
    public var dailyObjectives: [ObjectiveDefinition]
    public var weeklyObjectives: [ObjectiveDefinition]
    public var achievements: [ObjectiveDefinition]
    public var seasons: [SeasonDefinition]

    public init(
        gifts: [GiftDefinition] = [],
        dailyObjectives: [ObjectiveDefinition] = [],
        weeklyObjectives: [ObjectiveDefinition] = [],
        achievements: [ObjectiveDefinition] = [],
        seasons: [SeasonDefinition] = []
    ) {
        self.gifts = gifts
        self.dailyObjectives = dailyObjectives
        self.weeklyObjectives = weeklyObjectives
        self.achievements = achievements
        self.seasons = seasons
    }

    public static let empty = RulesContext()

    public func season(on day: GameDay) -> SeasonDefinition? {
        seasons.first { $0.contains(day) }
    }

    public func season(id: String) -> SeasonDefinition? {
        seasons.first { $0.id == id }
    }
}

public struct CatState: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var personality: Personality
    public var adoptedOn: GameDay
    public var isKitten: Bool
    /// Days this cat was fed: trust.
    public var careDays = 0
    public var lastFedDay: GameDay?
    public var outfitID: String?

    public var trust: TrustTier {
        .forCareDays(careDays)
    }

    /// "Together 43 days": streak days since adoption; only ever rises.
    public func togetherDays(on day: GameDay) -> Int {
        max(0, adoptedOn.distance(to: day))
    }

    /// The cat's own age: its age at adoption plus the time together.
    public func ageDays(on day: GameDay) -> Int {
        (isKitten ? Tuning.Cat.kittenStartAgeDays : Tuning.Cat.adultDefaultAgeDays) + togetherDays(on: day)
    }

    /// A kitten grows up on day 21.
    public func isKittenStage(on day: GameDay) -> Bool {
        isKitten && togetherDays(on: day) < Tuning.Cat.kittenGrowsUpAtDay
    }
}

public struct PlacedItem: Codable, Equatable, Sendable {
    public var placementID: UUID
    public var itemID: String
    public var room: RoomID
    public var x: Int
    public var y: Int
    public var facing: GameEvent.Facing
}

/// What happened on the open game day. Reset when the day closes.
public struct DayTally: Codable, Equatable, Sendable {
    public var day: GameDay
    public var visited = false
    public var arrived = false
    /// The previous day had no visit and was not paused: sulk, and no gift today.
    public var missedYesterday = false
    public var fedCats: Set<String> = []
    public var firstVisitAt: Date?
    public var pets = 0
    public var plays = 0
    public var napped = false
    public var furnitureXP = 0
    public var newFurnitureXP = 0
    public var placedFurniture = false
    public var healthGoals: Set<GameEvent.HealthGoal> = []
    public var passPoints = 0
    public var clubDay = false
    public var sundayCard = false
    public var satForFriend = false
    /// Beans earned today before the Cat Club bonus.
    public var baseBeans = 0
    public var metrics: [ObjectiveMetric: Int] = [:]
    public var objectives: [String] = []
    public var completed: Set<String> = []

    public init(day: GameDay) {
        self.day = day
    }

    /// The Cat Club bonus on today's Beans.
    public var clubBonus: Int {
        clubDay ? baseBeans * Tuning.Beans.clubBonusPercent / 100 : 0
    }
}

public struct WeekTally: Codable, Equatable, Sendable {
    public var weekStart: GameDay
    public var metrics: [ObjectiveMetric: Int] = [:]
    public var objectives: [String] = []
    public var completed: Set<String> = []
}

/// Lifetime counters for the profile and achievements, all derived from events.
public struct Lifetime: Codable, Equatable, Sendable {
    public var feeds = 0
    public var pets = 0
    public var gifts = 0
    public var legendaryGifts = 0
    public var naps = 0
    public var visits = 0
    public var minigameWins = 0
    public var threeStarGames = 0
    public var seasonChanges = 0
    public var homeMoves = 0
    public var passTiersClaimed = 0
    public var pawPrintsSent = 0
    public var groupsJoined = 0
    public var sittingDays = 0
    public var giftsSent = 0
    public var outfitsWorn = 0
    public var surfacesChanged = 0
    public var catsAdopted = 0
    public var sundayCards = 0
    public var roomsVisited: Set<RoomID> = []
    public var usedItems: Set<String> = []
}

/// Everything derived from the event log. Built only by folding events
/// (`apply`) and closing days (`advance`); see Reducer.swift.
public struct HouseholdState: Codable, Equatable, Sendable {
    public internal(set) var seed: UInt64 = 0
    public internal(set) var clock = DayClock()
    public internal(set) var createdOn: GameDay?
    /// The open game day; every earlier day is closed.
    public internal(set) var today: DayTally?
    public internal(set) var week: WeekTally?
    public internal(set) var lastEventAt: Date?

    public internal(set) var xp = 0
    public internal(set) var beansGranted = 0
    /// Beans earned on closed days, Cat Club bonus included.
    public internal(set) var beansEarnedClosed = 0
    public internal(set) var beansSpent = 0

    public internal(set) var cats: [CatState] = []
    public internal(set) var streak = StreakState()
    public internal(set) var pause = PauseState()
    /// Arrivals since the last missed day, capped (sulky → thawing → fine).
    public internal(set) var warmUpArrivals = Tuning.Streak.warmUpArrivals

    public internal(set) var openedRooms: Set<RoomID> = [.living]
    public internal(set) var owned: [String: Int] = [:]
    public internal(set) var ownedOutfits: Set<String> = []
    public internal(set) var ownedSurfaces: Set<String> = []
    public internal(set) var placed: [PlacedItem] = []
    public internal(set) var surfaces: [RoomID: String] = [:]
    public internal(set) var homeMovesUsed = 0

    public internal(set) var giftsCollected: [String: Int] = [:]
    public internal(set) var pendingGifts: [GiftDraw] = []
    public internal(set) var passes: [String: SeasonProgress] = [:]
    public internal(set) var completedAchievements: Set<String> = []
    public internal(set) var lifetime = Lifetime()

    public init() {}

    // MARK: Derived values

    public var level: Int {
        LevelCurve.level(forXP: xp)
    }

    /// Beans in hand.
    public var beans: Int {
        let todayEarned = (today?.baseBeans ?? 0) + (today?.clubBonus ?? 0)
        return beansGranted + beansEarnedClosed + todayEarned - beansSpent
    }

    public var visitedToday: Bool {
        today?.visited ?? false
    }

    public var missedYesterday: Bool {
        today?.missedYesterday ?? false
    }

    public func cat(_ id: String) -> CatState? {
        cats.first { $0.id == id }
    }

    public func isFedToday(_ catID: String) -> Bool {
        today?.fedCats.contains(catID) ?? false
    }

    /// Gifts dropped and waiting to be collected at `date`.
    public func waitingGifts(at date: Date) -> [GiftDraw] {
        pendingGifts.filter { $0.dropAt <= date }
    }

    public func placedCount(of itemID: String) -> Int {
        placed.filter { $0.itemID == itemID }.count
    }

    /// Affordances the furniture in a room offers, given each item's affordances.
    public func affordances(in room: RoomID, catalogue: [String: Set<Affordance>]) -> Set<Affordance> {
        placed.filter { $0.room == room }.reduce(into: Set<Affordance>()) { result, item in
            result.formUnion(catalogue[item.itemID] ?? [])
        }.subtracting([.none])
    }

    /// The cat's mood at `date` (the state must be resolved through that day).
    public func mood(of catID: String, at date: Date) -> Mood {
        guard let cat = cat(catID) else { return .content }
        if warmUpArrivals <= 1 {
            return .sulky
        }
        if warmUpArrivals == 2 {
            return .thawing
        }
        if !isFedToday(catID) {
            return .hungry
        }
        let time = TimeOfDay.at(localMinutes: clock.localMinutes(of: date), clock: clock)
        if time == .night {
            return .sleepy
        }
        if time == .evening, cat.personality.sliders.energy >= 0.7 {
            return .playful
        }
        return .content
    }

    /// The value of a lifetime metric on `day`.
    public func lifetimeValue(_ metric: ObjectiveMetric, on day: GameDay) -> Int {
        switch metric {
        case .totalFeeds: lifetime.feeds
        case .totalPets: lifetime.pets
        case .totalGifts: lifetime.gifts
        case .distinctGifts: giftsCollected.count
        case .legendaryGifts: lifetime.legendaryGifts
        case .itemsOwned: owned.values.reduce(0, +)
        case .roomsOpened: openedRooms.count - 1
        case .roomsVisited: lifetime.roomsVisited.count
        case .longestStreak: streak.longest
        case .level: level
        case .trustTier: cats.map(\.trust.rawValue).max() ?? 0
        case .minigameWins: lifetime.minigameWins
        case .threeStarGames: lifetime.threeStarGames
        case .naps: lifetime.naps
        case .seasonChanged: lifetime.seasonChanges
        case .homeMoved: lifetime.homeMoves
        case .passTiersClaimed: lifetime.passTiersClaimed
        case .seasonsCompleted: passes.values.filter { $0.tier >= Tuning.Pass.tiers }.count
        case .pawPrintsSent: lifetime.pawPrintsSent
        case .groupsJoined: lifetime.groupsJoined
        case .sittingDays: lifetime.sittingDays
        case .giftsSent: lifetime.giftsSent
        case .outfitsWorn: lifetime.outfitsWorn
        case .surfacesChanged: lifetime.surfacesChanged
        case .catsAdopted: lifetime.catsAdopted
        case .sundayCards: lifetime.sundayCards
        case .togetherDays: cats.map { $0.togetherDays(on: day) }.max() ?? 0
        default: 0
        }
    }
}
