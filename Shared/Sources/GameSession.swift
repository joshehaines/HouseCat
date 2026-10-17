import Foundation
import HouseCatCore
import HouseCatGame
import HouseCatModels

/// The player's save on this device: the append-only event log in SwiftData, read through
/// HouseCatCore. Scenes get what they need from here and never compute rules themselves.
@MainActor
final class GameSession {
    static let shared = GameSession()

    /// The mascot until onboarding adopts the player's own cat.
    static let catID = "midnight"

    let content: ContentBundle?
    private let rules: RulesContext
    private let store: EventStore?
    private(set) var log: SaveLog

    private init() {
        content = GameWorld.content
        rules = (try? content?.rulesContext()) ?? RulesContext()
        // In the App Group when the app is entitled to it (the widget reads the same save), else in the app's container.
        store = (try? EventStore()) ?? (try? EventStore(inMemory: true))
        log = (try? store?.load()) ?? SaveLog()
        if log.events.isEmpty, log.snapshot == nil {
            seedDemoHousehold()
        }
    }

    // MARK: Time and state

    /// Game time now (CLAUDE.md "Clock rules"): never before the newest event, so a clock set back is ignored.
    func now() -> Date {
        TrustedTime.now(
            wall: Date(),
            uptime: ProcessInfo.processInfo.systemUptime,
            bootID: Self.bootID,
            anchor: nil,
            lastGameTime: log.events.last?.at ?? log.snapshot?.lastEventAt
        ).date
    }

    /// The state with every day before `date`'s game day closed.
    func state(at date: Date) -> HouseholdState {
        let clock = log.derive(context: rules).clock
        return log.derive(through: clock.day(of: date), context: rules)
    }

    @discardableResult
    func append(_ kind: GameEvent.Kind, at date: Date, source: GameEvent.Source = .app) -> GameEvent {
        let at = log.timestamp(for: date)
        let clock = log.derive(context: rules).clock
        let event = GameEvent(at: at, day: clock.day(of: at), source: source, kind: kind)
        log.append(event)
        try? store?.append(event)
        return event
    }

    private static let bootID: String = {
        var size = 0
        sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }()

    // MARK: The arrival

    /// What an arrival does: the greeting line chosen from the state before it, the `arrived` event,
    /// then the cat's next activity from the behaviour table with the mood that follows.
    struct Arrival {
        var greeting: String?
        /// The meow that goes with the greeting (its line pack's `meow`).
        var meow: LinesFile.Line.Meow?
        var choice: BehaviourChoice
        var mood: Mood
    }

    func arrive(weather: Weather = .sun) -> Arrival {
        let date = now()
        let before = state(at: date)
        let cat = before.cat(Self.catID)
        let greetingContext = Greeting.context(before: before, at: date)
        append(.arrived, at: date)
        let after = state(at: date)
        let day = after.clock.day(of: date)
        let mood = after.mood(of: Self.catID, at: date)
        let sky = GameWorld.skyPhase(at: date)
        let context = BehaviourContext(
            mood: mood,
            weather: weather,
            personality: cat?.personality ?? .velcro,
            timeOfDay: TimeOfDay.at(localMinutes: after.clock.localMinutes(of: date), clock: after.clock),
            available: after.affordances(in: .living, catalogue: content?.affordances ?? [:]),
            sunlit: sky == .day && weather.isSunny
        )
        let visits = after.lifetime.visits
        var brain = DaySeed(household: after.seed, day: day, purpose: "brain", salt: "arrival\(visits)-\(log.events.count)")
        var words = DaySeed(household: after.seed, day: day, purpose: "greeting", salt: greetingContext)
        let greeting = cat.flatMap { cat in content.flatMap { Greeting.line(greetingContext, cat: cat, lines: $0.lines, rng: &words) } }
        let meow = cat
            .flatMap { cat in content?.lines.lines.first { $0.context == greetingContext && $0.personality == cat.personality }?.meow }
        return Arrival(greeting: greeting, meow: meow, choice: BehaviourTable.choose(context, rng: &brain), mood: mood)
    }

    /// The cat's next activity while you watch (no event: activities are not game state). Same rule as the
    /// arrival, drawn afresh each time so it wanders.
    func nextActivity(weather: Weather = .sun) -> BehaviourChoice? {
        let date = now()
        let state = state(at: date)
        guard let cat = state.cat(Self.catID) else { return nil }
        let sky = GameWorld.skyPhase(at: date)
        let context = BehaviourContext(
            mood: state.mood(of: Self.catID, at: date),
            weather: weather,
            personality: cat.personality,
            timeOfDay: TimeOfDay.at(localMinutes: state.clock.localMinutes(of: date), clock: state.clock),
            available: state.affordances(in: .living, catalogue: content?.affordances ?? [:]),
            sunlit: sky == .day && weather.isSunny
        )
        var rng = DaySeed(
            household: state.seed,
            day: state.clock.day(of: date),
            purpose: "brain",
            salt: "idle\(Int(date.timeIntervalSince1970))"
        )
        return BehaviourTable.choose(context, rng: &rng)
    }

    // MARK: Care

    /// Feed (once a day; again gets "full"): the line from the state before, then the `fed` event.
    func feed() -> String? {
        let date = now()
        let before = state(at: date)
        let context = CareLines.feed(before: before, catID: Self.catID)
        append(.fed(catID: Self.catID), at: date)
        return line(context, before: before, date: date)
    }

    /// A pet; `taps` counts pets in a row. Returns the line (if any) and whether the cat walks off.
    func pet(taps: Int) -> (line: String?, walksOff: Bool) {
        let date = now()
        let before = state(at: date)
        let context = CareLines.pet(before: before, catID: Self.catID, taps: taps)
        append(.petted(catID: Self.catID), at: date)
        // Only the first pet of the day and the last straw get a line; the rest are purrs.
        let speaks = context != "pet.repeat"
        return (speaks ? line(context, before: before, date: date) : nil, context == "pet.too_many")
    }

    private func line(_ context: String, before state: HouseholdState, date: Date) -> String? {
        guard let cat = state.cat(Self.catID), let content else { return nil }
        var rng = DaySeed(household: state.seed, day: state.clock.day(of: date), purpose: "line", salt: "\(context)\(log.events.count)")
        return Greeting.line(context, cat: cat, lines: content.lines, rng: &rng)
    }

    // MARK: Inventory

    /// A piece the player owns but has not placed.
    struct InventoryEntry: Identifiable, Equatable {
        var id: String
        var name: String
        var count: Int
        var sprite: String
    }

    func inventory() -> [InventoryEntry] {
        guard let content else { return [] }
        let items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        // Paid pieces join the inventory from the player's entitlements once the store is wired to the save;
        // `rules.paidItems` is every paid piece in the catalogue, not what this player bought.
        return state(at: now()).unplaced().compactMap { id, count in
            guard let item = items[id], let sprite = item.sprites["R"] ?? item.sprites.values.first else { return nil }
            return InventoryEntry(id: id, name: item.name, count: count, sprite: sprite)
        }.sorted { $0.name < $1.name }
    }

    /// Places a piece from the inventory where it first fits among the room's pieces; returns the placement (with
    /// the event's id) for the scene, or nil if the room is full.
    func placeFromInventory(_ itemID: String, among pieces: [PlacementRules.Piece], room: RoomID = .living) -> RoomModel.Placement? {
        guard let item = content?.catalogue.items.first(where: { $0.id == itemID }) else { return nil }
        let fresh = PlacementRules.Piece(item, x: 0, y: 0, facing: .right)
        guard let spot = PlacementRules.firstFit(fresh, among: pieces) else { return nil }
        let event = append(.itemPlaced(itemID: itemID, room: room, x: spot.x, y: spot.y, facing: spot.facing), at: now())
        Sound.play("ui_place_item", volume: Tuning.Sound.place)
        return RoomModel.Placement(id: itemID, u: Double(spot.x), v: Double(spot.y), facing: spot.facing.rawValue, placementID: event.id)
    }

    // MARK: Decorating

    /// Records a change made in decorate mode (the scene already checked it with PlacementRules).
    func record(_ change: RoomScene.DecorateChange, in room: RoomID = .living) {
        switch change {
        case let .moved(placementID, x, y, facing):
            Sound.play("ui_place_item", volume: Tuning.Sound.place)
            append(.itemMoved(placementID: placementID, room: room, x: x, y: y, facing: facing), at: now())
        case let .stored(placementID):
            append(.itemStored(placementID: placementID), at: now())
        }
    }

    // MARK: The demo household

    /// Until onboarding exists: a household with Midnight, the free living-room furniture of the demo
    /// layout granted and placed (cells rounded from the layout's hand-tuned positions), and two more in the inventory.
    private func seedDemoHousehold() {
        let date = Date()
        append(.householdCreated(seed: UInt64.random(in: 1 ... UInt64.max), clock: DayClock()), at: date)
        append(.catAdopted(catID: Self.catID, name: "Midnight", personality: .velcro, isKitten: false), at: date)
        guard let art = GameWorld.art, let layout = try? art.data("rooms/layout_living_demo.json", as: RoomModel.self) else { return }
        for item in layout.items {
            append(.itemGranted(itemID: item.id), at: date)
            let facing: GameEvent.Facing = item.facing == "L" ? .left : .right
            append(
                .itemPlaced(itemID: item.id, room: .living, x: Int(item.u.rounded()), y: Int(item.v.rounded()), facing: facing),
                at: date
            )
        }
        // Two pieces in the inventory, so Decorate has something to put out.
        for spare in ["living_armchair", "living_coffee"] {
            append(.itemGranted(itemID: spare), at: date)
        }
    }
}
