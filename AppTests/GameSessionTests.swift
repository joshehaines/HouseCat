import CoreGraphics
import Foundation
@testable import HouseCat
import HouseCatCore
import HouseCatGame
import HouseCatModels
import Testing

/// The app's save glue against an in-memory store, inside the app (it needs the bundled art and content).
@MainActor
@Suite("Game session")
struct GameSessionTests {
    let session: GameSession

    init() throws {
        session = try GameSession(store: EventStore(inMemory: true))
    }

    /// The player's cat from the builder: a calico called Pip.
    private func adopt() throws {
        let look = try #require(GameWorld.catArt?.builder.preset("calico")).look
        session.adopt(name: "Pip", personality: .velcro, look: look)
    }

    @Test func aNewHomeStartsEmptyWithTheStarterPieceAndWaitsForTheBuilder() {
        let state = session.state(at: session.now())
        #expect(session.cat == nil)
        // Only the bowl and the moving box (Josh, 19 Oct: the player should want to decorate).
        #expect(Set(state.placed.map(\.itemID)) == Tuning.Room.firstHome)
        #expect(state.placed.allSatisfy { $0.room == .living })
        #expect(session.inventory().map(\.id) == Tuning.Room.starterPieces)
    }

    @Test func adoptionRecordsTheNameThePersonalityAndTheLook() throws {
        try adopt()
        let cat = try #require(session.cat)
        #expect(cat.name == "Pip")
        #expect(cat.personality == .velcro)
        #expect(cat.look.pattern == "tortie")
        #expect(cat.look.white == "white_bicolour")
        // Every field can be changed again from the profile.
        var look = cat.look
        look.eyeLeft = .named("blue")
        session.edit(name: "Pippin", personality: .loaf, look: look)
        #expect(session.cat?.name == "Pippin")
        #expect(session.cat?.personality == .loaf)
        #expect(session.cat?.look.eyeLeft == .named("blue"))
    }

    @Test func theProfileAndTheBookComeFromTheSave() throws {
        try adopt()
        let state = session.state(at: session.now())
        let profile = try #require(state.profile(of: GameSession.catID, on: state.clock.day(of: session.now())))
        #expect(profile.togetherDays == 0)
        #expect(profile.name == "Pip")
        #expect(CatScreens.portrait(profile.look) != nil)
        #expect(CatScreens.book().count == session.content?.gifts.gifts.count)
    }

    @Test func theHomeIsPlacedThenMovedAndTheHouseFollowsIt() throws {
        try adopt()
        let lisbon = HomePlace(name: "Lisbon", latitude: 38.72, longitude: -9.14, timeZoneID: "Europe/Lisbon", biome: .city)
        session.placeHome(lisbon, season: .auto)
        var state = session.state(at: session.now())
        #expect(state.home.place == lisbon)
        let desert = HomePlace(name: "Djado", latitude: 21, longitude: 12.3, timeZoneID: "Africa/Niamey", biome: .desert)
        session.placeHome(desert, season: .fixed(.summer))
        state = session.state(at: session.now())
        #expect(state.home.place == desert, "the free move")
        #expect(state.home.season == .fixed(.summer))
        let house = try #require(GameWorld.house(at: session.now(), state: state))
        let windows = house.rooms.compactMap { $0.model.window == nil ? nil : $0.model.terrain }
        #expect(!windows.isEmpty && windows.allSatisfy { $0 == "world/terrain/terr_desert_summer.png" })
        #expect(GameWorld.exteriorScene(size: CGSize(width: 1024, height: 768), at: session.now(), state: state) != nil)
    }

    @Test func theFirstArrivalIsRecordedAndGreetsAsTheFirstEver() throws {
        try adopt()
        let arrival = session.arrive()
        #expect(session.log.events.contains { $0.kind == .arrived })
        #expect(arrival.greeting?.isEmpty == false)
        // Not fed yet today: the behaviour table sends the cat to the bowl.
        #expect(arrival.mood == .hungry)
        #expect(arrival.choice.activity == .bowlNag)
    }

    @Test func aSecondBowlIsFull() throws {
        try adopt()
        _ = session.arrive()
        let first = session.feed()
        let second = session.feed()
        #expect(first != nil && second != nil)
        #expect(session.state(at: session.now()).isFedToday(GameSession.catID))
    }

    @Test func aPieceFromTheInventoryIsPlacedAndMovesAreRecorded() throws {
        let starter = try #require(Tuning.Room.starterPieces.first)
        let placement = try #require(session.placeFromInventory(starter, among: []))
        let id = try #require(placement.placementID)
        #expect(session.inventory().isEmpty)
        session.record(.moved(placementID: id, x: 1, y: 1, facing: .left))
        let moved = session.state(at: session.now()).placed.first { $0.placementID == id }
        #expect(moved?.x == 1 && moved?.facing == .left)
        session.record(.stored(placementID: id))
        #expect(session.inventory().map(\.id) == [starter])
    }
}
