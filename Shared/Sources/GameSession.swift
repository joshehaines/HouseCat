import Foundation
import HouseCatCore
import HouseCatGame
import HouseCatModels

/// The player's save on this device: the append-only event log in SwiftData, read through
/// HouseCatCore. Scenes get what they need from here and never compute rules themselves.
@MainActor
final class GameSession {
    static let shared = GameSession()

    /// The player's first cat (the id the save has used since the mascot was the only cat).
    static let catID = "midnight"

    let content: ContentBundle?
    let rules: RulesContext
    private let store: EventStore?
    private(set) var log: SaveLog {
        didSet {
            // Events normally land at the end of the log: fold just those onto what is cached. Anything
            // else (a late event from another device) refolds from the start next time.
            if let cached = folded, log.events.count > cached.count, log.snapshot == oldValue.snapshot,
               log.events.prefix(cached.count).last?.id == oldValue.events.prefix(cached.count).last?.id
            {
                return
            }
            folded = nil
        }
    }

    /// The log folded through its last event, and how many events that took.
    private var folded: (count: Int, state: HouseholdState)?

    /// The derived state through the last event, kept up to date as events are appended (a full refold of a
    /// long save on every read made a sixty-day household slow to use).
    private func fold() -> HouseholdState {
        if let cached = folded, cached.count == log.events.count {
            return cached.state
        }
        var state: HouseholdState
        var start = 0
        if let cached = folded, cached.count < log.events.count {
            state = cached.state
            start = cached.count
        } else {
            state = log.snapshot ?? HouseholdState()
        }
        for event in log.events[start...] {
            state.apply(event, context: rules)
        }
        folded = (log.events.count, state)
        return state
    }

    /// - Parameter store: the save; nil uses the App Group store when the app is entitled to it (the widget
    ///   reads the same save), else the app's container. Tests pass an in-memory store.
    init(store: EventStore? = nil) {
        content = GameWorld.content
        var rules = (try? content?.rulesContext()) ?? RulesContext()
        #if DEBUG
            // HOUSECAT_TRACK_DAY=<n>: the events moved so that today is day n of the gift track (HOUSECAT_TRACK=<id>
            // picks another, e.g. advent_2026).
            let environment = ProcessInfo.processInfo.environment
            if let n = environment["HOUSECAT_TRACK_DAY"].flatMap(Int.init),
               let first = environment["HOUSECAT_TRACK"].flatMap({ id in rules.events.first { $0.id == id } }) ?? rules.events.first
            {
                let today = DayClock().day(of: Date())
                let shift = first.startDay.distance(to: today.advanced(by: -(n - 1)))
                rules.events = rules.events.map { event in
                    var moved = event
                    moved.startDay = event.startDay.advanced(by: shift)
                    moved.endDay = event.endDay.advanced(by: shift)
                    return moved
                }
            }
            // HOUSECAT_PASS_DAY=<n>: the seasons moved so that today is day n of the first one.
            if let n = ProcessInfo.processInfo.environment["HOUSECAT_PASS_DAY"].flatMap(Int.init), let first = rules.seasons.first {
                let today = DayClock().day(of: Date())
                let shift = first.startDay.distance(to: today.advanced(by: -(n - 1)))
                rules.seasons = rules.seasons.map { season in
                    var moved = season
                    moved.startDay = season.startDay.advanced(by: shift)
                    moved.endDay = season.endDay.advanced(by: shift)
                    return moved
                }
            }
        #endif
        self.rules = rules
        var store = store
        #if DEBUG
            // HOUSECAT_FRESH=1: a new player's save in memory, leaving the one on this device alone (shared simulators).
            if store == nil, ProcessInfo.processInfo.environment["HOUSECAT_FRESH"] != nil {
                store = try? EventStore(inMemory: true)
            }
        #endif
        self.store = store ?? (try? EventStore()) ?? (try? EventStore(inMemory: true))
        log = (try? self.store?.load()) ?? SaveLog()
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
        let state = fold()
        return state.resolved(through: state.clock.day(of: date), context: rules)
    }

    /// Where this save's own taps are made (the menu-bar cat's count as Mac visits).
    static let device: GameEvent.Source = {
        #if os(macOS)
            return .mac
        #else
            return .app
        #endif
    }()

    @discardableResult
    func append(_ kind: GameEvent.Kind, at date: Date, source: GameEvent.Source = GameSession.device) -> GameEvent {
        let at = log.timestamp(for: date)
        let clock = fold().clock
        let event = GameEvent(at: at, day: clock.day(of: at), actor: HouseholdSync.actor, source: source, kind: kind)
        log.append(event)
        try? store?.append(event)
        WidgetBridge.changed()
        HouseholdSync.queue(event)
        return event
    }

    /// The derived state through the last event (what the widget is left with).
    var current: HouseholdState {
        fold()
    }

    /// Events made outside the app (the widget's Feed and Pet, Siri's, the Watch's), into the save once each;
    /// `fromCloud` for the other owner's, which CloudKit already has.
    func importEvents(_ events: [GameEvent], fromCloud: Bool = false) {
        let known = Set(log.events.map(\.id))
        let horizon = log.snapshot?.lastEventAt ?? .distantPast
        let new = events.filter { !known.contains($0.id) && $0.at > horizon }
        guard !new.isEmpty else { return }
        log.merge(new)
        try? store?.append(contentsOf: new)
        WidgetBridge.changed()
        // This phone's widget, Siri and Watch taps go up to the co-owner too.
        for event in new where !fromCloud && [.widget, .siri, .watch].contains(event.source) {
            HouseholdSync.queue(event)
        }
    }

    /// One event of the save, by id (what the household's sync sends up).
    func event(_ id: UUID) -> GameEvent? {
        log.events.last { $0.id == id }
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
        /// Where the cat is when you come in (resting where its day put it, in any open room), and how it greets you.
        var start: BehaviourChoice
        var style: GreetingStyle
    }

    func arrive() -> Arrival {
        let date = now()
        let before = state(at: date)
        let cat = before.cat(Self.catID)
        let greetingContext = Greeting.context(before: before, at: date, rules: rules)
        append(.arrived, at: date)
        let after = state(at: date)
        let day = after.clock.day(of: date)
        let mood = after.mood(of: Self.catID, at: date)
        let home = GameWorld.now(state: after, at: date)
        let sky = home.sky, weather = home.weather
        let offers = RoomChoice.offers(in: after, catalogue: content?.affordances ?? [:])
        let time = TimeOfDay.at(localMinutes: after.clock.localMinutes(of: date), clock: after.clock)
        var personality = cat?.personality ?? .velcro, trust = cat?.trust ?? .newcomer
        #if DEBUG
            // Screenshot runs: HOUSECAT_PERSONALITY=loaf and HOUSECAT_TRUST=3 greet as that cat would.
            let environment = ProcessInfo.processInfo.environment
            if let name = environment["HOUSECAT_PERSONALITY"], let chosen = Personality(rawValue: name) {
                personality = chosen
            }
            if let tier = environment["HOUSECAT_TRUST"].flatMap(Int.init).flatMap(TrustTier.init(rawValue:)) {
                trust = tier
            }
        #endif
        let available = offers.values.reduce(into: Set<Affordance>()) { $0.formUnion($1) }
        let identity = cat.map { CatIdentity.of($0, household: after.seed) }
        let context = BehaviourContext(
            mood: mood,
            weather: weather,
            personality: personality,
            timeOfDay: time,
            available: available,
            sunlit: sky == .day && weather.isSunny,
            identity: identity,
            wants: cat.flatMap { cat in identity.map { Wellbeing.of(cat, identity: $0, offers: available, today: after.today).wants } } ?? []
        )
        let visits = after.lifetime.visits
        var brain = DaySeed(household: after.seed, day: day, purpose: "brain", salt: "arrival\(visits)-\(log.events.count)")
        var words = DaySeed(household: after.seed, day: day, purpose: "greeting", salt: greetingContext)
        let greeting = cat.flatMap { cat in content.flatMap { Greeting.line(greetingContext, cat: cat, lines: $0.lines, rng: &words) } }
        let meow = cat
            .flatMap { cat in content?.lines.lines.first { $0.context == greetingContext && $0.personality == cat.personality }?.meow }
        // Where it was resting: anywhere in the house (the first visit ever, in the living room for the tour).
        var rest = DaySeed(household: after.seed, day: day, purpose: "rest", salt: "arrival\(visits)")
        let open = offers.keys.sorted()
        let firstEver = before.lifetime.visits == 0
        let from: RoomID = firstEver || open.isEmpty ? .living : open[rest.below(open.count)]
        var start = RoomChoice.placed(
            BehaviourTable.resting(context, rng: &rest),
            current: from, viewing: from, offers: offers, timeOfDay: time, rng: &rest
        )
        let style = GreetingStyle.style(
            personality: personality,
            trust: trust,
            mood: mood,
            asleep: start.activity == .sleep,
            lateNight: time == .night
        )
        // One that comes to greet you is often waiting on the sofa (always the first time, for the tour), and jumps
        // down to come to you.
        if style == .runs || style == .walks, firstEver || rest.below(100) < Tuning.Arrival.onSofaPercent,
           let seat = [start.room ?? from, .living].first(where: { offers[$0]?.contains(.sit) == true && (!firstEver || $0 == .living) })
        {
            start = BehaviourChoice(activity: .sit, room: seat)
        }
        // A Gremlin waits in ambush by something to hide behind, in the room it was in if it can.
        if style == .ambush, let hideaway = offers.filter({ $0.value.contains(.hide) }).keys.sorted().first {
            let room = offers[start.room ?? from]?.contains(.hide) == true ? start.room ?? from : hideaway
            start = BehaviourChoice(activity: .hide, room: room)
        }
        if firstEver {
            start.room = .living
        }
        let here = start.room ?? .living
        let choice = RoomChoice.placed(
            BehaviourTable.choose(context, rng: &brain),
            current: here, viewing: here, offers: offers, timeOfDay: time, rng: &brain
        )
        return Arrival(greeting: greeting, meow: meow, choice: choice, mood: mood, start: start, style: style)
    }

    /// Whether the cat follows you from room to room (a Velcro cat does, and one with that quirk).
    var followsYou: Bool {
        cat?.personality == .velcro || identity?.has(.followsYou) == true
    }

    // MARK: The cat's ways and wants

    /// The cat's own ways (the same on every device, every day).
    var identity: CatIdentity? {
        let state = state(at: now())
        return state.cat(Self.catID).map { CatIdentity.of($0, household: state.seed) }
    }

    /// What every open room's furniture lets the cat do, together.
    private func offered(in state: HouseholdState) -> Set<Affordance> {
        RoomChoice.offers(in: state, catalogue: content?.affordances ?? [:]).values.reduce(into: Set<Affordance>()) { $0.formUnion($1) }
    }

    /// How the cat is doing now: what it would love, and how content it is.
    func wellbeing() -> Wellbeing? {
        let state = state(at: now())
        guard let cat = state.cat(Self.catID) else { return nil }
        return Wellbeing.of(cat, identity: CatIdentity.of(cat, household: state.seed), offers: offered(in: state), today: state.today)
    }

    /// A piece the cat would love, for its thought bubble.
    struct WantedPiece: Equatable {
        var want: Want
        var itemID: String
        var sprite: String
        /// You have it and have not put it out (else it is in the shop).
        var owned: Bool
    }

    /// The piece for what the cat would love most: one you have but have not put out, else the cheapest in the shop
    /// you can have now (else the next you can).
    func wantedPiece(in room: RoomID) -> WantedPiece? {
        guard let want = wellbeing()?.wants.first, let content else { return nil }
        let items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        let answers = { (id: String) in items[id]?.affordances.contains(want.affordance) == true }
        if let owned = inventory().first(where: { answers($0.id) }) {
            return WantedPiece(want: want, itemID: owned.id, sprite: owned.sprite, owned: true)
        }
        let stock = shop(for: room).filter { answers($0.id) }
        let pick = stock.first { if case .buyable = $0.status { true } else { false } }
            ?? stock.first { if case .needsBeans = $0.status { true } else { false } }
            ?? stock.first
        return pick.map { WantedPiece(want: want, itemID: $0.id, sprite: $0.sprite, owned: false) }
    }

    /// The cat's next activity while you watch (no event: activities are not game state). Same rule as the
    /// arrival, drawn afresh each time so it wanders, in whichever open room has what it wants.
    func nextActivity(catRoom: RoomID, viewing: RoomID) -> BehaviourChoice? {
        let date = now()
        let state = state(at: date)
        guard let cat = state.cat(Self.catID) else { return nil }
        let home = GameWorld.now(state: state, at: date)
        let sky = home.sky, weather = home.weather
        let offers = RoomChoice.offers(in: state, catalogue: content?.affordances ?? [:])
        let time = TimeOfDay.at(localMinutes: state.clock.localMinutes(of: date), clock: state.clock)
        let available = offers.values.reduce(into: Set<Affordance>()) { $0.formUnion($1) }
        let identity = CatIdentity.of(cat, household: state.seed)
        let context = BehaviourContext(
            mood: state.mood(of: Self.catID, at: date),
            weather: weather,
            personality: cat.personality,
            timeOfDay: time,
            available: available,
            sunlit: sky == .day && weather.isSunny,
            identity: identity,
            wants: Wellbeing.of(cat, identity: identity, offers: available, today: state.today).wants
        )
        var rng = DaySeed(
            household: state.seed,
            day: state.clock.day(of: date),
            purpose: "brain",
            salt: "idle\(Int(date.timeIntervalSince1970))"
        )
        let choice = BehaviourTable.choose(context, rng: &rng)
        return RoomChoice.placed(choice, current: catRoom, viewing: viewing, offers: offers, timeOfDay: time, rng: &rng)
    }

    /// An activity sent now (fed: the bowl) in the room that has what it needs.
    func placed(_ choice: BehaviourChoice, catRoom: RoomID, viewing: RoomID) -> BehaviourChoice {
        let date = now()
        let state = state(at: date)
        var rng = DaySeed(household: state.seed, day: state.clock.day(of: date), purpose: "brain", salt: "send\(log.events.count)")
        return RoomChoice.placed(
            choice,
            current: catRoom,
            viewing: viewing,
            offers: RoomChoice.offers(in: state, catalogue: content?.affordances ?? [:]),
            timeOfDay: TimeOfDay.at(localMinutes: state.clock.localMinutes(of: date), clock: state.clock),
            rng: &rng
        )
    }

    // MARK: Care

    /// Feed (once a day; again gets "full"): the line from the state before, then the `fed` event.
    func feed() -> String? {
        let date = now()
        let before = state(at: date)
        let context = CareLines.feed(before: before, catID: Self.catID)
        if before.cats.first?.lastFedDay == nil {
            Analytics.track(.firstFeed)
        }
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

    /// A line for a context from the cat's pack, now.
    func line(_ context: String) -> String? {
        let date = now()
        return line(context, before: state(at: date), date: date)
    }

    /// A reminder's line, in the cat's voice, for a moment ahead, with nothing left to fill in.
    func reminderLine(_ context: String, id: String, at date: Date) -> String? {
        let state = state(at: now())
        guard let cat = state.cat(Self.catID), let content else { return nil }
        var rng = DaySeed(household: state.seed, day: state.clock.day(of: date), purpose: "reminder", salt: id)
        return Greeting.line(context, cat: cat, lines: content.lines, rng: &rng, whole: true)
    }

    private func line(_ context: String, before state: HouseholdState, date: Date) -> String? {
        guard let cat = state.cat(Self.catID), let content else { return nil }
        var rng = DaySeed(household: state.seed, day: state.clock.day(of: date), purpose: "line", salt: "\(context)\(log.events.count)")
        return Greeting.line(context, cat: cat, lines: content.lines, rng: &rng)
    }

    // MARK: Launch events

    /// The gift track running today, if any.
    func liveTrack() -> EventDefinition? {
        let date = now()
        let state = state(at: date)
        return EventRules.live(on: state.clock.day(of: date), context: rules).first { $0.kind == .track }
    }

    /// The track's days whose presents are waiting, and which are already opened.
    func trackProgress(_ event: EventDefinition) -> (waiting: [Int], claimed: Set<Int>, today: Int?) {
        let date = now()
        let state = state(at: date)
        let day = state.clock.day(of: date)
        return (EventRules.claimable(event, state: state, on: day), state.eventClaims[event.id] ?? [], event.trackDay(on: day))
    }

    /// Opens one day's present.
    func claim(_ event: EventDefinition, day: Int) {
        append(.eventRewardClaimed(eventID: event.id, day: day), at: now())
    }

    // MARK: Play and naps

    /// What a game paid, for its results card.
    struct Reward {
        var beans: Int
        var xp: Int
        var line: String?
    }

    var playsLeft: Int {
        MiniGameRules.playsLeft(state(at: now()))
    }

    /// The day's seed for one play (String Chase lays its sparkles out with it).
    func miniGameSeed(_ gameID: String) -> DaySeed {
        let date = now()
        let state = state(at: date)
        return DaySeed(
            household: state.seed,
            day: state.clock.day(of: date),
            purpose: "minigame",
            salt: "\(gameID).\(state.today?.plays ?? 0)"
        )
    }

    /// A finished game: the `miniGamePlayed` event, and what it paid (nothing once the day's plays are used).
    func playMiniGame(_ gameID: String, stars: Int) -> Reward {
        Analytics.track(.gamePlayed, detail: gameID)
        let date = now()
        let before = state(at: date)
        append(.miniGamePlayed(game: gameID, stars: stars), at: date)
        let after = state(at: now())
        return Reward(
            beans: after.beans - before.beans,
            xp: after.xp - before.xp,
            line: line(MiniGameRules.endLine(stars: stars), before: before, date: date)
        )
    }

    /// The living room's floor and wallpaper pictures, for the games' room.
    func livingRoomTiles() -> (floor: String?, wall: String?) {
        guard let catalogue = content?.catalogue else { return (nil, nil) }
        let state = state(at: now())
        func sprite(_ kind: CatalogueFile.Surface.Kind) -> String? {
            let id = state.surface(kind, in: .living, catalogue: catalogue)
            return catalogue.surfaces.first { $0.id == id }?.sprite
        }
        return (sprite(.floor), sprite(.wall))
    }

    /// A nap that ran its course, recorded at the moment it ended (it pays once a day).
    @discardableResult
    func completeNap(endedAt end: Date) -> Bool {
        guard NapRules.pays(state(at: end)) else { return false }
        append(.napCompleted, at: min(end, now()))
        return true
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
        }.sorted { a, b in
            // The tour's pieces first, in the order it asks for them (sofa, rug, coffee table), then by name.
            let order = Tuning.Room.starterPieces
            switch (order.firstIndex(of: a.id), order.firstIndex(of: b.id)) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.name < b.name
            }
        }
    }

    /// The Bean catalogue for a room (its own pieces first), with what each needs.
    struct ShopEntry: Identifiable, Equatable {
        var id: String
        var name: String
        var sprite: String
        var status: BeanShop.Status
    }

    func shop(for room: RoomID) -> [ShopEntry] {
        guard let catalogue = content?.catalogue else { return [] }
        let state = state(at: now())
        return BeanShop.stock(for: room, catalogue: catalogue).compactMap { item in
            guard let sprite = item.sprites["R"] ?? item.sprites.values.first else { return nil }
            return ShopEntry(
                id: item.id,
                name: item.name,
                sprite: sprite,
                status: BeanShop.status(of: item, level: state.level, beans: state.beans)
            )
        }
    }

    /// Buys a piece with Beans into the inventory; false if it is not for sale to you now.
    @discardableResult
    func buy(_ itemID: String) -> Bool {
        guard let room = content?.catalogue.items.first(where: { $0.id == itemID }).flatMap({ RoomID(rawValue: $0.room) }),
              let entry = shop(for: room).first(where: { $0.id == itemID }),
              case let .buyable(price) = entry.status else { return false }
        append(.itemBought(itemID: itemID, beans: price), at: now())
        Sound.play("ui_bean_chime", volume: Tuning.Sound.place)
        return true
    }

    /// Places a piece from the inventory where it first fits among the room's pieces; returns the placement (with
    /// the event's id) for the scene, or nil if the room is full.
    func placeFromInventory(_ itemID: String, among pieces: [PlacementRules.Piece], room: RoomID = .living) -> RoomModel.Placement? {
        guard let item = content?.catalogue.items.first(where: { $0.id == itemID }) else { return nil }
        let fresh = PlacementRules.Piece(item, x: 0, y: 0, facing: .right)
        let size = state(at: now()).roomSize
        // In the tour's furnishing, the coffee table goes straight onto the rug (Josh, 22 Oct: "table on top").
        var onRug: PlacementRules.Piece?
        if itemID == Tuning.Room.tourTable, room == .living,
           let rug = state(at: now()).placed.first(where: { $0.room == .living && $0.itemID == Tuning.Room.tourRug })
        {
            let candidate = PlacementRules.Piece(item, x: rug.x, y: rug.y, facing: rug.facing)
            onRug = PlacementRules.fits(candidate, among: pieces, room: size) ? candidate : nil
        }
        // And the sofa against a back wall, facing the room (the tour waits for it there).
        var byWall: PlacementRules.Piece?
        if itemID == Tuning.Room.tourSofa, room == .living {
            let along = (0 ..< size.u).map { PlacementRules.Piece(item, x: $0, y: 0, facing: .right) }
                + (0 ..< size.v).map { PlacementRules.Piece(item, x: 0, y: $0, facing: .left) }
            byWall = along.first { PlacementRules.fits($0, among: pieces, room: size) }
        }
        guard let spot = onRug ?? byWall ?? PlacementRules.firstFit(fresh, among: pieces, room: size) else { return nil }
        let event = append(.itemPlaced(itemID: itemID, room: room, x: spot.x, y: spot.y, facing: spot.facing), at: now())
        Sound.play("ui_place_item", volume: Tuning.Sound.place)
        return RoomModel.Placement(id: itemID, u: Double(spot.x), v: Double(spot.y), facing: spot.facing.rawValue, placementID: event.id)
    }

    /// The wallpapers or floors the player can put up in a room, with the one up now.
    func surfaces(_ kind: CatalogueFile.Surface.Kind, in room: RoomID = .living) -> (options: [CatalogueFile.Surface], current: String?) {
        guard let catalogue = content?.catalogue else { return ([], nil) }
        let state = state(at: now())
        return (state.availableSurfaces(kind, in: room, catalogue: catalogue), state.surface(kind, in: room, catalogue: catalogue))
    }

    func changeSurface(_ surfaceID: String, in room: RoomID = .living) {
        append(.surfaceChanged(room: room, surfaceID: surfaceID), at: now())
        Sound.play("ui_place_item", volume: Tuning.Sound.place)
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

    // MARK: The cat

    /// The player's cat, once adopted.
    var cat: CatState? {
        state(at: now()).cat(Self.catID)
    }

    /// Adoption from the builder (SPEC "Cat builder"): the cat's own name, its personality and its look.
    func adopt(name: String, personality: Personality, look: CatLook) {
        Analytics.track(.catMade)
        let date = now()
        append(.catAdopted(catID: Self.catID, name: name, personality: personality, isKitten: look.age.isKitten), at: date)
        append(.catLookSet(catID: Self.catID, look: look), at: date)
    }

    /// An edit from the profile: every field can be changed again, free.
    func edit(name: String? = nil, personality: Personality? = nil, look: CatLook? = nil) {
        guard let cat else { return }
        let date = now()
        if let name, name != cat.name {
            append(.catRenamed(catID: Self.catID, name: name), at: date)
        }
        if let personality, personality != cat.personality {
            append(.personalityChanged(catID: Self.catID, personality: personality), at: date)
        }
        if let look, look != cat.look {
            append(.catLookSet(catID: Self.catID, look: look), at: date)
        }
    }

    // MARK: Home

    /// Buys the next house up the ladder (docs/LADDER.md) if nothing stands in the way, and fetches its exteriors.
    /// True when it was bought.
    @discardableResult
    func buyNextHouse() -> Bool {
        let date = now()
        let state = state(at: date)
        guard let next = state.nextRung,
              HouseLadder.block(above: state.rung, level: state.level, tasksDone: state.houseTasksDone, beans: state.beans) == nil
        else { return false }
        Analytics.track(.homeChosen, detail: next.style.rawValue)
        append(.houseBought(rung: next.number, beans: next.price), at: date)
        HomePacks.prepare(next.style)
        return self.state(at: date).rung == next.number
    }

    /// The home's season changed in Settings: saved at once.
    func setSeason(_ season: SeasonSetting) {
        let date = now()
        guard season != state(at: date).home.season else { return }
        append(.seasonSet(season), at: date)
    }

    // MARK: Gifts

    /// A gift the cat has dropped and the player has not picked up, with its book entry.
    struct WaitingGift: Equatable {
        var draw: GiftDraw
        var name: String
        var description: String
        var sprite: String
    }

    func waitingGift() -> WaitingGift? {
        let date = now()
        guard let draw = state(at: date).waitingGifts(at: date).first else { return nil }
        let entry = content?.gifts.gifts.first { $0.id == draw.giftID }
        return WaitingGift(
            draw: draw,
            name: entry?.name ?? draw.giftID,
            description: entry?.description ?? "",
            sprite: entry?.sprite ?? ""
        )
    }

    /// Picks the gift up: into the book, with its Beans and XP. Returns the line the cat says about it.
    func collect(_ gift: WaitingGift) -> String? {
        let date = now()
        let before = state(at: date)
        append(.giftCollected(catID: gift.draw.catID, giftID: gift.draw.giftID, rarity: gift.draw.rarity), at: date)
        return line("gift.\(gift.draw.rarity.rawValue)", before: before, date: date)
    }

    // MARK: The demo household

    /// A new household: the living room empty apart from the bowl and the moving box (`Tuning.Room.firstHome`,
    /// cells rounded from the demo layout's hand-tuned positions), and the starter piece in the inventory.
    /// The cat comes from the builder; debug runs can skip it with HOUSECAT_CAT=<preset id> (a velcro cat called Pip).
    // MARK: Your data

    /// The whole save as JSON ("Export my data"): every event and what they add up to now. Nothing else is
    /// kept about the player.
    func exportData() throws -> Data {
        struct Export: Encodable {
            var exportedAt: Date
            var app: String
            var note: String
            var events: [GameEvent]
            var state: HouseholdState
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let export = Export(
            exportedAt: Date(),
            app: "HouseCat \(version)",
            note: "Your HouseCat save: every event in order, and the household they add up to. Purchases are kept by your Apple Account, not here.",
            events: log.events,
            state: state(at: now())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// Wipes the save on this device and starts a new, empty household ("Delete all my data"), with any household
    /// set aside while sharing someone else's cat.
    func eraseEverything() {
        do {
            try store?.deleteEverything()
        } catch {
            NSLog("HouseCat: deleting the save failed: %@", "\(error)")
        }
        if let url = Self.setAsideURL {
            try? FileManager.default.removeItem(at: url)
        }
        log = SaveLog()
        folded = nil
        seedDemoHousehold()
    }

    // MARK: Sharing someone else's cat

    /// Where this phone's own household waits while its player co-owns someone else's cat (CLAUDE.md "Leaving and
    /// removing"): the whole log as JSON, on this device only.
    static var setAsideURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HouseCat", isDirectory: true)
            .appendingPathComponent("own-household.json")
    }

    /// The cat waiting on this device while its player shares another, by name.
    var setAsideCatName: String? {
        guard let url = Self.setAsideURL, let data = try? Data(contentsOf: url),
              let own = try? JSONDecoder().decode(SaveLog.self, from: data) else { return nil }
        return own.derive(context: rules).cat(Self.catID)?.name
    }

    /// Joining someone's cat: this phone's own household, if it has a cat, is set aside (never merged: both
    /// households' cats have the same id), and the save becomes the shared household's events. Nothing is sent
    /// anywhere; the caller switches who this phone is and starts the sync.
    func joinShared(_ events: [GameEvent]) throws {
        if cat != nil, let url = Self.setAsideURL, !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(SaveLog(events: log.events)).write(to: url, options: .atomic)
        }
        try store?.deleteEverything()
        log = SaveLog()
        folded = nil
        log.merge(events)
        try store?.append(contentsOf: log.events)
        WidgetBridge.changed()
    }

    /// Back to this phone's own household after leaving someone's cat (or being removed): the shared household's
    /// events go from this phone (they stay in the owner's iCloud) and the cat set aside comes back, its streak
    /// as the days away left it. With none set aside the save starts empty and the intro runs, as for a new player.
    /// Returns the cat that came back.
    @discardableResult
    func returnToOwnHousehold() -> String? {
        try? store?.deleteEverything()
        log = SaveLog()
        folded = nil
        var restored: String?
        if let url = Self.setAsideURL, let data = try? Data(contentsOf: url),
           let own = try? JSONDecoder().decode(SaveLog.self, from: data)
        {
            log.merge(own.events)
            try? store?.append(contentsOf: log.events)
            try? FileManager.default.removeItem(at: url)
            restored = cat?.name
        } else {
            seedDemoHousehold()
        }
        WidgetBridge.changed()
        return restored
    }

    private func seedDemoHousehold() {
        var date = Date()
        #if DEBUG
            // HOUSECAT_GIFT=1: the household starts yesterday with the cat fed, so a gift is waiting.
            let gift = ProcessInfo.processInfo.environment["HOUSECAT_GIFT"] != nil
            if gift {
                date = date.addingTimeInterval(-26 * 3600)
            }
            // HOUSECAT_HOUSE=full (with HOUSECAT_CAT): sixty days of play, every room open and furnished.
            let full = ProcessInfo.processInfo.environment["HOUSECAT_HOUSE"] == "full"
            if full {
                date = date.addingTimeInterval(-Double(Tuning.Debug.fullHouseDays + 1) * 86400)
            }
        #endif
        append(.householdCreated(seed: UInt64.random(in: 1 ... UInt64.max), clock: DayClock()), at: date)
        #if DEBUG
            if let id = ProcessInfo.processInfo.environment["HOUSECAT_CAT"], let preset = GameWorld.catArt?.builder.preset(id) {
                // HOUSECAT_NAME: a name to try the screens with (the longest a name can be, say).
                let name = ProcessInfo.processInfo.environment["HOUSECAT_NAME"] ?? "Pip"
                append(.catAdopted(catID: Self.catID, name: name, personality: .velcro, isKitten: false), at: date)
                append(.catLookSet(catID: Self.catID, look: preset.look), at: date)
                if gift {
                    append(.arrived, at: date.addingTimeInterval(300))
                    append(.fed(catID: Self.catID), at: date.addingTimeInterval(360))
                }
            }
        #endif
        guard let art = GameWorld.art, let layout = try? art.data("rooms/layout_living_demo.json", as: RoomModel.self) else { return }
        // A new home starts empty (Josh, 19 Oct: "they should want to decorate"): only the bowl and the moving box,
        // where the demo layout has them, and a starter piece in the tray for the tour's Decorate step. A debug
        // full house has the whole demo living room and two spare pieces.
        var furnished = false
        #if DEBUG
            furnished = full
        #endif
        for item in layout.items where furnished || Tuning.Room.firstHome.contains(item.id) {
            append(.itemGranted(itemID: item.id), at: date)
            let facing: GameEvent.Facing = item.facing == "L" ? .left : .right
            append(
                .itemPlaced(itemID: item.id, room: .living, x: Int(item.u.rounded()), y: Int(item.v.rounded()), facing: facing),
                at: date
            )
        }
        for spare in furnished ? ["living_armchair", "living_coffee"] : Tuning.Room.starterPieces {
            append(.itemGranted(itemID: spare), at: date)
        }
        #if DEBUG
            if full, cat != nil {
                seedFullHouse(from: date)
            }
        #endif
    }

    #if DEBUG
        /// A well-loved cat's two months: a visit, a meal, a pet, the day's games, a nap and the health goals
        /// every day (enough XP for every room), Beans to open them all, and each furnished as its closed
        /// silhouette shows (assets/rooms/houses.json roomStyles).
        private func seedFullHouse(from start: Date) {
            // Appended in one batch on the household's clock: deriving the save for every event would take a minute.
            let clock = fold().clock
            var batch: [GameEvent] = []
            func append(_ kind: GameEvent.Kind, at date: Date) {
                let at = log.timestamp(for: date)
                let event = GameEvent(at: at, day: clock.day(of: at), kind: kind)
                log.append(event)
                batch.append(event)
            }
            defer { try? store?.append(contentsOf: batch) }
            for day in 1 ... Tuning.Debug.fullHouseDays {
                let morning = start.addingTimeInterval(Double(day) * 86400 + 3 * 3600)
                append(.arrived, at: morning)
                append(.fed(catID: Self.catID), at: morning.addingTimeInterval(60))
                append(.petted(catID: Self.catID), at: morning.addingTimeInterval(120))
                for play in 0 ..< 5 {
                    append(.miniGamePlayed(game: "laser_pointer", stars: 3), at: morning.addingTimeInterval(Double(180 + play * 30)))
                }
                append(.napCompleted, at: morning.addingTimeInterval(600))
                for goal in GameEvent.HealthGoal.allCases {
                    append(.healthGoalMet(goal), at: morning.addingTimeInterval(700))
                }
            }
            let now = Date()
            append(.purchaseBeansGranted(transactionID: "debug-full-house", beans: Tuning.Debug.fullHouseBeans), at: now)
            guard let plans = try? GameWorld.art?.data("rooms/houses.json", as: HousePlans.self) else { return }
            for room in RoomID.allCases where room != .living {
                append(.roomOpened(room, beans: RoomRules.cost(of: room, clubActive: false)), at: now)
                for piece in plans.roomStyles[room.rawValue]?.preview ?? [] {
                    append(.itemGranted(itemID: piece.id), at: now)
                    let facing: GameEvent.Facing = piece.facing == "L" ? .left : .right
                    append(
                        .itemPlaced(itemID: piece.id, room: room, x: Int(piece.u.rounded()), y: Int(piece.v.rounded()), facing: facing),
                        at: now
                    )
                }
            }
        }
    #endif
}
