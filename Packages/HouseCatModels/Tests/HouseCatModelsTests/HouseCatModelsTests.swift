import Foundation
import HouseCatCore
@testable import HouseCatModels
import Testing

@MainActor
@Suite("SwiftData event store")
struct EventStoreTests {
    let clock = DayClock()
    let start = GameDay(year: 2026, month: 11, day: 2)

    func event(_ kind: GameEvent.Kind, day offset: Int, hour: Int) -> GameEvent {
        let date = clock.date(on: start.advanced(by: offset), atLocalMinutes: hour * 60)
        return GameEvent(at: date, day: clock.day(of: date), kind: kind)
    }

    func history() -> [GameEvent] {
        var events = [
            event(.householdCreated(seed: 77, clock: clock), day: 0, hour: 7),
            event(.catAdopted(catID: "pip", name: "Pip", personality: .gremlin, isKitten: true), day: 0, hour: 7),
        ]
        for day in 0 ..< 45 where day % 9 != 4 {
            events.append(event(.arrived, day: day, hour: 8))
            events.append(event(.fed(catID: "pip"), day: day, hour: 9))
        }
        return events
    }

    @Test func eventsRoundTripThroughSwiftData() throws {
        let store = try EventStore(inMemory: true)
        let events = history()
        for event in events {
            try store.append(event)
        }
        let loaded = try store.load()
        #expect(loaded == SaveLog(events: events))
        #expect(loaded.derive(context: .empty).cat("pip")?.careDays == 40)
    }

    @Test func duplicatesSyncedFromAnotherDeviceAreDropped() throws {
        let store = try EventStore(inMemory: true)
        let events = history()
        for event in events + events.prefix(10) {
            try store.append(event)
        }
        #expect(try store.load().events.count == events.count)
    }

    @Test func compactionStoresASnapshotAndKeepsTheState() throws {
        let store = try EventStore(inMemory: true)
        for event in history() {
            try store.append(event)
        }
        let today = start.advanced(by: 45)
        let before = try store.load().derive(through: today, context: .empty)
        try store.compact(today: today, context: .empty)
        let after = try store.load()
        #expect(after.snapshotBoundary == SaveLog.compactionBoundary(today: today))
        #expect(after.events.allSatisfy { $0.day >= SaveLog.compactionBoundary(today: today) })
        #expect(after.derive(through: today, context: .empty) == before)
    }
}
