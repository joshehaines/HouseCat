import Foundation

/// Turns trusted timestamps into game days. A streak day is the local calendar
/// day at the player's wake time: with a 06:00 wake time, 02:00 on Tuesday is
/// still Monday's game day.
public struct DayClock: Codable, Hashable, Sendable {
    public var wakeMinutes: Int
    public var bedtimeMinutes: Int
    public var timeZoneID: String

    public init(
        wakeMinutes: Int = Tuning.Day.defaultWakeMinutes,
        bedtimeMinutes: Int = Tuning.Day.defaultBedtimeMinutes,
        timeZoneID: String = Tuning.Day.defaultTimeZoneID
    ) {
        self.wakeMinutes = wakeMinutes
        self.bedtimeMinutes = bedtimeMinutes
        self.timeZoneID = timeZoneID
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
    }

    private static let secondsPerDay = 86400.0

    /// Seconds since 1970 on the local wall clock.
    private func localSeconds(_ date: Date) -> Double {
        date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
    }

    /// The game day a moment belongs to.
    public func day(of date: Date) -> GameDay {
        let shifted = localSeconds(date) - Double(wakeMinutes * 60)
        return GameDay(index: Int((shifted / Self.secondsPerDay).rounded(.down)))
    }

    /// Minutes after local midnight (0–1439).
    public func localMinutes(of date: Date) -> Int {
        let seconds = localSeconds(date)
        let intoDay = seconds - (seconds / Self.secondsPerDay).rounded(.down) * Self.secondsPerDay
        return Int(intoDay / 60)
    }

    /// The moment a game day reaches the given local time. Times before the wake
    /// time fall after midnight, at the end of the game day.
    public func date(on day: GameDay, atLocalMinutes minutes: Int) -> Date {
        let calendarDay = minutes >= wakeMinutes ? day.index : day.index + 1
        let localTarget = Double(calendarDay) * Self.secondsPerDay + Double(minutes * 60)
        // Resolve the offset at the target moment (two passes settle a DST change).
        var guess =
            Date(timeIntervalSince1970: localTarget - Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: localTarget))))
        guess = Date(timeIntervalSince1970: localTarget - Double(timeZone.secondsFromGMT(for: guess)))
        return guess
    }

    /// When the game day begins.
    public func start(of day: GameDay) -> Date {
        date(on: day, atLocalMinutes: wakeMinutes)
    }
}
