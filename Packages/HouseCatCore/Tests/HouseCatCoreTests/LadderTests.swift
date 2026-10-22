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
            #expect(upper.price > lower.price && upper.level > lower.level && upper.tasks >= lower.tasks)
        }
        // Each step costs more than the one before it, so the climb slows.
        let steps = zip(rungs.dropFirst(), rungs.dropFirst(2)).map { $1.price - $0.price }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
        // Every room but the living room opens with exactly one house.
        let rooms = rungs.compactMap(\.room)
        #expect(Set(rooms) == Set(RoomID.allCases) && rooms.count == RoomID.allCases.count)
    }

    @Test func levelAndTasksComeBeforeBeans() {
        let next = HouseLadder.rung(2)
        #expect(HouseLadder.block(above: 1, level: 1, tasksDone: 9, beans: 99999) == .needsLevel(next.level))
        #expect(HouseLadder.block(above: 1, level: 9, tasksDone: 0, beans: 99999) == .needsTasks(done: 0, of: next.tasks))
        #expect(HouseLadder.block(above: 1, level: 9, tasksDone: 9, beans: 10) == .needsBeans(next.price))
        #expect(HouseLadder.block(above: 1, level: 9, tasksDone: 9, beans: next.price) == nil)
        #expect(HouseLadder.block(above: 8, level: 99, tasksDone: 99, beans: 999_999) == .atTheTop)
    }

    @Test func aNewHouseholdStartsAtTheBottom() {
        let state = Fixture().state
        #expect(state.rung == 1 && state.nextRung?.number == 2)
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
        // Level 1: refused, whatever the Beans.
        f.add(.houseBought(rung: 2, beans: 1500), day: 0)
        #expect(f.state.rung == 1)
        var day = 0
        while f.state.level < HouseLadder.rung(2).level, day < 40 {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8)
            for goal in GameEvent.HealthGoal.allCases {
                f.add(.healthGoalMet(goal), day: day, hour: 20)
            }
            day += 1
        }
        #expect(f.state.level >= HouseLadder.rung(2).level)
        f.add(.houseBought(rung: 3, beans: 4000), day: day) // a skip: refused
        f.add(.houseBought(rung: 2, beans: 100), day: day) // underpaid: refused
        #expect(f.state.rung == 1)
        let before = f.state.beans
        f.add(.houseBought(rung: 2, beans: 1500), day: day)
        let state = f.state
        #expect(state.rung == 2)
        #expect(state.home.style == .houseboat && state.home.place?.name == "Amsterdam")
        #expect(state.openedRooms.contains(.bedroom))
        #expect(state.beans == before - 1500)
        f.add(.houseBought(rung: 2, beans: 1500), day: day) // the same house twice: refused
        #expect(f.state.beans == before - 1500)
    }
}
