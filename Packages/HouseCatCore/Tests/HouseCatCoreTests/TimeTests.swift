import Foundation
@testable import HouseCatCore
import Testing

@Suite("Game days")
struct GameDayTests {
    @Test func civilDatesRoundTrip() {
        for (y, m, d) in [(1970, 1, 1), (2000, 2, 29), (2026, 10, 17), (2027, 1, 4), (1969, 12, 31), (2100, 3, 1)] {
            let day = GameDay(year: y, month: m, day: d)
            #expect(day.date.year == y && day.date.month == m && day.date.day == d)
        }
        #expect(GameDay(year: 1970, month: 1, day: 1).index == 0)
    }

    @Test func weekdaysAndWeeksStartOnMonday() {
        let monday = GameDay(year: 2026, month: 11, day: 2)
        #expect(monday.weekday == 1)
        #expect(monday.advanced(by: 6).weekday == 7)
        #expect(monday.advanced(by: 6).weekStart == monday)
        #expect(monday.advanced(by: 7).weekStart == monday.advanced(by: 7))
        #expect(GameDay(year: 1970, month: 1, day: 1).weekday == 4) // a Thursday
        #expect(GameDay(year: 1969, month: 12, day: 31).weekday == 3)
    }

    @Test func quartersAndParsing() {
        #expect(GameDay(year: 2026, month: 3, day: 31).quarter != GameDay(year: 2026, month: 4, day: 1).quarter)
        #expect(GameDay(year: 2026, month: 1, day: 1).quarter == GameDay(year: 2026, month: 3, day: 31).quarter)
        #expect(GameDay(iso: "2026-12-07") == GameDay(year: 2026, month: 12, day: 7))
        #expect(GameDay(iso: "2026-13-07") == nil)
        #expect(GameDay(year: 2026, month: 12, day: 7).description == "2026-12-07")
    }
}

@Suite("Day clock")
struct DayClockTests {
    let clock = DayClock(wakeMinutes: 6 * 60, bedtimeMinutes: 23 * 60, timeZoneID: "Europe/London")

    private func london(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var components = DateComponents(year: y, month: m, day: d, hour: h, minute: min)
        components.timeZone = TimeZone(identifier: "Europe/London")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func dayResetsAtWakeTime() {
        let monday = GameDay(year: 2026, month: 11, day: 2)
        #expect(clock.day(of: london(2026, 11, 2, 6, 0)) == monday)
        #expect(clock.day(of: london(2026, 11, 2, 23, 59)) == monday)
        // 02:00 and 05:59 on Tuesday are still Monday's game day.
        #expect(clock.day(of: london(2026, 11, 3, 2, 0)) == monday)
        #expect(clock.day(of: london(2026, 11, 3, 5, 59)) == monday)
        #expect(clock.day(of: london(2026, 11, 3, 6, 0)) == monday.advanced(by: 1))
    }

    @Test func aLaterWakeTimeMovesTheReset() {
        let late = DayClock(wakeMinutes: 9 * 60, timeZoneID: "Europe/London")
        let monday = GameDay(year: 2026, month: 11, day: 2)
        #expect(late.day(of: london(2026, 11, 3, 8, 59)) == monday)
        #expect(late.day(of: london(2026, 11, 3, 9, 0)) == monday.advanced(by: 1))
    }

    @Test func summerTimeChangesDoNotShiftTheReset() {
        // Clocks go forward on 28 March 2027 and back on 25 October 2026.
        #expect(clock.day(of: london(2027, 3, 28, 5, 59)) == GameDay(year: 2027, month: 3, day: 27))
        #expect(clock.day(of: london(2027, 3, 28, 6, 0)) == GameDay(year: 2027, month: 3, day: 28))
        #expect(clock.day(of: london(2026, 10, 25, 6, 0)) == GameDay(year: 2026, month: 10, day: 25))
        #expect(clock.start(of: GameDay(year: 2027, month: 3, day: 28)) == london(2027, 3, 28, 6, 0))
        #expect(clock.start(of: GameDay(year: 2026, month: 10, day: 25)) == london(2026, 10, 25, 6, 0))
    }

    @Test func localTimesRoundTrip() {
        let day = GameDay(year: 2026, month: 11, day: 2)
        let evening = clock.date(on: day, atLocalMinutes: 22 * 60)
        #expect(evening == london(2026, 11, 2, 22))
        #expect(clock.localMinutes(of: evening) == 22 * 60)
        // Before the wake time means after midnight, still on this game day.
        let small = clock.date(on: day, atLocalMinutes: 2 * 60)
        #expect(small == london(2026, 11, 3, 2))
        #expect(clock.day(of: small) == day)
    }

    @Test func otherTimeZones() {
        let tokyo = DayClock(wakeMinutes: 6 * 60, timeZoneID: "Asia/Tokyo")
        let date = clock.date(on: GameDay(year: 2026, month: 11, day: 2), atLocalMinutes: 22 * 60) // 22:00 London = 07:00 Tokyo
        #expect(tokyo.day(of: date) == GameDay(year: 2026, month: 11, day: 3))
        #expect(tokyo.localMinutes(of: date) == 7 * 60)
    }
}

@Suite("Trusted time")
struct TrustedTimeTests {
    let anchor = TimeAnchor(trusted: Date(timeIntervalSince1970: 1_800_000_000), uptime: 1000, bootID: "boot-1")

    @Test func followsTheWallClockWhenItAgrees() {
        let wall = anchor.trusted.addingTimeInterval(600)
        let time = TrustedTime.now(wall: wall, uptime: 1600, bootID: "boot-1", anchor: anchor, lastGameTime: anchor.trusted)
        #expect(time == GameTime(date: wall, status: .live))
    }

    @Test func aBackwardsClockJumpIsIgnored() {
        let last = anchor.trusted.addingTimeInterval(3600)
        let wall = anchor.trusted.addingTimeInterval(-86400 * 3) // set back three days
        let time = TrustedTime.now(wall: wall, uptime: 4700, bootID: "boot-1", anchor: anchor, lastGameTime: last)
        #expect(time.status == .pausedBackwards)
        #expect(time.date >= last)
        // Game time never goes backwards, so no streak day or gift is lost or replayed.
        #expect(time.date == anchor.trusted.addingTimeInterval(3700))
    }

    @Test func aBackwardsJumpWithoutAnAnchorHoldsTheLastTime() {
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        let time = TrustedTime.now(wall: last.addingTimeInterval(-60), uptime: 5, bootID: "x", anchor: nil, lastGameTime: last)
        #expect(time == GameTime(date: last, status: .pausedBackwards))
    }

    @Test func aJumpOfMoreThanADayAheadPausesGameTime() {
        let wall = anchor.trusted.addingTimeInterval(86400 * 7) // a week ahead, but only 10 minutes passed
        let time = TrustedTime.now(wall: wall, uptime: 1600, bootID: "boot-1", anchor: anchor, lastGameTime: anchor.trusted)
        #expect(time.status == .pausedAhead)
        #expect(time.date == anchor.trusted.addingTimeInterval(600))
    }

    @Test func aSmallForwardDriftIsAllowed() {
        let wall = anchor.trusted.addingTimeInterval(600 + 3 * 3600) // three hours ahead: a time-zone hop
        let time = TrustedTime.now(wall: wall, uptime: 1600, bootID: "boot-1", anchor: anchor, lastGameTime: anchor.trusted)
        #expect(time.status == .live)
    }

    @Test func aNewBootCannotMeasureElapsedTimeAndTrustsTheWallClock() {
        let wall = anchor.trusted.addingTimeInterval(86400 * 3)
        let time = TrustedTime.now(wall: wall, uptime: 30, bootID: "boot-2", anchor: anchor, lastGameTime: anchor.trusted)
        #expect(time == GameTime(date: wall, status: .live))
    }

    @Test func aClockFarBehindTheAnchorFollowsTheAnchor() {
        let wall = anchor.trusted.addingTimeInterval(-86400 * 2)
        let time = TrustedTime.now(wall: wall, uptime: 1060, bootID: "boot-1", anchor: anchor, lastGameTime: nil)
        #expect(time.status == .pausedBackwards)
        #expect(time.date == anchor.trusted.addingTimeInterval(60))
    }
}

@Suite("Day seed")
struct DaySeedTests {
    let day = GameDay(year: 2026, month: 11, day: 2)

    @Test func theSameInputsGiveTheSameNumbers() {
        var a = DaySeed(household: 42, day: day, purpose: "gift", salt: "pip")
        var b = DaySeed(household: 42, day: day, purpose: "gift", salt: "pip")
        #expect((0 ..< 20).map { _ in a.next() } == (0 ..< 20).map { _ in b.next() })
    }

    @Test func anyChangeGivesDifferentNumbers() {
        let base = DaySeed(household: 42, day: day, purpose: "gift", salt: "pip")
        for other in [
            DaySeed(household: 43, day: day, purpose: "gift", salt: "pip"),
            DaySeed(household: 42, day: day.advanced(by: 1), purpose: "gift", salt: "pip"),
            DaySeed(household: 42, day: day, purpose: "brain", salt: "pip"),
            DaySeed(household: 42, day: day, purpose: "gift", salt: "sooty"),
        ] {
            var a = base, b = other
            #expect(a.next() != b.next())
        }
    }

    @Test func rangesWeightsAndShuffles() throws {
        var rng = DaySeed(household: 7, day: day, purpose: "test")
        for _ in 0 ..< 1000 {
            #expect((0 ..< 7).contains(rng.below(7)))
        }
        var counts = [0, 0, 0]
        for _ in 0 ..< 10000 {
            let picked = rng.pick(weights: [1, 0, 3])
            try counts[#require(picked)] += 1
        }
        #expect(counts[1] == 0)
        #expect(counts[2] > counts[0] * 2)
        #expect(rng.pick(weights: [0, 0]) == nil)
        let shuffled = rng.shuffled(Array(0 ..< 20))
        #expect(shuffled.sorted() == Array(0 ..< 20))
        #expect(shuffled != Array(0 ..< 20))
    }
}
