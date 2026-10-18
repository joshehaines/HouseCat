import Foundation
import HouseCatCore
import SwiftData

/// One event of the append-only save, stored as JSON. Every attribute has a
/// default and nothing is unique, as CloudKit mirroring requires; duplicates
/// that sync in from other devices are dropped when the log is loaded.
@Model
public final class StoredEvent {
    public var eventID = UUID()
    public var at = Date.distantPast
    public var dayIndex = 0
    public var payload = Data()

    public init(_ event: GameEvent) throws {
        eventID = event.id
        at = event.at
        dayIndex = event.day.index
        payload = try JSONEncoder().encode(event)
    }

    public func decoded() throws -> GameEvent {
        try JSONDecoder().decode(GameEvent.self, from: payload)
    }
}

/// The compaction snapshot: the derived state through `boundaryDay`, a cache over the events (which are
/// never deleted): one of another `version`, or one that no longer decodes, is passed over.
@Model
public final class StoredSnapshot {
    public var boundaryDay = 0
    public var version = 0
    public var payload = Data()

    public init(boundaryDay: GameDay, state: HouseholdState) throws {
        self.boundaryDay = boundaryDay.index
        version = Tuning.Save.snapshotVersion
        payload = try JSONEncoder().encode(state)
    }

    public func decoded() throws -> HouseholdState {
        try JSONDecoder().decode(HouseholdState.self, from: payload)
    }
}

/// Reads and writes the player's own save in SwiftData. Holds no rules: the
/// state is always `SaveLog.derive` over what is stored.
@MainActor
public final class EventStore {
    public static let appGroup = "group.com.housecatgame.housecat"
    public static let cloudKitContainer = "iCloud.com.housecatgame.housecat"

    public let container: ModelContainer
    private var context: ModelContext {
        container.mainContext
    }

    /// - Parameters:
    ///   - inMemory: for tests and previews.
    ///   - sharedWithWidgets: store in the App Group so the widget reads the same save (when the app is
    ///     entitled to it; otherwise the app's own container).
    ///   - cloudKit: mirror to the CloudKit private database (needs the iCloud entitlement).
    public init(inMemory: Bool = false, sharedWithWidgets: Bool = true, cloudKit: Bool = false) throws {
        let schema = Schema([StoredEvent.self, StoredSnapshot.self])
        // SwiftData traps (rather than throws) on an App Group the app is not entitled to, so check it exists first.
        let group = sharedWithWidgets && !inMemory
            && FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) != nil
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: group ? .identifier(Self.appGroup) : .none,
            cloudKitDatabase: cloudKit ? .private(Self.cloudKitContainer) : .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Appends one event and saves.
    public func append(_ event: GameEvent) throws {
        try context.insert(StoredEvent(event))
        try context.save()
    }

    /// Many events in one save (seeding a household).
    public func append(contentsOf events: [GameEvent]) throws {
        for event in events {
            try context.insert(StoredEvent(event))
        }
        try context.save()
    }

    /// The whole save as a log: the newest usable snapshot plus every event after it, or every event when
    /// there is no snapshot of this build's shape. An event that no longer decodes is skipped, not fatal.
    public func load() throws -> SaveLog {
        let snapshots = try context.fetch(FetchDescriptor<StoredSnapshot>(sortBy: [SortDescriptor(\.boundaryDay, order: .reverse)]))
        let usable = snapshots.first { $0.version == Tuning.Save.snapshotVersion }
        let snapshot = try? usable?.decoded()
        let boundary = snapshot == nil ? Int.min : usable?.boundaryDay ?? Int.min
        let stored = try context.fetch(FetchDescriptor<StoredEvent>(predicate: #Predicate { $0.dayIndex >= boundary }))
        return SaveLog(snapshot: snapshot, events: stored.compactMap { try? $0.decoded() })
    }

    /// Removes every event and snapshot ("Delete all my data"). With CloudKit mirroring on, the deletions are
    /// mirrored too.
    public func deleteEverything() throws {
        // One by one: a batch delete leaves rows behind in a store shared through the App Group.
        for event in try context.fetch(FetchDescriptor<StoredEvent>()) {
            context.delete(event)
        }
        for snapshot in try context.fetch(FetchDescriptor<StoredSnapshot>()) {
            context.delete(snapshot)
        }
        try context.save()
    }

    /// Folds events older than the horizon into a snapshot, so loading folds only the recent ones. The events
    /// stay: the snapshot is a cache, rebuilt from them whenever the state's shape changes.
    public func compact(today: GameDay, context rules: RulesContext) throws {
        let boundary = SaveLog.compactionBoundary(today: today)
        let log = try load()
        let compacted = log.compacted(before: boundary, context: rules)
        guard let snapshot = compacted.snapshot, compacted.snapshotBoundary != log.snapshotBoundary else { return }
        try context.delete(model: StoredSnapshot.self)
        try context.insert(StoredSnapshot(boundaryDay: boundary, state: snapshot))
        try context.save()
    }
}
