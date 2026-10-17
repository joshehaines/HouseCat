/// Objectives (CONTENT.md §5): three daily drawn from a pool of 20, three weekly
/// from a pool of 12, and one-off achievements. They pay Beans and pass points,
/// never anything else.
public enum ObjectiveMetric: String, CaseIterable, Codable, Sendable {
    // Counted within the day or the week.
    case pet
    case feed
    case feedBefore9 = "feed_before_9"
    case playMinigame = "play_minigame"
    case winMinigame = "win_minigame"
    case threeStarMinigame = "three_star_minigame"
    case placeItem = "place_item"
    case widgetVisit = "widget_visit"
    case tapWindow = "tap_window"
    case nap
    case macVisit = "mac_visit"
    case watchVisit = "watch_visit"
    case visitDay = "visit_day"
    case findGift = "find_gift"
    case openRoom = "open_room"
    case sendPawPrint = "send_paw_print"
    case changeSurface = "change_surface"
    case buyItemBeans = "buy_item_beans"
    case wearOutfit = "wear_outfit"

    // Lifetime totals, for achievements.
    case totalFeeds = "total_feeds"
    case totalPets = "total_pets"
    case totalGifts = "total_gifts"
    case distinctGifts = "distinct_gifts"
    case legendaryGifts = "legendary_gifts"
    case itemsOwned = "items_owned"
    case roomsOpened = "rooms_opened"
    case roomsVisited = "rooms_visited"
    case longestStreak = "longest_streak"
    case level
    case trustTier = "trust_tier"
    case minigameWins = "minigame_wins"
    case threeStarGames = "three_star_games"
    case naps
    case seasonChanged = "season_changed"
    case homeMoved = "home_moved"
    case passTiersClaimed = "pass_tiers_claimed"
    case seasonsCompleted = "seasons_completed"
    case pawPrintsSent = "paw_prints_sent"
    case groupsJoined = "groups_joined"
    case sittingDays = "sitting_days"
    case giftsSent = "gifts_sent"
    case outfitsWorn = "outfits_worn"
    case surfacesChanged = "surfaces_changed"
    case catsAdopted = "cats_adopted"
    case sundayCards = "sunday_cards"
    case togetherDays = "together_days"

    /// Whether the metric is a lifetime total (achievements) rather than a count within a period.
    public var isLifetime: Bool {
        let periodMetrics: Set<ObjectiveMetric> = [
            .pet, .feed, .feedBefore9, .playMinigame, .winMinigame, .threeStarMinigame, .placeItem, .widgetVisit,
            .tapWindow, .nap, .macVisit, .watchVisit, .visitDay, .findGift, .openRoom, .sendPawPrint,
            .changeSurface, .buyItemBeans, .wearOutfit,
        ]
        return !periodMetrics.contains(self)
    }
}

/// An objective from Content/objectives.json.
public struct ObjectiveDefinition: Codable, Hashable, Sendable {
    public var id: String
    public var metric: ObjectiveMetric
    public var target: Int
    public var beans: Int
    public var passPoints: Int

    public init(id: String, metric: ObjectiveMetric, target: Int, beans: Int, passPoints: Int) {
        self.id = id
        self.metric = metric
        self.target = target
        self.beans = beans
        self.passPoints = passPoints
    }
}

public enum ObjectiveRules {
    /// Today's three daily objectives, the same on every device.
    public static func daily(from pool: [ObjectiveDefinition], household seed: UInt64, day: GameDay) -> [ObjectiveDefinition] {
        draw(Tuning.Objectives.dailyCount, from: pool, rng: DaySeed(household: seed, day: day, purpose: "objectives.daily"))
    }

    /// This week's three weekly objectives (weeks start on Monday at the wake time).
    public static func weekly(from pool: [ObjectiveDefinition], household seed: UInt64, day: GameDay) -> [ObjectiveDefinition] {
        draw(Tuning.Objectives.weeklyCount, from: pool, rng: DaySeed(household: seed, day: day.weekStart, purpose: "objectives.weekly"))
    }

    private static func draw(_ count: Int, from pool: [ObjectiveDefinition], rng: DaySeed) -> [ObjectiveDefinition] {
        var rng = rng
        return Array(rng.shuffled(pool.sorted { $0.id < $1.id }).prefix(count))
    }
}
