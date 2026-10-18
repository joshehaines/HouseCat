import Foundation
@testable import HouseCatCore
import Testing

private let day = GameDay(year: 2026, month: 11, day: 2)

private func rng(_ salt: String) -> DaySeed {
    DaySeed(household: 7, day: day, purpose: "brain", salt: salt)
}

private let furnished: [RoomID: Set<Affordance>] = [
    .living: [.sit, .sleep, .scratch, .perch],
    .bedroom: [.sleep, .perch, .hide],
    .kitchen: [.eat, .perch, .sit],
    .garden: [.watch, .sit, .sleep],
    .study: [.perch, .sit, .hide],
    .attic: [.hide, .sleep, .perch],
]

@Test func theCatOnlyGoesToOpenRooms() {
    let offers: [RoomID: Set<Affordance>] = [.living: [.sit], .bedroom: [.sleep]]
    for i in 0 ..< 50 {
        var r = rng("open\(i)")
        let room = RoomChoice.room(for: .sleep, current: .living, viewing: .living, offers: offers, timeOfDay: .night, rng: &r)
        #expect(room == .bedroom)
        var s = rng("watch\(i)")
        // Nothing to watch from anywhere: it stays where it is.
        #expect(RoomChoice
            .room(for: .windowWatch, current: .living, viewing: .living, offers: offers, timeOfDay: .midday, rng: &s) == .living)
        var t = rng("closed\(i)")
        // A room it is in that has since closed (never happens in the save) falls back to the living room.
        #expect(RoomChoice.room(for: .floorLoaf, current: .attic, viewing: .living, offers: offers, timeOfDay: .midday, rng: &t) == .living)
    }
}

@Test func eachRoomTypeIsForSomething() {
    var counts: [RoomID: Int] = [:]
    for i in 0 ..< 200 {
        var r = rng("night\(i)")
        counts[
            RoomChoice.room(for: .sleep, current: .living, viewing: .living, offers: furnished, timeOfDay: .night, rng: &r),
            default: 0
        ] +=
            1
    }
    // The bed at night most of the time, but not always.
    #expect(counts[.bedroom, default: 0] > 120)
    #expect(counts.count > 1)
    var eat = rng("eat")
    #expect(RoomChoice.room(for: .bowlNag, current: .study, viewing: .living, offers: furnished, timeOfDay: .evening, rng: &eat) != .study)
}

@Test func nearYouIsTheRoomYouAreLookingAt() {
    var r = rng("near")
    #expect(RoomChoice
        .room(for: .nearPlayer, current: .bedroom, viewing: .kitchen, offers: furnished, timeOfDay: .evening, rng: &r) == .kitchen)
    var s = rng("near2")
    #expect(RoomChoice.room(for: .sulk, current: .bedroom, viewing: .kitchen, offers: furnished, timeOfDay: .evening, rng: &s) == .bedroom)
}

@Test func theCatOftenStaysWhereItIs() {
    var stays = 0
    for i in 0 ..< 200 {
        var r = rng("stay\(i)")
        if RoomChoice.room(for: .perch, current: .attic, viewing: .living, offers: furnished, timeOfDay: .evening, rng: &r) == .attic {
            stays += 1
        }
    }
    #expect(stays > 80)
    #expect(stays < 200)
}

@Test func offersComeFromTheFurnitureInEachOpenRoom() {
    var fixture = Fixture()
    fixture.add(.itemGranted(itemID: "living_sofa"), day: 0)
    fixture.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 1, y: 1, facing: .right), day: 0)
    let offers = RoomChoice.offers(in: fixture.state, catalogue: ["living_sofa": [.sit, .sleep]])
    #expect(offers[.living] == [.sit, .sleep])
    #expect(offers[.bedroom] == nil)
}

@Test func theBeanShopListsTheRoomsOwnPiecesFirst() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let catalogue = try ContentBundle.load(from: repo.appendingPathComponent("Content")).catalogue
    for room in RoomID.allCases {
        let stock = BeanShop.stock(for: room, catalogue: catalogue)
        #expect(!stock.isEmpty)
        // One currency: the Bean catalogue and the looks' pieces one at a time.
        #expect(stock.allSatisfy { ($0.pool == .beans && $0.beans != nil) || $0.pool == .set })
        let own = stock.prefix { $0.room == room.rawValue }
        #expect(!own.isEmpty, "\(room) has Bean pieces of its own")
        #expect(own.map(BeanPrices.piece) == own.map(BeanPrices.piece).sorted())
    }
    let bed = try #require(catalogue.items.first { $0.id == "bedroom_bed" })
    #expect(BeanShop.status(of: bed, level: 1, beans: 500) == (bed.level > 1 ? .needsLevel(bed.level) : .buyable(price: bed.beans ?? 0)))
    #expect(BeanShop.status(of: bed, level: 20, beans: 0) == .needsBeans(price: bed.beans ?? 0))
}
