import Foundation

// MARK: bundles.json

/// Room looks sold for money (Content/bundles.json): every piece, the wallpaper and the floor of one look, for
/// one room, added in one tap. Granted into the save once per purchase (`bundleGranted`, keyed by transaction).
public struct BundlesFile: Codable, Sendable {
    public struct Bundle: Codable, Sendable, Identifiable, Hashable {
        public var id: String
        public var name: String
        public var room: RoomID
        public var sku: String
        public var price: String
        public var blurb: String
        public var items: [String]
        public var wallpaper: String?
        public var floor: String?
        /// Sold only during its launch sale (events.json), then never again.
        public var limited: Bool?

        public var surfaces: [String] {
            [wallpaper, floor].compactMap(\.self)
        }
    }

    public var version: Int
    public var bundles: [Bundle]
}

// MARK: levels.json

/// What each level gives (Content/levels.json): Beans, sometimes a piece of furniture, and a title.
public struct LevelsFile: Codable, Sendable {
    public struct Level: Codable, Sendable, Hashable {
        public var level: Int
        public var title: String
        public var beans: Int
        public var item: String?
    }

    public struct Beyond: Codable, Sendable, Hashable {
        public var title: String
        public var beans: Int
    }

    public var version: Int
    public var levels: [Level]
    public var beyond: Beyond

    /// The reward for reaching a level (past the table, the `beyond` one).
    public func reward(for level: Int) -> Level {
        levels.first { $0.level == level } ?? Level(level: level, title: beyond.title, beans: beyond.beans, item: nil)
    }
}

/// One currency (Josh, 18 Oct: Beans bought like gems in a builder game, earned too): what the decorate tray and
/// the shop's outfits charge in Beans, and how short the player is.
public enum BeanPrices {
    /// A piece from a room look, bought alone: by its size on the floor (wall pieces are small).
    public static func piece(_ item: CatalogueFile.Item) -> Int {
        if let beans = item.beans {
            return beans
        }
        if item.layer == .wall {
            return Tuning.Beans.paidPieceSmall
        }
        switch item.footprint.w * item.footprint.d {
        case ...1: return Tuning.Beans.paidPieceSmall
        case 2: return Tuning.Beans.paidPieceMedium
        default: return Tuning.Beans.paidPieceLarge
        }
    }

    /// Beans still needed for a price (0 when the balance covers it).
    public static func shortfall(price: Int, balance: Int) -> Int {
        max(0, price - balance)
    }
}

/// A level's place on the roadmap (Josh, 18 Oct: show what each level opens, so the gate is a goal).
public struct RoadmapStop: Equatable, Sendable, Identifiable {
    public var level: Int
    public var title: String
    public var beans: Int
    /// A piece given on reaching it.
    public var gift: String?
    /// Rooms that can be opened from this level (they still cost Beans).
    public var rooms: [RoomID]
    /// Bean-shop pieces that go on sale at this level.
    public var pieces: [String]
    /// XP needed to reach it.
    public var xp: Int

    public var id: Int {
        level
    }
}

public enum LevelRoadmap {
    /// The levels from `from` (exclusive) to `to` (inclusive), each with everything it brings.
    public static func stops(after from: Int, through to: Int, levels: LevelsFile, catalogue: CatalogueFile) -> [RoadmapStop] {
        guard to > from else { return [] }
        return (from + 1 ... to).map { level in
            let reward = levels.reward(for: level)
            return RoadmapStop(
                level: level,
                title: reward.title,
                beans: reward.beans,
                gift: reward.item,
                rooms: RoomID.allCases.filter { $0.requiredLevel == level },
                pieces: catalogue.items.filter { $0.pool == .beans && $0.level == level }.map(\.id),
                xp: LevelCurve.threshold(for: level)
            )
        }
    }

    /// The next level that opens a room, if any: the goal the roadmap points at.
    public static func nextRoomLevel(after level: Int) -> (level: Int, room: RoomID)? {
        RoomID.allCases.filter { $0.requiredLevel > level }.min { $0.requiredLevel < $1.requiredLevel }.map { ($0.requiredLevel, $0) }
    }
}

/// Mending a broken streak (Josh, 18 Oct: gentle streaks, repair earned, never bought): within a few days of
/// losing it, a day with a visit, a feed and a game puts the old run back.
public enum StreakRepair {
    public static func canRepair(_ state: HouseholdState, on day: GameDay) -> Bool {
        guard let broken = state.streak.brokenOn, state.streak.brokenLength > 0,
              broken.distance(to: day) <= Tuning.Streak.repairWindowDays, let tally = state.today, tally.day == day
        else { return false }
        return tally.visited && tally.plays > 0 && state.cats.first.map { state.isFedToday($0.id) } == true
    }

    /// What is left to do today to mend it (the card lists these).
    public static func remaining(_ state: HouseholdState) -> [String] {
        guard let tally = state.today else { return [] }
        var left: [String] = []
        if state.cats.first.map({ state.isFedToday($0.id) }) != true {
            left.append("feed")
        }
        if tally.plays == 0 {
            left.append("play")
        }
        return left
    }

    /// The last day it can be mended.
    public static func lastDay(_ state: HouseholdState) -> GameDay? {
        state.streak.brokenOn?.advanced(by: Tuning.Streak.repairWindowDays)
    }
}

/// The co-owners' shared quest (Josh, 18 Oct; Duolingo's friends quest): a week's goal both owners work on
/// together, counted from who visited on which days. Only for a household with more than one owner.
public enum CoopQuest {
    public struct Progress: Equatable, Sendable {
        public var total: Int
        public var byOwner: [String: Int]
        public var target: Int
        public var claimed: Bool

        public init(total: Int, byOwner: [String: Int], target: Int, claimed: Bool) {
            self.total = total
            self.byOwner = byOwner
            self.target = target
            self.claimed = claimed
        }

        /// Done: the total reached, and everyone pitched in.
        public var isComplete: Bool {
            total >= target && byOwner.values.allSatisfy { $0 >= Tuning.Coop.questMinimumEach }
        }
    }

    /// This week's quest, or nil when only one person looks after the cat.
    public static func progress(_ state: HouseholdState) -> Progress? {
        // Owners now: once a co-owner leaves the quest goes (their visits this week stay in the tally, unused).
        guard let week = state.week, state.owners.count >= 2 else { return nil }
        var byOwner: [String: Int] = [:]
        for owner in state.owners {
            byOwner[owner] = week.visitsByOwner[owner, default: 0]
        }
        return Progress(
            total: byOwner.values.reduce(0, +),
            byOwner: byOwner,
            target: Tuning.Coop.questVisits,
            claimed: week.questClaimed
        )
    }
}

/// A friend code (Josh, 18 Oct; Finch's friend code): six characters to read out or type instead of sending a
/// link, standing for a co-owner invite for a couple of days. Letters and digits that cannot be mistaken for
/// each other, shown in two threes ("K7P-Q3M").
public enum FriendCode {
    public static let alphabet = Array("ACDEFGHJKMNPQRTUVWXY34679")

    public static func make(using rng: inout some RandomNumberGenerator) -> String {
        String((0 ..< Tuning.Coop.friendCodeLength).map { _ in alphabet.randomElement(using: &rng)! })
    }

    /// What someone typed, as the code it stands for (case, spaces and dashes ignored), or nil when it cannot be
    /// one. The alphabet leaves out O, 0, I, L, 1, B, 8, S, 5, Z and 2.
    public static func normalised(_ typed: String) -> String? {
        let code = typed.uppercased().filter { !" -".contains($0) }
        guard code.count == Tuning.Coop.friendCodeLength, code.allSatisfy(alphabet.contains) else { return nil }
        return code
    }

    public static func display(_ code: String) -> String {
        let half = code.count / 2
        return String(code.prefix(half)) + "-" + String(code.dropFirst(half))
    }
}

/// How a household member is named on screen, from the actor key: a co-owner by the name they chose.
public enum OwnerName {
    /// `hidden`: members this phone chose not to see by name (Hide, in the Together card); they show as `otherwise`.
    public static func display(_ key: String, otherwise: String, hidden: Set<String> = []) -> String {
        if hidden.contains(key) {
            return otherwise
        }
        if key.hasPrefix("co:") {
            return String(key.dropFirst(3))
        }
        if key.hasPrefix("sitter:") {
            return String(key.dropFirst(7))
        }
        return otherwise
    }
}

public extension GameEvent.Actor {
    /// A stable name for counting (the owner, or a co-owner's or sitter's chosen name).
    var key: String {
        switch self {
        case .owner: "owner"
        case let .coOwner(name): "co:\(name)"
        case let .sitter(name): "sitter:\(name)"
        }
    }
}
