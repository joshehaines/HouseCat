@testable import HouseCatCore
import Testing

@Suite("Objectives")
struct ObjectiveTests {
    let daily = (1 ... 20).map { ObjectiveDefinition(id: "d\($0)", metric: .pet, target: $0, beans: 10, passPoints: 5) }
    let weekly = (1 ... 12).map { ObjectiveDefinition(id: "w\($0)", metric: .visitDay, target: $0, beans: 50, passPoints: 20) }

    @Test func threeDailyObjectivesTheSameOnEveryDevice() {
        let day = GameDay(year: 2026, month: 11, day: 2)
        let a = ObjectiveRules.daily(from: daily, household: 9, day: day)
        let b = ObjectiveRules.daily(from: daily.shuffled(), household: 9, day: day)
        #expect(a.count == 3)
        #expect(Set(a.map(\.id)).count == 3)
        #expect(a == b)
        let days = (0 ..< 10).map { ObjectiveRules.daily(from: daily, household: 9, day: day.advanced(by: $0)).map(\.id) }
        #expect(Set(days).count > 1)
    }

    @Test func weeklyObjectivesHoldForTheWeek() {
        let monday = GameDay(year: 2026, month: 11, day: 2)
        let week = ObjectiveRules.weekly(from: weekly, household: 9, day: monday)
        #expect(week.count == 3)
        #expect(ObjectiveRules.weekly(from: weekly, household: 9, day: monday.advanced(by: 6)) == week)
    }

    @Test func completingADailyObjectivePaysOnce() {
        let objective = ObjectiveDefinition(id: "pet_twice", metric: .pet, target: 2, beans: 15, passPoints: 5)
        var f = Fixture(context: RulesContext(dailyObjectives: [objective]))
        for minute in 0 ..< 4 {
            f.add(.petted(catID: f.cat), day: 0, hour: 9, minute: minute)
        }
        let state = f.state
        #expect(state.today?.completed == ["pet_twice"])
        // The pets also count as the day's visit: no arrival, so 150 + 15 only.
        #expect(state.beans == 150 + 15)
    }

    @Test func feedBeforeNineCountsOnlyEarlyMorningFeeds() {
        let objective = ObjectiveDefinition(id: "early", metric: .feedBefore9, target: 1, beans: 20, passPoints: 5)
        var late = Fixture(context: RulesContext(dailyObjectives: [objective]))
        late.add(.fed(catID: late.cat), day: 0, hour: 9, minute: 1)
        #expect(late.state.today?.completed.isEmpty == true)
        var early = Fixture(context: RulesContext(dailyObjectives: [objective]))
        early.add(.fed(catID: early.cat), day: 0, hour: 8, minute: 59)
        #expect(early.state.today?.completed == ["early"])
    }

    @Test func weeklyVisitDaysAndAchievements() {
        let visitAll = ObjectiveDefinition(id: "all_week", metric: .visitDay, target: 7, beans: 100, passPoints: 20)
        let tenFeeds = ObjectiveDefinition(id: "ten_feeds", metric: .totalFeeds, target: 10, beans: 50, passPoints: 0)
        var f = Fixture(context: RulesContext(weeklyObjectives: [visitAll], achievements: [tenFeeds]))
        f.visit(days: Array(0 ..< 7))
        var state = f.state(through: 7)
        #expect(state.week?.weekStart == f.day(7)) // a new week has started
        #expect(!state.completedAchievements.contains("ten_feeds"))
        f.visit(days: Array(7 ..< 10))
        state = f.state(through: 10)
        #expect(state.completedAchievements == ["ten_feeds"])
        // 150 + 10 arrivals + streak 7 (100) + weekly 100 + achievement 50 + level-up (150 XP) 100
        #expect(state.beans == 150 + 100 + 100 + 100 + 50 + 100)
    }
}

@Suite("Launch events")
struct LaunchEventTests {
    let content: ContentBundle
    let context: RulesContext

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    var track: EventDefinition {
        context.events.first { $0.id == "housewarming_track" }!
    }

    @Test func theEventsRunFromLaunchWithRealDates() throws {
        let launch = try #require(content.seasons.launchDay)
        #expect(track.startDay == launch)
        #expect(track.lastDay == launch.advanced(by: 13))
        let sale = try #require(EventRules.onSale("housecat.season.housewarming", on: launch.advanced(by: 30), context: context))
        #expect(sale.lastDay == launch.advanced(by: 30))
        #expect(EventRules.onSale("housecat.season.housewarming", on: launch.advanced(by: 31), context: context) == nil)
        #expect(EventRules.live(on: launch.advanced(by: -1), context: context).isEmpty)
    }

    @Test func everyDayOfTheTrackHasAPresentThatExists() {
        #expect(track.rewards.map(\.day) == Array(1 ... 14))
        let items = Set(content.catalogue.items.map(\.id))
        for reward in track.rewards {
            #expect(reward.beans != nil || reward.item != nil)
            if let item = reward.item {
                #expect(items.contains(item), "\(item)")
            }
        }
    }

    @Test func presentsAreClaimedOnTheirDayOrLaterOnceEach() {
        var f = Fixture(context: context)
        let offset = f.start.distance(to: track.startDay)
        f.visit(days: [offset])
        // Day one: only day one's present.
        #expect(EventRules.claimable(track, state: f.state, on: f.day(offset)) == [1])
        let before = f.state.beans
        f.add(.eventRewardClaimed(eventID: track.id, day: 1), day: offset, hour: 9)
        f.add(.eventRewardClaimed(eventID: track.id, day: 1), day: offset, hour: 9, minute: 1)
        #expect(f.state.beans == before + 50)
        // Not tomorrow's yet.
        f.add(.eventRewardClaimed(eventID: track.id, day: 2), day: offset, hour: 10)
        #expect(f.state.owned["living_clock"] == nil)
        // Back on day four: days two to four wait.
        f.visit(days: [offset + 3])
        #expect(EventRules.claimable(track, state: f.state, on: f.day(offset + 3)) == [2, 3, 4])
        f.add(.eventRewardClaimed(eventID: track.id, day: 2), day: offset + 3, hour: 9)
        #expect(f.state.owned["living_clock"] == 1)
        // After the track, nothing more.
        f.visit(days: [offset + 14])
        #expect(EventRules.claimable(track, state: f.state, on: f.day(offset + 14)).isEmpty)
        f.add(.eventRewardClaimed(eventID: track.id, day: 5), day: offset + 14, hour: 9)
        #expect(f.state.eventClaims[track.id] == [1, 2])
    }
}
