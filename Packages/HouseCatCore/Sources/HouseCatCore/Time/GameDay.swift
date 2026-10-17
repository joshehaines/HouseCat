import Foundation

/// A game day: a local calendar date, counted from the player's wake time
/// (see `DayClock`). Stored as days since 1970-01-01 so arithmetic is exact and
/// identical on every device.
public struct GameDay: Hashable, Comparable, Codable, Sendable, Strideable, CustomStringConvertible {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    /// A proleptic Gregorian date (Howard Hinnant's days-from-civil).
    public init(year: Int, month: Int, day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        index = era * 146_097 + doe - 719_468
    }

    /// Year, month (1–12) and day (1–31).
    public var date: (year: Int, month: Int, day: Int) {
        let z = index + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    public var month: Int {
        date.month
    }

    /// ISO weekday: 1 = Monday … 7 = Sunday.
    public var weekday: Int {
        ((index % 7 + 7 + 3) % 7) + 1
    }

    /// The Monday that starts this day's week.
    public var weekStart: GameDay {
        GameDay(index: index - (weekday - 1))
    }

    /// A key for the calendar quarter (pause allowance).
    public var quarter: Int {
        let date = date
        return date.year * 4 + (date.month - 1) / 3
    }

    public static func < (lhs: GameDay, rhs: GameDay) -> Bool {
        lhs.index < rhs.index
    }

    public func advanced(by n: Int) -> GameDay {
        GameDay(index: index + n)
    }

    public func distance(to other: GameDay) -> Int {
        other.index - index
    }

    public var description: String {
        let date = date
        return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    /// Parses "yyyy-MM-dd".
    public init?(iso string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1 ... 12).contains(parts[1]), (1 ... 31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
}
