import Foundation

/// The player's save: an optional snapshot plus every event since it.
/// Append-only; devices merge by event id and never conflict. Compaction folds
/// old events into the snapshot so the log stays small.
public struct SaveLog: Codable, Equatable, Sendable {
    /// State folded through the day before `snapshot.today.day`.
    public private(set) var snapshot: HouseholdState?
    /// Events after the snapshot, in log order, unique by id.
    public private(set) var events: [GameEvent]

    public init(snapshot: HouseholdState? = nil, events: [GameEvent] = []) {
        self.snapshot = snapshot
        self.events = []
        merge(events)
    }

    /// The first day not folded into the snapshot.
    public var snapshotBoundary: GameDay? {
        snapshot?.today?.day
    }

    /// The timestamp for a new event at game time `date`: always after the
    /// newest event, so events appended in quick succession (or while game
    /// time is paused) keep the order they happened in.
    public func timestamp(for date: Date) -> Date {
        let newest = events.map(\.at).max() ?? snapshot?.lastEventAt
        guard let newest, date <= newest else { return date }
        return newest.addingTimeInterval(0.001)
    }

    /// Adds a new event. Returns false if an event with the same id is already in the log.
    @discardableResult
    public mutating func append(_ event: GameEvent) -> Bool {
        guard !events.contains(where: { $0.id == event.id }) else { return false }
        let index = events.firstIndex { GameEvent.logOrder(event, $0) } ?? events.endIndex
        events.insert(event, at: index)
        return true
    }

    /// Merges events from another device (or the iCloud copy). Idempotent and
    /// order-independent: any devices holding the same events derive the same state.
    public mutating func merge(_ incoming: [GameEvent]) {
        var seen = Set(events.map(\.id))
        for event in incoming where !seen.contains(event.id) {
            seen.insert(event.id)
            events.append(event)
        }
        events.sort(by: GameEvent.logOrder)
    }

    /// The derived state through the last event (the last event's day is open).
    public func derive(context: RulesContext) -> HouseholdState {
        var state = snapshot ?? HouseholdState()
        for event in events {
            state.apply(event, context: context)
        }
        return state
    }

    /// The derived state with every day before `day` closed: what screens and
    /// widgets read for "now".
    public func derive(through day: GameDay, context: RulesContext) -> HouseholdState {
        derive(context: context).resolved(through: day, context: context)
    }

    /// Folds every event before `boundary` into the snapshot. Deterministic, so
    /// devices holding the same events produce the same snapshot. Events from
    /// before an existing snapshot that arrive late are folded onto its open day.
    /// `boundary` must not be after today (use `compactionBoundary(today:)`).
    public func compacted(before boundary: GameDay, context: RulesContext) -> SaveLog {
        if let existing = snapshotBoundary, boundary <= existing {
            return self
        }
        let old = events.filter { $0.day < boundary }
        let recent = events.filter { $0.day >= boundary }
        guard !old.isEmpty || snapshot != nil else { return self }
        var state = snapshot ?? HouseholdState()
        for event in old {
            state.apply(event, context: context)
        }
        state.advance(to: boundary, context: context)
        return SaveLog(snapshot: state, events: recent)
    }

    /// The compaction boundary for "now": events older than the horizon are folded.
    public static func compactionBoundary(today: GameDay) -> GameDay {
        today.advanced(by: -Tuning.Save.compactionHorizonDays)
    }
}
