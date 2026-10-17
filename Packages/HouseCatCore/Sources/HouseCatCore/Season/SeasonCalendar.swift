/// When seasons run (Josh, 18 Oct 2026): December is always the Christmas
/// season. It starts on 1 December and lasts four weeks; twelve four-week
/// seasons follow back to back, and the last of them runs on to the next
/// 1 December, a day longer than four weeks (two in a leap year).
public enum SeasonCalendar {
    public struct Slot: Equatable, Sendable {
        public var start: GameDay
        /// Exclusive.
        public var end: GameDay
        public var isChristmas: Bool

        public var lengthDays: Int {
            start.distance(to: end)
        }

        public func contains(_ day: GameDay) -> Bool {
            day >= start && day < end
        }
    }

    /// The Christmas season of a year.
    public static func christmas(year: Int) -> Slot {
        let start = GameDay(year: year, month: Tuning.Pass.christmasMonth, day: Tuning.Pass.christmasStartDay)
        return Slot(start: start, end: start.advanced(by: Tuning.Pass.seasonLengthDays), isChristmas: true)
    }

    /// The thirteen seasons from the end of the previous year's Christmas
    /// season to the end of this year's.
    public static func slots(endingWithChristmasOf year: Int) -> [Slot] {
        let next = christmas(year: year)
        var start = christmas(year: year - 1).end
        var slots: [Slot] = []
        let ordinary = Tuning.Pass.seasonsPerYear - 1
        for index in 0 ..< ordinary {
            let end = index == ordinary - 1 ? next.start : start.advanced(by: Tuning.Pass.seasonLengthDays)
            slots.append(Slot(start: start, end: end, isChristmas: false))
            start = end
        }
        slots.append(next)
        return slots
    }

    /// The season slot a day falls in.
    public static func slot(containing day: GameDay) -> Slot {
        let year = day.date.year
        let candidates = day >= christmas(year: year).end
            ? slots(endingWithChristmasOf: year + 1)
            : slots(endingWithChristmasOf: year)
        return candidates.first { $0.contains(day) } ?? christmas(year: year)
    }
}
