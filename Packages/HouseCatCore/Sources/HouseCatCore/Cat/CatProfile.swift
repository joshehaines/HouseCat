import Foundation

/// The cat's profile (SPEC "Age and time together"): how long you have had it, its own age, its trust, the
/// badges for the long haul and the lifetime stats, all derived from the save. The together count is streak
/// days (game days at the wake time) since adoption: a missed day, a lost streak or pause never touch it.
public struct CatProfile: Equatable, Sendable {
    public enum Anniversary: Equatable, Sendable {
        /// Each month on the adoption's day of the month, in the first year.
        case monthly(months: Int)
        case hundredDays
        /// Each year on the adoption's date: the gotcha day.
        case yearly(years: Int)

        /// The line context for it (Content/lines.json).
        public var lineContext: String {
            switch self {
            case .monthly: "together.monthly"
            case .hundredDays: "together.hundred_days"
            case .yearly: "together.yearly"
            }
        }
    }

    public enum Badge: Equatable, Hashable, Sendable {
        case hundredDays
        case years(Int)
    }

    public var catID: String
    public var name: String
    public var personality: Personality
    public var look: CatLook
    public var togetherDays: Int
    public var ageDays: Int
    public var isKitten: Bool
    public var trust: TrustTier
    public var careDays: Int
    /// Care days to the next tier, nil at Soulmate.
    public var careDaysToNextTier: Int?
    public var badges: [Badge]
    public var anniversary: Anniversary?
    public var visits: Int
    public var meals: Int
    public var pets: Int
    public var giftsFound: Int
    public var roomsOpened: Int
    public var currentStreak: Int
    public var longestStreak: Int
}

public extension HouseholdState {
    /// The profile of a cat on a game day (the state resolved through that day).
    func profile(of catID: String, on day: GameDay) -> CatProfile? {
        guard let cat = cat(catID) else { return nil }
        let together = cat.togetherDays(on: day)
        let next = TrustTier(rawValue: cat.trust.rawValue + 1)
        var badges: [CatProfile.Badge] = []
        if together >= Tuning.Together.hundredDays {
            badges.append(.hundredDays)
        }
        let years = Self.wholeYears(from: cat.adoptedOn, to: day)
        if years >= 1 {
            badges += (1 ... years).map(CatProfile.Badge.years)
        }
        return CatProfile(
            catID: catID,
            name: cat.name,
            personality: cat.personality,
            look: cat.look,
            togetherDays: together,
            ageDays: cat.ageDays(on: day),
            isKitten: cat.isKittenStage(on: day),
            trust: cat.trust,
            careDays: cat.careDays,
            careDaysToNextTier: next.map { $0.careDaysRequired - cat.careDays },
            badges: badges,
            anniversary: Self.anniversary(adopted: cat.adoptedOn, on: day),
            visits: lifetime.visits,
            meals: lifetime.feeds,
            pets: lifetime.pets,
            giftsFound: lifetime.gifts,
            roomsOpened: openedRooms.count - 1,
            currentStreak: streak.current,
            longestStreak: streak.longest
        )
    }

    /// Whole years from one date to another, counted on the calendar (29 February counts on 28 February).
    static func wholeYears(from start: GameDay, to day: GameDay) -> Int {
        let a = start.date, b = day.date
        var years = b.year - a.year
        if (b.month, b.day) < (a.month, min(a.day, daysIn(month: a.month, year: b.year))) {
            years -= 1
        }
        return max(0, years)
    }

    /// The anniversary that falls on a day, if one does.
    static func anniversary(adopted: GameDay, on day: GameDay) -> CatProfile.Anniversary? {
        let together = adopted.distance(to: day)
        guard together > 0 else { return nil }
        let a = adopted.date, b = day.date
        let anniversaryDay = min(a.day, daysIn(month: b.month, year: b.year))
        if b.month == a.month, b.day == anniversaryDay, b.year > a.year {
            return .yearly(years: b.year - a.year)
        }
        if together == Tuning.Together.hundredDays {
            return .hundredDays
        }
        let months = (b.year - a.year) * 12 + b.month - a.month
        if b.day == anniversaryDay, months >= 1, months < 12 {
            return .monthly(months: months)
        }
        return nil
    }

    static func daysIn(month: Int, year: Int) -> Int {
        let next = month == 12 ? GameDay(year: year + 1, month: 1, day: 1) : GameDay(year: year, month: month + 1, day: 1)
        return GameDay(year: year, month: month, day: 1).distance(to: next)
    }
}
