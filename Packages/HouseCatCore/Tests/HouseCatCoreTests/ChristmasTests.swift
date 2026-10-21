import Foundation
@testable import HouseCatCore
import Testing

/// The Christmas event (SPEC "Launch", "Sky, season, weather and windows"): an advent track every December,
/// 1 December to 6 January, snow past every window while it runs, and the day's first arrival greeting it.
@Suite("Christmas")
struct ChristmasTests {
    let content: ContentBundle
    let context: RulesContext

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    private var advent: EventDefinition {
        context.events.first { $0.id == "advent_2026" }!
    }

    @Test func adventComesBackEveryDecember() {
        let advents = context.events.filter { $0.id.hasPrefix("advent_") }
        #expect(advents.count == Tuning.Events.yearsAhead)
        for (offset, event) in advents.enumerated() {
            let year = 2026 + offset
            #expect(event.id == "advent_\(year)")
            #expect(event.startDay == GameDay(year: year, month: 12, day: 1))
            #expect(event.lastDay == GameDay(year: year + 1, month: 1, day: 6))
            #expect(event.date(ofDay: 25) == GameDay(year: year, month: 12, day: 25))
            #expect(event.dated && event.snow && event.kind == .track)
        }
    }

    @Test func everyDoorHasAPresentThatExistsAndIsNotTheHousewarmingsAgain() throws {
        #expect(advent.rewards.map(\.day) == Array(1 ... 25))
        let items = Set(content.catalogue.items.map(\.id))
        let excluded = Set((content.catalogue.excluded ?? []).map(\.id))
        let housewarming = try #require(context.events.first { $0.id == "housewarming_track" })
        let given = Set(housewarming.rewards.compactMap(\.item))
        for reward in advent.rewards {
            #expect(reward.beans != nil || reward.item != nil)
            if let item = reward.item {
                #expect(items.contains(item) && !excluded.contains(item) && !given.contains(item), "\(item)")
            }
        }
    }

    @Test func snowFallsPastTheWindowsOnlyWhileItRuns() {
        var f = Fixture(context: context)
        f.visit(days: [0])
        let state = f.state
        let noon = { (day: GameDay) in f.clock.date(on: day, atLocalMinutes: 12 * 60) }
        // Whatever the weather would be, it snows in December.
        let december = GameDay(year: 2026, month: 12, day: 10)
        #expect(state.homeNow(at: noon(december), weather: content.weather, context: context).weather == .snow)
        // The event's snow is the game's, not Apple Weather's, so no mark goes with it.
        #expect(!state.homeNow(at: noon(december), weather: content.weather, context: context).weatherIsReal)
        #expect(EventRules.snowing(on: GameDay(year: 2027, month: 1, day: 6), context: context))
        // Before and after, the weather is the day's own.
        for day in [GameDay(year: 2026, month: 11, day: 30), GameDay(year: 2027, month: 1, day: 7)] {
            #expect(!EventRules.snowing(on: day, context: context))
            #expect(
                state.homeNow(at: noon(day), weather: content.weather, context: context).weather
                    == state.homeNow(at: noon(day), weather: content.weather).weather
            )
        }
    }

    @Test func theFirstArrivalOfASpecialDayGreetsIt() {
        var f = Fixture(context: context)
        let christmas = f.start.distance(to: GameDay(year: 2026, month: 12, day: 11))
        let newYear = f.start.distance(to: GameDay(year: 2027, month: 1, day: 1))
        f.visit(days: Array(0 ..< christmas))
        // The Housewarming's second day, then a day in December.
        #expect(Greeting.context(before: f.state(through: 1), at: f.at(1, 9), rules: context) != "arrival.first_of_day")
        #expect(Greeting.context(before: f.state(through: christmas), at: f.at(christmas, 9), rules: context) == "event.christmas")
        // Without the events, an ordinary first arrival.
        #expect(Greeting.context(before: f.state(through: christmas), at: f.at(christmas, 9)) == "arrival.first_of_day")
        f.visit(days: [christmas])
        #expect(Greeting.context(before: f.state(through: christmas), at: f.at(christmas, 15), rules: context) == "arrival.second_visit")
        // New Year's Day has its own lines, inside the Christmas event.
        f.visit(days: Array(christmas + 1 ..< newYear))
        #expect(Greeting.context(before: f.state(through: newYear), at: f.at(newYear, 9), rules: context) == "event.new_year")
    }
}
