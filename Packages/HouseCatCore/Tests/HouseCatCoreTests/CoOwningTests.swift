import Foundation
@testable import HouseCatCore
import Testing

/// Step 8's exit test, on a test clock (SPEC "Build phases": two phones co-own one cat for three days without a
/// conflict): each phone keeps its own log, offline most of the time, and they swap events now and then in
/// any order. Whatever they did, both end with the same household, nothing lost, nothing doubled, no Beans
/// spent twice and no two pieces of furniture in the same cells.
@Suite("Co-owning")
struct CoOwningTests {
    let context: RulesContext
    let clock = DayClock(wakeMinutes: 6 * 60, bedtimeMinutes: 23 * 60, timeZoneID: "Europe/London")
    let start = GameDay(year: 2026, month: 11, day: 2)
    let cat = "midnight"

    init() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    /// One phone: its own log and who holds it.
    struct Phone {
        var log = SaveLog()
        let actor: GameEvent.Actor

        mutating func add(_ kind: GameEvent.Kind, at date: Date, clock: DayClock) -> GameEvent {
            let at = log.timestamp(for: date)
            let event = GameEvent(at: at, day: clock.day(of: at), actor: actor, kind: kind)
            log.append(event)
            return event
        }

        /// Takes in what the other phone has (CloudKit's shared zone, in the app).
        mutating func sync(with other: Phone) {
            log.merge(other.log.events.shuffled())
        }
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        clock.date(on: start.advanced(by: day), atLocalMinutes: hour * 60 + minute)
    }

    @Test func twoPhonesCoOwnOneCatForThreeDaysWithoutAConflict() {
        var owner = Phone(actor: .owner)
        var partner = Phone(actor: .coOwner("sam"))
        _ = owner.add(.householdCreated(seed: 0x5EED, clock: clock), at: at(0, 7), clock: clock)
        _ = owner.add(.catAdopted(catID: cat, name: "Pip", personality: .velcro, isKitten: false), at: at(0, 7, 1), clock: clock)
        _ = owner.add(.itemGranted(itemID: "living_sofa"), at: at(0, 7, 2), clock: clock)
        _ = owner.add(.itemGranted(itemID: "living_armchair"), at: at(0, 7, 2), clock: clock)
        // The invite: the partner's phone takes in the household.
        partner.sync(with: owner)

        // Day 0, both offline: each feeds (only one is breakfast), both pet, both buy with the same Beans,
        // both rename the cat, and each puts a piece in the same corner of the living room.
        _ = owner.add(.arrived, at: at(0, 8), clock: clock)
        _ = owner.add(.fed(catID: cat), at: at(0, 8, 5), clock: clock)
        _ = partner.add(.arrived, at: at(0, 8, 30), clock: clock)
        _ = partner.add(.fed(catID: cat), at: at(0, 8, 31), clock: clock)
        _ = partner.add(.petted(catID: cat), at: at(0, 8, 32), clock: clock)
        let beans = SaveLog(snapshot: nil, events: owner.log.events).derive(context: context).beans
        _ = owner.add(.itemBought(itemID: "living_lamp", beans: beans - 10), at: at(0, 9), clock: clock)
        _ = partner.add(.itemBought(itemID: "living_bookcase", beans: beans - 20), at: at(0, 9, 1), clock: clock)
        _ = owner.add(.catRenamed(catID: cat, name: "Pip"), at: at(0, 10), clock: clock)
        _ = partner.add(.catRenamed(catID: cat, name: "Pepper"), at: at(0, 10, 1), clock: clock)
        _ = owner.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 1, y: 1, facing: .right), at: at(0, 11), clock: clock)
        _ = partner.add(.itemPlaced(itemID: "living_armchair", room: .living, x: 1, y: 1, facing: .right), at: at(0, 11, 1), clock: clock)

        // Evening: they sync, one way and then the other.
        partner.sync(with: owner)
        owner.sync(with: partner)

        // Day 1: only the partner visits (the household's streak keeps). Day 2: both, each before syncing.
        _ = partner.add(.arrived, at: at(1, 18), clock: clock)
        _ = partner.add(.fed(catID: cat), at: at(1, 18, 1), clock: clock)
        _ = owner.add(.arrived, at: at(2, 7), clock: clock)
        _ = partner.add(.petted(catID: cat), at: at(2, 7, 30), clock: clock)
        _ = owner.add(.fed(catID: cat), at: at(2, 8), clock: clock)
        owner.sync(with: partner)
        partner.sync(with: owner)

        let a = owner.log.derive(through: start.advanced(by: 3), context: context)
        let b = partner.log.derive(through: start.advanced(by: 3), context: context)

        // The same household on both phones.
        #expect(a == b)
        #expect(owner.log.events.map(\.id) == partner.log.events.map(\.id))
        #expect(Set(owner.log.events.map(\.id)).count == owner.log.events.count) // nothing doubled
        // Every day had a visit from someone: a three-day streak.
        #expect(a.streak.current == 3)
        // Breakfast counted once a day: trust from three fed days, not five feeds.
        #expect(a.cats.first?.careDays == 3)
        // One purchase fitted the Beans; the other was refused, never spent twice.
        #expect(a.beans >= 0)
        #expect((a.owned["living_lamp"] ?? 0) + (a.owned["living_bookcase"] ?? 0) == 1)
        // The later rename wins, everywhere.
        #expect(a.cats.first?.name == "Pepper")
        // Only one piece stands in that corner; the other is still in the inventory.
        let corner = a.placed.filter { $0.room == .living && $0.x == 1 && $0.y == 1 }
        #expect(corner.count == 1)
        #expect(a.unplaced().values.reduce(0, +) >= 1)
        let pieces = a.placed.filter { $0.room == .living }.compactMap(context.piece)
        for piece in pieces {
            #expect(PlacementRules.fits(piece, among: pieces), "overlap at \(piece.x),\(piece.y)")
        }
    }

    @Test func aPhoneThatWasOfflineForDaysCatchesUpToTheSameHousehold() {
        var owner = Phone(actor: .owner)
        var partner = Phone(actor: .coOwner("sam"))
        _ = owner.add(.householdCreated(seed: 1, clock: clock), at: at(0, 7), clock: clock)
        _ = owner.add(.catAdopted(catID: cat, name: "Pip", personality: .aloof, isKitten: false), at: at(0, 7, 1), clock: clock)
        partner.sync(with: owner)
        for day in 0 ..< 3 {
            _ = owner.add(.arrived, at: at(day, 8), clock: clock)
            _ = owner.add(.fed(catID: cat), at: at(day, 8, 1), clock: clock)
        }
        // The partner was away and acted on an old picture of the house: a visit on day 1 and a pet.
        _ = partner.add(.arrived, at: at(1, 20), clock: clock)
        _ = partner.add(.petted(catID: cat), at: at(1, 20, 1), clock: clock)
        partner.sync(with: owner)
        owner.sync(with: partner)
        let a = owner.log.derive(through: start.advanced(by: 3), context: context)
        let b = partner.log.derive(through: start.advanced(by: 3), context: context)
        #expect(a == b)
        #expect(a.streak.current == 3)
        #expect(owner.log.events.filter { $0.actor == .coOwner("sam") }.count == 2)
    }
}
