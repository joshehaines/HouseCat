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
        return Arrival(greeting: greeting, choice: BehaviourTable.choose(context, rng: &brain), mood: mood)
    }

    // MARK: The demo household

    /// Until onboarding exists: a household with Midnight, the free living-room furniture of the demo
    /// layout granted and placed (cells rounded from the layout's hand-tuned positions).
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
    }
}
