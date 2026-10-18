/// The visit streak (SPEC "Care and the visit streak"): consecutive game days
/// with a visit (an arrival in the app, or Feed or Pet from a widget, the Watch,
/// the Mac or Siri). One free miss per rolling week; pause mode up to 14 days a
/// quarter; a lost streak restarts at 1 and the longest streak is kept.
public struct StreakState: Codable, Equatable, Sendable {
    public private(set) var current = 0
    public private(set) var longest = 0
    public private(set) var lastVisitDay: GameDay?
    /// Days whose miss was forgiven, newest last (only the last window is kept).
    public private(set) var graceDays: [GameDay] = []
    /// Milestones (in days) ever reached; each pays once.
    public private(set) var milestonesReached: [Int] = []
    /// The run the last miss ended, and the missed day, while it can still be mended (StreakRepair).
    public private(set) var brokenLength = 0
    public private(set) var brokenOn: GameDay?

    public init() {}

    public enum MissOutcome: Equatable, Sendable {
        /// No streak was running.
        case none
        /// The free miss for this rolling week was used; the streak holds.
        case graced
        /// The streak ended; the next visit restarts it at 1.
        case lost
    }

    /// Counts a visit on `day`. Returns milestones (in days) reached for the first time.
    @discardableResult
    public mutating func visit(on day: GameDay) -> [Int] {
        guard lastVisitDay != day else { return [] }
        current += 1
        longest = max(longest, current)
        lastVisitDay = day
        var reached: [Int] = []
        for milestone in Tuning.Streak.milestoneDays where current >= milestone && !milestonesReached.contains(milestone) {
            milestonesReached.append(milestone)
            reached.append(milestone)
        }
        return reached
    }

    /// Records a missed day that was not paused.
    public mutating func miss(on day: GameDay) -> MissOutcome {
        guard current > 0 else { return .none }
        let windowStart = day.advanced(by: -(Tuning.Streak.graceWindowDays - 1))
        let gracesInWindow = graceDays.filter { $0 >= windowStart && $0 < day }.count
        if gracesInWindow < Tuning.Streak.graceMissesPerWindow {
            graceDays.append(day)
            graceDays.removeAll { $0 < windowStart }
            return .graced
        }
        brokenLength = current
        brokenOn = day
        current = 0
        return .lost
    }

    /// Puts the broken run back, joined to the days since. Returns milestones newly reached.
    public mutating func repair() -> [Int] {
        guard brokenLength > 0 else { return [] }
        current += brokenLength
        longest = max(longest, current)
        brokenLength = 0
        brokenOn = nil
        var reached: [Int] = []
        for milestone in Tuning.Streak.milestoneDays where current >= milestone && !milestonesReached.contains(milestone) {
            milestonesReached.append(milestone)
            reached.append(milestone)
        }
        return reached
    }

    /// Past its window, a broken run is let go.
    mutating func forgetBreak(before day: GameDay) {
        if let brokenOn, brokenOn.distance(to: day) > Tuning.Streak.repairWindowDays {
            self.brokenOn = nil
            brokenLength = 0
        }
    }

    /// Beans paid for a milestone.
    public static func beans(forMilestone days: Int) -> Int {
        guard let index = Tuning.Streak.milestoneDays.firstIndex(of: days) else { return 0 }
        return Tuning.Streak.milestoneBeans[index]
    }
}

/// Pause mode: up to 14 paused days per calendar quarter. A paused day neither
/// counts nor breaks the streak.
public struct PauseState: Codable, Equatable, Sendable {
    public var from: GameDay?
    public var until: GameDay?
    /// Paused days used, by quarter key.
    public var usedByQuarter: [Int: Int] = [:]

    public init() {}

    public var isSet: Bool {
        from != nil && until != nil
    }

    /// Whether `day` (which had no visit) is a paused day; records its use.
    public mutating func consume(_ day: GameDay) -> Bool {
        guard let from, let until, day >= from, day <= until else { return false }
        let used = usedByQuarter[day.quarter, default: 0]
        guard used < Tuning.Streak.pauseDaysPerQuarter else { return false }
        usedByQuarter[day.quarter] = used + 1
        return true
    }

    public func remaining(in quarter: Int) -> Int {
        Tuning.Streak.pauseDaysPerQuarter - usedByQuarter[quarter, default: 0]
    }
}
