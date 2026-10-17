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

    @Test func aNewSaveSeedsMidnightAndTheDemoRoom() {
        let state = session.state(at: session.now())
        #expect(state.cat(GameSession.catID)?.name == "Midnight")
        #expect(state.placed.contains { $0.itemID == "living_sofa" && $0.room == .living })
        #expect(session.inventory().map(\.id).sorted() == ["living_armchair", "living_coffee"])
    }

    @Test func theFirstArrivalIsRecordedAndGreetsAsTheFirstEver() {
        let arrival = session.arrive()
        #expect(session.log.events.contains { $0.kind == .arrived })
        #expect(arrival.greeting?.isEmpty == false)
        // Not fed yet today: the behaviour table sends the cat to the bowl.
        #expect(arrival.mood == .hungry)
        #expect(arrival.choice.activity == .bowlNag)
    }

    @Test func aSecondBowlIsFull() {
        _ = session.arrive()
        let first = session.feed()
        let second = session.feed()
        #expect(first != nil && second != nil)
        #expect(session.state(at: session.now()).isFedToday(GameSession.catID))
    }

    @Test func aPieceFromTheInventoryIsPlacedAndMovesAreRecorded() throws {
        let placement = try #require(session.placeFromInventory("living_armchair", among: []))
        let id = try #require(placement.placementID)
        #expect(session.inventory().map(\.id) == ["living_coffee"])
        session.record(.moved(placementID: id, x: 1, y: 1, facing: .left))
        let moved = session.state(at: session.now()).placed.first { $0.placementID == id }
        #expect(moved?.x == 1 && moved?.facing == .left)
        session.record(.stored(placementID: id))
        #expect(session.inventory().map(\.id).sorted() == ["living_armchair", "living_coffee"])
    }
}
