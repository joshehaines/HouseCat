import Foundation
@testable import HouseCatCore

/// Builds event logs on a test clock. Day 0 is Monday 2 November 2026; the
/// player wakes at 06:00 and goes to bed at 23:00, London time.
struct Fixture {
    let clock = DayClock(wakeMinutes: 6 * 60, bedtimeMinutes: 23 * 60, timeZoneID: "Europe/London")
    let start = GameDay(year: 2026, month: 11, day: 2)
    let seed: UInt64 = 0x5EED
    let cat = "midnight"
    var context = RulesContext.empty
    var log = SaveLog()

    init(context: RulesContext = .empty, created: Bool = true) {
        self.context = context
        if created {
            add(.householdCreated(seed: seed, clock: clock), day: 0, hour: 7)
            add(.catAdopted(catID: cat, name: "Pip", personality: .aloof, isKitten: false), day: 0, hour: 7)
        }
    }

    func day(_ offset: Int) -> GameDay {
        start.advanced(by: offset)
    }

    /// Local time on game day `offset`; hours before 06:00 fall after midnight.
    func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        clock.date(on: day(offset), atLocalMinutes: hour * 60 + minute)
    }

    @discardableResult
    mutating func add(
        _ kind: GameEvent.Kind,
        day offset: Int,
        hour: Int = 9,
        minute: Int = 0,
        source: GameEvent.Source = .app,
        actor: GameEvent.Actor = .owner
    ) -> GameEvent {
        let date = log.timestamp(for: at(offset, hour, minute))
        let event = GameEvent(at: date, day: clock.day(of: date), actor: actor, source: source, kind: kind)
        log.append(event)
        return event
    }

    /// An arrival and a feed on each listed day.
    mutating func visit(days: [Int], feed: Bool = true) {
        for offset in days {
            add(.arrived, day: offset, hour: 8)
            if feed {
                add(.fed(catID: cat), day: offset, hour: 8, minute: 5)
            }
        }
    }

    /// Collects every gift that has dropped by the given time.
    mutating func collectGifts(day offset: Int, hour: Int, minute: Int = 0) {
        let time = at(offset, hour, minute)
        for gift in state.waitingGifts(at: time) {
            log.append(GameEvent(
                at: time,
                day: day(offset),
                kind: .giftCollected(catID: gift.catID, giftID: gift.giftID, rarity: gift.rarity)
            ))
        }
    }

    /// State with every day before `offset` closed.
    func state(through offset: Int) -> HouseholdState {
        log.derive(through: day(offset), context: context)
    }

    /// State through the last event (its day still open).
    var state: HouseholdState {
        log.derive(context: context)
    }
}
