import Foundation
@testable import HouseCatCore
import Testing

@Suite("The house ladder")
struct LadderTests {
    @Test func eightHousesClimbToLondonAndEachCostsMore() {
        let rungs = HouseLadder.rungs
        #expect(rungs.count == 8)
        #expect(rungs.first?.price == 0 && rungs.first?.room == .living)
        #expect(rungs.last?.place == .london && rungs.last?.style == .mansionFlat)
        #expect(Set(rungs.map(\.style)).count == 8, "every house once")
        for (lower, upper) in zip(rungs, rungs.dropFirst()) {
            #expect(upper.price > lower.price && upper.level >= lower.level && upper.tasks >= lower.tasks)
        }
        // Each step costs more than the one before it, so the climb slows.
        let steps = zip(rungs.dropFirst(), rungs.dropFirst(2)).map { $1.price - $0.price }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
        // Every room but the living room opens with exactly one house.
        let rooms = rungs.compactMap(\.room)
        #expect(Set(rooms) == Set(RoomID.allCases) && rooms.count == RoomID.allCases.count)
    }

    @Test func levelAndTasksComeBeforeBeans() {
        let next = HouseLadder.rung(3)
        #expect(HouseLadder.block(above: 2, level: 1, tasksDone: 9, beans: 99999) == .needsLevel(next.level))
        #expect(HouseLadder.block(above: 2, level: 9, tasksDone: 0, beans: 99999) == .needsTasks(done: 0, of: next.tasks))
        #expect(HouseLadder.block(above: 2, level: 9, tasksDone: 9, beans: 10) == .needsBeans(next.price))
        #expect(HouseLadder.block(above: 2, level: 9, tasksDone: 9, beans: next.price) == nil)
        #expect(HouseLadder.block(above: 8, level: 99, tasksDone: 99, beans: 999_999) == .atTheTop)
    }

    @Test func aNewHouseholdStartsAtTheBottomInAMadeUpTown() {
        let state = Fixture().state
        #expect(state.rung == 1 && state.nextRung?.number == 2)
        #expect(state.homePlace.name == "Puddlebury")
    }

    /// The tutorial gets you out of the first house: the housewarming allowance and the tour's welcome buy the second.
    @Test func theTutorialsBeansBuyTheSecondHouse() {
        var f = Fixture()
        f.add(.arrived, day: 0, hour: 8)
        f.add(.tourFinished, day: 0, hour: 8, minute: 10)
        #expect(f.state.beans >= HouseLadder.rung(2).price)
        f.add(.houseBought(rung: 2, beans: HouseLadder.rung(2).price), day: 0, hour: 8, minute: 11)
        #expect(f.state.rung == 2 && f.state.openedRooms.contains(.bedroom))
    }

    /// Each house asks as many tasks as the next one needs, and they count from moving in.
    @Test func everyHouseHasItsTasksCountedFromMovingIn() {
        for rung in HouseLadder.rungs.dropFirst() {
            #expect((Tuning.Ladder.houseTasks[rung.number - 1] ?? []).count == rung.tasks, "house \(rung.number - 1)")
        }
        #expect(Tuning.Ladder.houseTasks[HouseLadder.top] == nil, "London is the top")
        var f = Fixture()
        for day in 0 ..< 3 {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8, minute: 1)
        }
        f.add(.tourFinished, day: 2, hour: 9)
        f.add(.houseBought(rung: 2, beans: HouseLadder.rung(2).price), day: 2, hour: 9, minute: 1)
        // The three meals before the houseboat don't count towards its "Feed 10 times".
        let feeds = f.state.houseTaskProgress(on: f.day(2)).first { $0.task.metric == .totalFeeds }
        #expect(feeds?.done == 0)
        f.add(.fed(catID: f.cat), day: 3, hour: 8)
        #expect(f.state.houseTaskProgress(on: f.day(3)).first { $0.task.metric == .totalFeeds }?.done == 1)
    }

    @Test func aSaveFromBeforeTheLadderKeepsItsRooms() {
        var state = HouseholdState()
        state.openedRooms = [.living, .bedroom, .kitchen]
        #expect(state.rung == 3)
        state.openedRooms = [.living, .garden]
        #expect(state.rung == 4, "the highest room decides")
    }

    @Test func buyingTheNextHouseNeverSkipsAndOpensItsRoom() {
        var f = Fixture()
        f.add(.purchaseBeansGranted(transactionID: "t1", beans: 50000), day: 0)
        f.add(.houseBought(rung: 2, beans: HouseLadder.rung(2).price), day: 0)
        #expect(f.state.rung == 2)
        // Level 1: the third house is refused, whatever the Beans.
        f.add(.houseBought(rung: 3, beans: HouseLadder.rung(3).price), day: 0)
        #expect(f.state.rung == 2)
        var day = 0
        while f.state.level < HouseLadder.rung(3).level, day < 60 {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8)
            for goal in GameEvent.HealthGoal.allCases {
                f.add(.healthGoalMet(goal), day: day, hour: 20)
            }
            day += 1
        }
        #expect(f.state.level >= HouseLadder.rung(3).level)
        // Level and Beans are not enough: the houseboat's tasks come first.
        f.add(.houseBought(rung: 3, beans: HouseLadder.rung(3).price), day: day)
        #expect(f.state.rung == 2 && f.state.houseTasksDone < HouseLadder.rung(3).tasks)
        for game in 0 ..< 5 {
            f.add(.miniGamePlayed(game: "laser_pointer", stars: 1), day: day, hour: 10, minute: game)
        }
        for piece in 0 ..< 5 {
            f.add(.itemGranted(itemID: "living_plant_\(piece)"), day: day, hour: 10, minute: 10 + piece)
        }
        #expect(f.state.houseTasksDone == HouseLadder.rung(3).tasks)
        let price = HouseLadder.rung(3).price
        f.add(.houseBought(rung: 4, beans: HouseLadder.rung(4).price), day: day) // a skip: refused
        f.add(.houseBought(rung: 3, beans: 100), day: day) // underpaid: refused
        #expect(f.state.rung == 2)
        let before = f.state.beans
        f.add(.houseBought(rung: 3, beans: price), day: day)
        let state = f.state
        #expect(state.rung == 3)
        #expect(state.homeStyle == .woodlandCabin && state.homePlace.name == "Vancouver")
        #expect(state.openedRooms.contains(.kitchen))
        #expect(state.beans == before - price)
        f.add(.houseBought(rung: 3, beans: price), day: day) // the same house twice: refused
        #expect(f.state.beans == before - price)
    }
}
