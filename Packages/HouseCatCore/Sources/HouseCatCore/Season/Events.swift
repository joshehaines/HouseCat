import Foundation

/// One day's present on a gift track: Beans, a piece of furniture, or both.
public struct EventReward: Codable, Hashable, Sendable {
    public var day: Int
    public var beans: Int?
    public var item: String?

    public init(day: Int, beans: Int? = nil, item: String? = nil) {
        self.day = day
        self.beans = beans
        self.item = item
    }
}

/// A launch event as the rules see it: its real first and last day.
public struct EventDefinition: Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: EventsFile.Event.Kind
    public var startDay: GameDay
    /// Exclusive: the event's last day is the day before.
    public var endDay: GameDay
    public var sku: String?
    public var rewards: [EventReward]
    /// What it is, in a line (from events.json).
    public var blurb: String
    /// Snow falls past every window while it runs (the Christmas event, SPEC "Sky, season, weather").
    public var snow: Bool
    /// It falls on the same dates every year, so its days are shown as dates.
    public var dated: Bool
    /// The line context the day's first arrival greets it with (`event.christmas`).
    public var lines: String?

    public init(
        id: String,
        name: String,
        kind: EventsFile.Event.Kind,
        startDay: GameDay,
        endDay: GameDay,
        sku: String? = nil,
        rewards: [EventReward] = [],
        blurb: String = "",
        snow: Bool = false,
        dated: Bool = false,
        lines: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.startDay = startDay
        self.endDay = endDay
        self.sku = sku
        self.rewards = rewards
        self.blurb = blurb
        self.snow = snow
        self.dated = dated
        self.lines = lines
    }

    public func isLive(on day: GameDay) -> Bool {
        startDay <= day && day < endDay
    }

    /// The last day it runs (shown as a real date, never a countdown).
    public var lastDay: GameDay {
        endDay.advanced(by: -1)
    }

    /// The date of a track's present (`day` 1 is its first day).
    public func date(ofDay day: Int) -> GameDay {
        startDay.advanced(by: day - 1)
    }

    /// Which day of a track `day` is (1 on its first day), or nil outside it.
    public func trackDay(on day: GameDay) -> Int? {
        isLive(on: day) ? startDay.distance(to: day) + 1 : nil
    }
}

/// The launch events' rules (SPEC "Launch"; CLAUDE.md "Store and review rules": a limited offer states its
/// real end date and never returns). A track's presents can be claimed on their day or any day after, until
/// the track ends; each once.
public enum EventRules {
    public static func live(on day: GameDay, context: RulesContext) -> [EventDefinition] {
        context.events.filter { $0.isLive(on: day) }
    }

    /// The days of a track whose present is waiting.
    public static func claimable(_ event: EventDefinition, state: HouseholdState, on day: GameDay) -> [Int] {
        guard let today = event.trackDay(on: day) else { return [] }
        let claimed = state.eventClaims[event.id] ?? []
        return event.rewards.map(\.day).filter { $0 <= today && !claimed.contains($0) }
    }

    /// Whether snow falls past the windows today whatever the weather (the Christmas event).
    public static func snowing(on day: GameDay, context: RulesContext) -> Bool {
        live(on: day, context: context).contains(where: \.snow)
    }

    /// Whether a sale (the Housewarming pack) is on.
    public static func onSale(_ sku: String, on day: GameDay, context: RulesContext) -> EventDefinition? {
        context.events.first { $0.kind == .sale && $0.sku == sku && $0.isLive(on: day) }
    }
}

/// The health layer (SPEC "Health layer": HealthKit read-only, asked on day 3, each threshold pays XP and a line,
/// never a penalty): which goals a day's readings meet. The reducer pays each goal once a day.
public enum HealthRules {
    public static func goalsMet(steps: Double, sleepHours: Double, workouts: Int) -> [GameEvent.HealthGoal] {
        var met: [GameEvent.HealthGoal] = []
        if steps >= Double(Tuning.Health.stepsGoal) {
            met.append(.steps)
        }
        if sleepHours >= Tuning.Health.sleepGoalHours {
            met.append(.sleep)
        }
        if workouts > 0 {
            met.append(.workout)
        }
        return met
    }

    /// The day to ask (day 3 of looking after the cat), and only once.
    public static func shouldAsk(_ state: HouseholdState, asked: Bool) -> Bool {
        !asked && (state.cats.first?.careDays ?? 0) >= Tuning.Health.askOnCareDay
    }

    /// The cat's line for a goal met (lines.json).
    public static func line(_ goal: GameEvent.HealthGoal) -> String {
        "health.\(goal.rawValue)"
    }
}
