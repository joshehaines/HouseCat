import Foundation
@testable import HouseCatCore
import Testing

@Suite("Behaviour table")
struct BehaviourTests {
    let livingRoom: Set<Affordance> = [.sit, .sleep, .hide, .perch, .scratch, .eat, .watch, .bat]

    func context(
        mood: Mood = .content,
        weather: Weather = .cloud,
        personality: Personality = .aloof,
        time: TimeOfDay = .midday,
        available: Set<Affordance>? = nil,
        sunlit: Bool = false
    ) -> BehaviourContext {
        BehaviourContext(
            mood: mood,
            weather: weather,
            personality: personality,
            timeOfDay: time,
            available: available ?? livingRoom,
            sunlit: sunlit
        )
    }

    func tally(_ context: BehaviourContext, runs: Int = 2000) -> [Activity: Int] {
        var counts: [Activity: Int] = [:]
        let start = GameDay(year: 2026, month: 11, day: 2)
        for i in 0 ..< runs {
            var rng = DaySeed(household: 3, day: start.advanced(by: i), purpose: "brain")
            counts[BehaviourTable.choose(context, rng: &rng).activity, default: 0] += 1
        }
        return counts
    }

    @Test func aCatWithNoFurnitureToSitOnLoafsOnTheFloorAndSaysSo() {
        var rng = DaySeed(household: 1, day: GameDay(index: 0), purpose: "brain")
        let empty = BehaviourTable.choose(context(available: []), rng: &rng)
        #expect(empty.activity == .floorLoaf)
        #expect(empty.pose == .loafSide)
        #expect(empty.lineContext == BehaviourTable.emptyRoomLine)
        // A plant and a bowl give it nothing to sit on either.
        let plantOnly = BehaviourTable.choose(context(available: [.bat, .eat]), rng: &rng)
        #expect(plantOnly.activity == .floorLoaf)
    }

    @Test func anEmptyRoomStillGetsTheBowlNagWhenHungry() {
        var rng = DaySeed(household: 1, day: GameDay(index: 0), purpose: "brain")
        #expect(BehaviourTable.choose(context(mood: .hungry, available: [.eat]), rng: &rng).activity == .bowlNag)
    }

    @Test func sulkingAndHungerComeFirst() {
        var rng = DaySeed(household: 1, day: GameDay(index: 0), purpose: "brain")
        #expect(BehaviourTable.choose(context(mood: .sulky), rng: &rng) == BehaviourChoice(activity: .sulk))
        #expect(BehaviourTable.choose(context(mood: .hungry), rng: &rng).activity == .bowlNag)
        #expect(BehaviourChoice(activity: .bowlNag).affordance == .eat)
    }

    @Test func rainSendsTheCatToTheWindow() {
        let rainy = tally(context(weather: .rain, time: .afternoon))
        let dry = tally(context(weather: .cloud, time: .afternoon))
        #expect((rainy[.windowWatch] ?? 0) > 400)
        #expect((dry[.windowWatch] ?? 0) == 0)
        // No window seat, no window watching.
        #expect(tally(context(weather: .rain, available: [.sit, .sleep]))[.windowWatch] == nil)
    }

    @Test func sunInTheRoomMakesASunbeamLoaf() {
        let sunny = tally(context(weather: .sun, personality: .loaf, time: .midday, sunlit: true))
        #expect((sunny[.sunbeamLoaf] ?? 0) > 400)
        #expect(tally(context(weather: .sun, time: .midday, sunlit: false))[.sunbeamLoaf] == nil)
    }

    @Test func personalityChangesTheWeights() {
        let gremlin = tally(context(personality: .gremlin, time: .evening))
        let aloof = tally(context(personality: .aloof, time: .evening))
        #expect((gremlin[.zoomies] ?? 0) > (aloof[.zoomies] ?? 0) * 3)
        let velcro = tally(context(personality: .velcro, time: .evening))
        #expect((velcro[.nearPlayer] ?? 0) > (aloof[.nearPlayer] ?? 0) * 3)
    }

    @Test func nightMeansBed() {
        let night = tally(context(time: .night))
        #expect((night[.sleep] ?? 0) > 1000)
    }

    @Test func theChoiceIsDeterministic() {
        var a = DaySeed(household: 8, day: GameDay(index: 20000), purpose: "brain", salt: "pip")
        var b = DaySeed(household: 8, day: GameDay(index: 20000), purpose: "brain", salt: "pip")
        let c = context(weather: .rain, personality: .gremlin, time: .evening)
        #expect(BehaviourTable.choose(c, rng: &a) == BehaviourTable.choose(c, rng: &b))
    }

    @Test func timeOfDayBands() {
        let clock = DayClock(wakeMinutes: 360, bedtimeMinutes: 1380)
        #expect(TimeOfDay.at(localMinutes: 7 * 60, clock: clock) == .morning)
        #expect(TimeOfDay.at(localMinutes: 12 * 60, clock: clock) == .midday)
        #expect(TimeOfDay.at(localMinutes: 15 * 60, clock: clock) == .afternoon)
        #expect(TimeOfDay.at(localMinutes: 19 * 60, clock: clock) == .evening)
        #expect(TimeOfDay.at(localMinutes: 23 * 60 + 30, clock: clock) == .night)
        #expect(TimeOfDay.at(localMinutes: 3 * 60, clock: clock) == .night)
    }

    @Test func moodComesFromTheSave() {
        var f = Fixture()
        f.visit(days: [0]) // day 1 missed
        var state = f.state(through: 2)
        #expect(state.mood(of: f.cat, at: f.at(2, 8)) == .sulky)
        f.add(.arrived, day: 2, hour: 8)
        #expect(f.state.mood(of: f.cat, at: f.at(2, 8)) == .sulky) // the first return visit
        f.add(.arrived, day: 2, hour: 12)
        #expect(f.state.mood(of: f.cat, at: f.at(2, 12)) == .thawing)
        f.add(.arrived, day: 2, hour: 13)
        #expect(f.state.mood(of: f.cat, at: f.at(2, 13)) == .hungry)
        f.add(.fed(catID: f.cat), day: 2, hour: 13)
        state = f.state
        #expect(state.mood(of: f.cat, at: f.at(2, 13)) == .content)
        #expect(state.mood(of: f.cat, at: f.at(2, 23, 30)) == .sleepy)
    }

    @Test func roomAffordancesComeFromPlacedFurniture() {
        var f = Fixture()
        f.add(.itemGranted(itemID: "living_sofa"), day: 0)
        f.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 1, y: 6, facing: .right), day: 0)
        let catalogue: [String: Set<Affordance>] = ["living_sofa": [.sit, .sleep], "living_picture": [.none]]
        #expect(f.state.affordances(in: .living, catalogue: catalogue) == [.sit, .sleep])
        #expect(f.state.affordances(in: .bedroom, catalogue: catalogue).isEmpty)
    }
}

@Suite("Widget state")
struct WidgetTests {
    func pose(_ f: Fixture, _ day: Int, _ hour: Int, _ minute: Int = 0) -> WidgetPose {
        WidgetRules.state(at: f.at(day, hour, minute), save: f.state, context: f.context).pose
    }

    @Test func beforeAVisitTheCatWaits() {
        var f = Fixture()
        f.visit(days: [0])
        #expect(pose(f, 1, 7) == .waitingByDoor)
        #expect(pose(f, 1, 12) == .lookingOutWindow)
        #expect(pose(f, 1, 20) == .stillWaiting)
        #expect(WidgetRules.state(at: f.at(1, 21), save: f.state, context: f.context).lineContext == WidgetRules.stillWaitingLine)
        #expect(pose(f, 1, 2) == .stillWaiting) // after midnight, still the same game day
    }

    @Test func afterAVisitTheCatGetsOnWithItsDay() {
        var f = Fixture()
        f.visit(days: [0])
        f.add(.arrived, day: 1, hour: 8)
        f.add(.fed(catID: f.cat), day: 1, hour: 8)
        // Collect the gifts so they do not override (the collection is in the save, so no gift waits at any time).
        f.collectGifts(day: 1, hour: 23, minute: 30)
        #expect(f.state.pendingGifts.isEmpty)
        #expect(pose(f, 1, 8, 30) == .content)
        #expect(pose(f, 1, 9, 30) == .content)
        #expect(pose(f, 1, 11) == .loaf)
        #expect(pose(f, 1, 15) == .box)
        #expect(pose(f, 1, 19) == .sofa)
        #expect(pose(f, 1, 22) == .zoomies)
        #expect(pose(f, 1, 23) == .asleep)
        #expect(pose(f, 1, 3) == .asleep)
    }

    @Test func aWaitingGiftOverridesWithTheCatHoldingIt() {
        var f = Fixture()
        f.add(.arrived, day: 0, hour: 8)
        f.add(.fed(catID: f.cat), day: 0, hour: 8)
        let drop = f.state.pendingGifts[0].dropAt
        let before = WidgetRules.state(at: drop.addingTimeInterval(-60), save: f.state, context: f.context)
        let after = WidgetRules.state(at: drop.addingTimeInterval(60), save: f.state, context: f.context)
        #expect(before.pose != .holdingGift)
        #expect(after.pose == .holdingGift)
    }

    @Test func aMissedYesterdayShowsASulkUntilYouVisit() {
        var f = Fixture()
        f.visit(days: [0]) // day 1 missed
        #expect(pose(f, 2, 9) == .sulk)
        #expect(WidgetRules.state(at: f.at(2, 9), save: f.state, context: f.context).streak == 1) // graced
        f.add(.petted(catID: f.cat), day: 2, hour: 10, source: .widget)
        f.collectGifts(day: 2, hour: 10, minute: 1) // yesterday's gift was waiting
        #expect(pose(f, 2, 10, 30) == .content)
    }

    @Test func theMoodEscalatesGentlyThroughTheDay() {
        var f = Fixture()
        f.visit(days: [0, 1, 2])
        func state(_ day: Int, _ hour: Int) -> WidgetState {
            WidgetRules.state(at: f.at(day, hour), save: f.state, context: f.context)
        }
        #expect(state(3, 9).mood == .waiting)
        #expect(state(3, 15).mood == .waiting)
        // From the evening, a streak to keep: the last chance, with the hours left until the day ends at waking.
        let evening = state(3, 21)
        #expect(evening.mood == .lastChance)
        let wake = f.state.clock.wakeMinutes / 60
        #expect(evening.hoursLeft == 24 - 21 + wake)
        #expect(state(3, 2).mood == .lastChance) // after midnight, the same game day
        // The sulk comes only the next morning, and a visit makes the cat glad again.
        #expect(state(4, 9).mood == .sulking)
        f.add(.arrived, day: 4, hour: 10)
        #expect(state(4, 11).mood == .content)
        #expect(state(4, 11).hoursLeft == nil)
    }

    @Test func theAddWidgetCardAsksAfterTheFirstFeedAndOnDayThreeOnly() {
        var f = Fixture()
        #expect(WidgetPromptRules.due(f.state, asked: [], installed: false) == nil)
        f.visit(days: [0])
        #expect(WidgetPromptRules.due(f.state, asked: [], installed: false) == .firstFeed)
        #expect(WidgetPromptRules.due(f.state, asked: [], installed: true) == nil)
        #expect(WidgetPromptRules.due(f.state, asked: ["firstFeed"], installed: false) == nil)
        f.visit(days: [1, 2])
        #expect(WidgetPromptRules.due(f.state, asked: ["firstFeed"], installed: false) == .thirdDay)
        #expect(WidgetPromptRules.due(f.state, asked: ["firstFeed", "thirdDay"], installed: false) == nil)
    }

    @Test func withNothingAtStakeTheEveningIsJustWaiting() {
        let f = Fixture()
        #expect(WidgetRules.state(at: f.at(0, 21), save: f.state, context: f.context).mood == .waiting)
    }

    @Test func theStreakAndFedFlagAreOnEveryEntry() {
        var f = Fixture()
        f.visit(days: [0, 1, 2])
        let state = WidgetRules.state(at: f.at(2, 12), save: f.state, context: f.context)
        #expect(state.streak == 3)
        #expect(state.visitedToday)
        #expect(state.fedToday)
    }

    @Test func aTimelineHasFortyEightEntriesHalfAnHourApart() {
        var f = Fixture()
        f.visit(days: [0])
        let start = f.at(1, 7, 10)
        let timeline = WidgetRules.timeline(from: start, save: f.state, context: f.context)
        #expect(timeline.count == 48)
        #expect(timeline[0].date == start)
        #expect(timeline[1].date == f.at(1, 7, 30))
        #expect(timeline[2].date.timeIntervalSince(timeline[1].date) == 1800)
        // The app computes the same state for the same moment.
        #expect(timeline[10] == WidgetRules.state(at: timeline[10].date, save: f.state, context: f.context))
    }
}

@Suite("Time together")
struct TimeTogetherTests {
    @Test func togetherDaysRiseThroughMissesAndLostStreaks() throws {
        var f = Fixture()
        f.visit(days: [0, 1])
        f.visit(days: [10]) // a lost streak in between
        let state = f.state(through: 43)
        let cat = try #require(state.cat(f.cat))
        #expect(cat.togetherDays(on: f.day(43)) == 43)
        #expect(state.streak.current == 0)
        #expect(state.lifetimeValue(.togetherDays, on: f.day(43)) == 43)
    }

    @Test func kittensGrowUpOnDayTwentyOne() throws {
        var f = Fixture()
        f.add(.catAdopted(catID: "smudge", name: "Smudge with a very long name indeed", personality: .velcro, isKitten: true), day: 0)
        let kitten = try #require(f.state.cat("smudge"))
        #expect(kitten.name.count == 20)
        #expect(kitten.isKittenStage(on: f.day(20)))
        #expect(!kitten.isKittenStage(on: f.day(21)))
        #expect(kitten.ageDays(on: f.day(0)) == 84)
        #expect(f.state.cat(f.cat)?.ageDays(on: f.day(365)) == 730 + 365)
    }
}
