@testable import HouseCatCore
import Testing

/// Josh's decisions of 18 Oct 2026.
@Suite("Christmas season calendar")
struct SeasonCalendarTests {
    @Test func decemberIsAlwaysTheChristmasSeason() {
        for year in 2026 ... 2040 {
            let christmas = SeasonCalendar.christmas(year: year)
            #expect(christmas.start == GameDay(year: year, month: 12, day: 1))
            #expect(christmas.lengthDays == 28)
            let slot = SeasonCalendar.slot(containing: GameDay(year: year, month: 12, day: 25))
            #expect(slot == christmas)
        }
    }

    @Test func twelveFourWeekSeasonsThenChristmas() {
        for year in [2027, 2028] {
            let slots = SeasonCalendar.slots(endingWithChristmasOf: year)
            #expect(slots.count == 13)
            #expect(slots.first?.start == GameDay(year: year - 1, month: 12, day: 29))
            for (a, b) in zip(slots, slots.dropFirst()) {
                #expect(a.end == b.start)
            }
            #expect(slots.dropLast(2).allSatisfy { $0.lengthDays == 28 })
            // The season that meets 1 December takes the spare day (two in a leap year).
            #expect(slots[11].lengthDays == (year == 2028 ? 30 : 29))
            #expect(slots[11].end == GameDay(year: year, month: 12, day: 1))
            #expect(slots.filter(\.isChristmas).count == 1)
        }
    }

    @Test func everyDayIsInExactlyOneSeason() {
        let start = GameDay(year: 2026, month: 1, day: 1)
        for offset in 0 ..< 1200 {
            let day = start.advanced(by: offset)
            let slot = SeasonCalendar.slot(containing: day)
            #expect(slot.contains(day))
        }
        #expect(SeasonCalendar.slot(containing: GameDay(year: 2026, month: 12, day: 29)).start == GameDay(year: 2026, month: 12, day: 29))
        #expect(SeasonCalendar.slot(containing: GameDay(year: 2026, month: 11, day: 15)).end == GameDay(year: 2026, month: 12, day: 1))
    }
}

@Suite("Seasonal stock")
struct ShopRulesTests {
    @Test func seasonalOutfitsAreOnSaleOnlyInTheirMonths() {
        let october = [10]
        #expect(ShopRules.isOnSale(months: october, on: GameDay(year: 2026, month: 10, day: 31)))
        #expect(!ShopRules.isOnSale(months: october, on: GameDay(year: 2026, month: 11, day: 1)))
        #expect(ShopRules.isOnSale(months: october, on: GameDay(year: 2027, month: 10, day: 1))) // back every year
        #expect(ShopRules.isOnSale(months: [], on: GameDay(year: 2026, month: 3, day: 3)))
    }

    @Test func theShopCanSayWhenItIsOnSaleUntil() {
        #expect(ShopRules.lastSaleDay(months: [10], from: GameDay(year: 2026, month: 10, day: 5)) == GameDay(
            year: 2026,
            month: 10,
            day: 31
        ))
        #expect(ShopRules.lastSaleDay(months: [11, 12], from: GameDay(year: 2026, month: 11, day: 5)) == GameDay(
            year: 2026,
            month: 12,
            day: 31
        ))
        #expect(ShopRules.lastSaleDay(months: [10], from: GameDay(year: 2026, month: 9, day: 5)) == nil)
        #expect(ShopRules.lastSaleDay(months: [], from: GameDay(year: 2026, month: 9, day: 5)) == nil)
    }
}

@Suite("Objectives a player can attempt")
struct ObjectiveEligibilityTests {
    let mac = ObjectiveDefinition(id: "hello_mac", metric: .macVisit, target: 1, beans: 15, passPoints: 5)
    let pets = (1 ... 3).map { ObjectiveDefinition(id: "pet\($0)", metric: .pet, target: $0, beans: 10, passPoints: 5) }

    func dailies(_ f: Fixture, days: Range<Int>) -> Set<String> {
        Set(days.flatMap { f.state(through: $0).today?.objectives ?? [] })
    }

    @Test func noMacObjectiveWithoutAMac() {
        let f = Fixture(context: RulesContext(dailyObjectives: [mac] + pets))
        #expect(!dailies(f, days: 0 ..< 40).contains("hello_mac"))
    }

    @Test func aMacVisitMakesTheMacObjectivePossible() {
        var f = Fixture(context: RulesContext(dailyObjectives: [mac] + pets))
        f.add(.fed(catID: f.cat), day: 0, source: .mac)
        #expect(dailies(f, days: 1 ..< 40).contains("hello_mac"))
    }

    @Test func otherObjectivesNeedTheirThing() {
        let state = Fixture().state
        func can(_ metric: ObjectiveMetric) -> Bool {
            state.canAttempt(ObjectiveDefinition(id: "x", metric: metric, target: 1, beans: 1, passPoints: 0))
        }
        #expect(!can(.watchVisit))
        #expect(!can(.wearOutfit))
        #expect(!can(.sendPawPrint))
        #expect(!can(.openRoom)) // level 1: no room's level reached yet
        #expect(can(.pet) && can(.widgetVisit) && can(.changeSurface))
    }
}

@Suite("Rooms are catalogue sections")
struct CatalogueSectionTests {
    @Test func anyItemGoesInAnyOpenRoom() {
        var f = Fixture()
        f.add(.itemGranted(itemID: "kitchen_bowl"), day: 0)
        f.add(.itemPlaced(itemID: "kitchen_bowl", room: .living, x: 2, y: 8, facing: .right), day: 0)
        #expect(f.state.placed.map(\.room) == [.living])
    }
}
