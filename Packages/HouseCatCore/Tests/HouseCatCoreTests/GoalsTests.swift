import Foundation
@testable import HouseCatCore
import Testing

/// The long-term goals pay what they say (Josh, 19 Oct: something to work towards): the outfits a streak earns are
/// handed over, the rooms achievements count the living room, and trying outfits counts different ones.
@Suite("Goals")
struct GoalsTests {
    let context: RulesContext

    init() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    @Test func aThirtyDayStreakEarnsTheHoodieAndAHundredTheBowTie() {
        #expect(context.streakOutfits[30] == "hoodie" && context.streakOutfits[100] == "bowtie")
        var f = Fixture(context: context)
        f.visit(days: Array(0 ..< 29))
        #expect(!f.state.ownedOutfits.contains("hoodie"))
        f.visit(days: [29])
        #expect(f.state.streak.current == 30)
        #expect(f.state.ownedOutfits.contains("hoodie"), "the 30th day in a row earns it")
        f.visit(days: Array(30 ..< 100))
        #expect(f.state.ownedOutfits.contains("bowtie"))
    }

    @Test func theRoomsAchievementsCountTheLivingRoom() {
        var f = Fixture(context: context)
        f.visit(days: [0])
        var state = f.state
        #expect(state.lifetimeValue(.roomsOpened, on: f.day(0)) == 1, "the living room is open from the start")
        state.openedRooms = Set(RoomID.allCases)
        #expect(state.lifetimeValue(.roomsOpened, on: f.day(0)) == 6, "all six rooms is six: \"Open all six rooms\" can be earned")
        let rooms = context.achievements.filter { $0.metric == .roomsOpened }.map(\.target)
        #expect(rooms.max() == RoomID.allCases.count)
    }

    @Test func wearingTheSameOutfitTwiceIsOneOutfitTried() {
        var f = Fixture(context: context)
        f.add(.outfitBought(outfitID: "beanie", beans: 0, gift: false), day: 0, hour: 9)
        f.add(.outfitWorn(catID: f.cat, outfitID: "beanie"), day: 0, hour: 10)
        f.add(.outfitTakenOff(catID: f.cat), day: 0, hour: 11)
        f.add(.outfitWorn(catID: f.cat, outfitID: "beanie"), day: 0, hour: 12)
        #expect(f.state.lifetime.outfitsWorn == 1)
    }
}

/// The Goals page's board: today's and this week's three with their progress, and every achievement in its ladder
/// at its next step, the nearest first.
@Suite("Goal board")
struct GoalBoardTests {
    @Test func theBoardShowsTodayTheWeekAndEveryLadder() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        var f = try Fixture(context: content.rulesContext())
        f.visit(days: Array(0 ..< 8))
        let board = GoalBoard.make(f.state, objectives: content.objectives, on: f.day(7))
        #expect(board.today.count == Tuning.Objectives.dailyCount)
        #expect(board.week.count == 3)
        #expect(board.achievementsTotal == content.objectives.achievements.count)
        // A week of breakfasts: the first meals step is done and the seven-day streak too.
        let feeds = try #require(board.milestones.first { $0.id == "care_feeds" })
        #expect(feeds.stepsDone == 0 && feeds.next.progress == 8 && feeds.next.target == 10)
        #expect(board.achievementsDone >= 2, "three and seven days in a row")
        // The nearest unclimbed ladder comes first.
        let open = board.milestones.filter { !$0.climbed }
        #expect(zip(open, open.dropFirst()).allSatisfy { $0.next.fraction >= $1.next.fraction })
        #expect(board.today.allSatisfy { $0.progress <= $0.target })
    }
}
