import Foundation
@testable import HouseCatCore
import Testing

/// The cat's own ways, what it would love its home to have, and how content it is (Josh, 19 Oct: an empty home
/// should show; the cat needs a deeper identity). Nothing here ever takes anything away.
@Suite("Wellbeing and identity")
struct WellbeingTests {
    func cat(_ personality: Personality, id: String = "pip", careDays: Int = 0) -> CatState {
        CatState(id: id, name: "Pip", personality: personality, adoptedOn: GameDay(index: 0), isKitten: false, careDays: careDays)
    }

    let everything: Set<Affordance> = [.sleep, .sit, .scratch, .hide, .perch, .watch, .bat, .eat]

    @Test func aCatsWaysAreItsOwnAndTheSameEveryTime() {
        let a = CatIdentity.of(cat(.loaf), household: 42)
        #expect(a == CatIdentity.of(cat(.loaf), household: 42))
        #expect(a.quirks.count == Tuning.Identity.quirks && Set(a.quirks).count == a.quirks.count)
        #expect(a.ways.count == a.quirks.count + 2)
        // Different cats (or households) differ somewhere.
        let others = (0 ..< 20).map { CatIdentity.of(cat(.loaf, id: "cat\($0)"), household: 42) }
        #expect(Set(others.map { "\($0.favouriteSpot)\($0.quirks)\($0.hours)" }).count > 5)
        // A Velcro cat already follows you, so that is never one of its quirks; personality nudges the spot.
        var high = 0
        for i in 0 ..< 200 {
            #expect(!CatIdentity.of(cat(.velcro, id: "v\(i)"), household: 7).has(.followsYou))
            if [.high, .window].contains(CatIdentity.of(cat(.aloof, id: "a\(i)"), household: 7).favouriteSpot) {
                high += 1
            }
        }
        #expect(high > 100, "an Aloof cat mostly likes it high up or at the window, got \(high)")
    }

    @Test func anEmptyHomeLeavesItSettlingInWantingEverythingAndAFullOneIsHappy() {
        let loaf = cat(.loaf)
        let identity = CatIdentity(favouriteSpot: .soft, quirks: [.tuckedLoaf, .chatty], hours: .morning)
        var today = DayTally(day: GameDay(index: 3))
        today.fedCats = [loaf.id]
        today.pets = 3
        let empty = Wellbeing.of(loaf, identity: identity, offers: [.eat], today: today)
        #expect(empty.comfort == 0)
        #expect(empty.level == .settlingIn)
        #expect(Set(empty.wants) == Set(Want.allCases))
        // A Loaf who likes soft things wants a bed most.
        #expect(empty.wants.first == .bed)
        today.plays = 1
        let full = Wellbeing.of(cat(.loaf, careDays: 40), identity: identity, offers: everything, today: today)
        #expect(full.wants.isEmpty && full.comfort == 1)
        #expect(full.level == .overTheMoon)
        // The same home, nothing done for it today and no trust yet: comfortable, not more.
        let unfussed = Wellbeing.of(loaf, identity: identity, offers: everything, today: nil)
        #expect(unfussed.level == .comfortable)
        // An Aloof cat wants a perch or a window first.
        let aloof = Wellbeing.of(cat(.aloof), identity: CatIdentity(favouriteSpot: .high, quirks: [], hours: .morning), offers: [], today: nil)
        #expect([.perch, .window].contains(aloof.wants.first))
    }

    func context(time: TimeOfDay, available: Set<Affordance>, wants: [Want], identity: CatIdentity? = nil, personality: Personality = .loaf) -> BehaviourContext {
        BehaviourContext(mood: .content, weather: .cloud, personality: personality, timeOfDay: time, available: available, sunlit: false,
                         identity: identity, wants: wants)
    }

    @Test func withoutABedItSleepsOnTheFloorAndWithoutAPostItScratchesTheSofa() {
        var floor = 0, sofa = 0
        for i in 0 ..< 400 {
            var rng = DaySeed(household: 5, day: GameDay(index: i), purpose: "brain")
            let night = BehaviourTable.choose(context(time: .night, available: [.sit, .eat], wants: [.bed, .scratcher]), rng: &rng)
            if night.activity == .sleep, night.lineContext == Want.bed.lineContext {
                floor += 1
                #expect(night.affordance == .sleep)
            }
            let day = BehaviourTable.choose(context(time: .midday, available: [.sit, .sleep, .eat], wants: [.scratcher]), rng: &rng)
            if day.activity == .scratch {
                sofa += 1
                #expect(day.use == .sit && day.affordance == .sit)
            }
        }
        #expect(floor > 220, "no bed: mostly the floor at night, got \(floor)")
        #expect(sofa > 10, "no post: the sofa now and then, got \(sofa)")
        // With a bed it is never the floor.
        var rng = DaySeed(household: 5, day: GameDay(index: 0), purpose: "brain")
        for _ in 0 ..< 50 {
            let choice = BehaviourTable.choose(context(time: .night, available: [.sit, .sleep], wants: []), rng: &rng)
            #expect(choice.lineContext != Want.bed.lineContext)
        }
    }

    @Test func itsFavouriteSpotWeighsInWhatItDoes() {
        func perches(_ identity: CatIdentity?) -> Int {
            (0 ..< 600).reduce(0) { count, i in
                var rng = DaySeed(household: 8, day: GameDay(index: i), purpose: "brain")
                let choice = BehaviourTable.choose(context(time: .afternoon, available: [.sit, .sleep, .perch, .hide], wants: [], identity: identity, personality: .velcro), rng: &rng)
                return count + (choice.activity == .perch ? 1 : 0)
            }
        }
        let plain = perches(nil)
        let high = perches(CatIdentity(favouriteSpot: .high, quirks: [], hours: .morning))
        #expect(high > plain * 2, "a cat that likes it high perches more: \(high) against \(plain)")
    }
}

@Suite("The cat's profile: its ways and how it is")
struct ProfileWaysTests {
    @Test func theProfileListsItsWaysAndWithTheCatalogueHowContentItIs() throws {
        var f = Fixture()
        f.add(.fed(catID: f.cat), day: 0, hour: 8)
        let state = f.state
        let plain = try #require(state.profile(of: f.cat, on: f.day(0)))
        #expect(plain.ways.count == Tuning.Identity.quirks + 2)
        #expect(plain.contentment == nil && plain.wouldLove == nil)
        // An empty home: settling in, and it would love something.
        let catalogue: [String: Set<Affordance>] = ["living_sofa": [.sit, .sleep]]
        let empty = try #require(state.profile(of: f.cat, on: f.day(0), catalogue: catalogue))
        #expect(empty.contentment == .settlingIn)
        #expect(empty.wouldLove != nil)
        #expect(empty.ways == plain.ways)
    }
}
