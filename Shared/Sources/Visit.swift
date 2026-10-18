import Foundation
import HouseCatCore
import HouseCatGame
import Observation
import SpriteKit

/// One visit (SPEC "The session loop" 1–3): the exterior cold open when the app has been away
/// an hour or more, then the living room with the cat's arrival. Holds the scene SwiftUI shows;
/// every decision comes from HouseCatCore.
@MainActor
@Observable
final class Visit {
    /// The scene on screen.
    private(set) var scene: SKScene
    /// The cat's greeting, shown for a few seconds once the room is on screen.
    private(set) var greeting: String?
    /// The cat's name, over its lines.
    var catName: String? {
        GameSession.shared.cat?.name
    }

    /// What VoiceOver says for the scene: the home and the room, or where the cat is and what it last said.
    var accessibilityDescription: String {
        guard scene is RoomScene else { return "Your home, from outside. Double-tap to go in." }
        let name = catName ?? "Your cat"
        if let greeting {
            return "\(roomTitle). \(name) says: \(greeting)"
        }
        return "\(roomTitle). \(name) is here."
    }

    /// Debug screenshot runs open the shop (HOUSECAT_SCREEN=shop).
    var openShop = false

    /// After the first feed: the card asking whether the cat may send reminders (once).
    var askReminders = false

    /// The cat has just reached a new trust tier (the app may show the once-only offer).
    var trustRose: TrustTier?

    /// Debug screenshot runs: a game to open (HOUSECAT_SCREEN=game:<id>), or "picker".
    var openGame: String?

    /// The first frame of the scene has been drawn (the launch curtain lifts).
    private(set) var ready = false

    func sceneIsReady() {
        if !ready {
            ready = true
        }
    }

    /// Decorate mode, and the piece picked up in it.
    private(set) var decorating = false
    private(set) var selected: UUID?
    /// What the save says now, for the status readout.
    struct Stats: Equatable {
        var level = 1
        var xp = 0
        /// How far into the level, 0 to 1 (the pill's XP bar).
        var progress = 0.0
        var beans = 0
        var streak = 0
    }

    private(set) var stats = Stats()

    /// XP just earned, floating up by the level ("+12 XP"); a new id each time so the same amount floats again.
    struct XPGain: Equatable {
        var amount: Int
        var id = UUID()
    }

    private(set) var xpGain: XPGain?

    /// A level just reached: the card with what it brought (Josh, 18 Oct: a level-up card and a road ahead).
    var levelReached: Int?

    /// Reads the level, Beans and streak again after anything that changes them; XP earned floats up, and a new
    /// level gets its fanfare and its card.
    func refreshStats() {
        let state = GameSession.shared.state(at: GameSession.shared.now())
        let before = stats
        let curve = LevelCurve.progress(xp: state.xp)
        let span = max(1, curve.intoLevel + curve.toNext)
        stats = Stats(
            level: state.level,
            xp: state.xp,
            progress: Double(curve.intoLevel) / Double(span),
            beans: state.beans,
            streak: state.streak.current
        )
        guard statsRead else {
            statsRead = true
            return
        }
        if stats.xp > before.xp {
            let gain = XPGain(amount: stats.xp - before.xp)
            xpGain = gain
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Tuning.Levels.floatSeconds))
                if self?.xpGain == gain {
                    self?.xpGain = nil
                }
            }
        }
        if stats.level > before.level {
            Sound.play("ui_level_up", volume: Tuning.Sound.levelUp)
            say(GameSession.shared.line("progress.level_up"))
            // Never over the tour: it waits for the tour's end.
            levelReached = stats.level
        }
    }

    @ObservationIgnored private var statsRead = false

    /// A short note over the room ("+10 Beans", "Level 3"), gone after a moment.
    private(set) var toast: String?
    /// The painted icon that goes with the toast.
    private(set) var toastIcon: String?

    private func show(toast text: String, icon: String? = nil) {
        toast = text
        toastIcon = icon
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.Care.toastSeconds))
            if self?.toast == text {
                self?.toast = nil
            }
        }
    }

    // MARK: The gift

    /// The gift the cat dropped, waiting to be tapped.
    private(set) var gift: GameSession.WaitingGift?

    /// If a gift is waiting, the cat drops it at your feet (SPEC "The session loop" 4).
    private func offerGift(after delay: TimeInterval = Tuning.Gifts.dropDelay) {
        guard let house = (scene as? RoomScene) ?? (room as? RoomScene), let waiting = GameSession.shared.waitingGift(),
              let art = GameWorld.art, !house.hasGift else { return }
        gift = waiting
        house.dropGift(art.texture(waiting.sprite), after: delay)
    }

    /// Tap on the gift: into the book, with its Beans and XP.
    func collectGift() {
        guard let house = scene as? RoomScene, let gift else { return }
        let beans = GameSession.shared.state(at: GameSession.shared.now()).beans
        let line = GameSession.shared.collect(gift)
        self.gift = nil
        house.removeGift(collected: true)
        Sound.play("ui_gift_open_\(gift.draw.rarity.rawValue)", volume: Tuning.Sound.gift)
        refreshStats()
        let earned = stats.beans - beans
        show(toast: "\(gift.name) · +\(earned) Beans", icon: "gift_box_with_a_ribbon")
        say(line)
        // Another may have dropped while this one waited.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds))
            self?.offerGift()
        }
    }

    // MARK: The cat's look

    /// Draws the cat in its look again after an edit from the profile.
    func refreshCat() {
        guard let house = scene as? RoomScene, let cat = GameSession.shared.cat else { return }
        let session = GameSession.shared
        house.director?.cat.apply(
            look: cat.look,
            isKitten: cat.isKittenStage(on: session.state(at: session.now()).clock.day(of: session.now()))
        )
    }

    /// A closed room the player tapped, with what opening it takes (Core's `RoomRules.availability`).
    struct RoomOffer: Identifiable {
        var room: RoomID
        var availability: RoomAvailability
        var level: Int
        var beans: Int
        var id: RoomID {
            room
        }
    }

    var roomOffer: RoomOffer?

    /// The storey on screen, and whether the house has one above it.
    private(set) var storey = 0
    private(set) var storeys: [Int] = [0]
    /// The room you are in (decorating, walls and floors, and the shop act on it).
    private(set) var activeRoom: RoomID = .living
    /// Whether the room you are in is on the storey on screen (decorating needs it).
    private(set) var canDecorate = true

    /// The open rooms, ground floor first, for moving between them.
    var openRooms: [RoomID] {
        guard let house = (scene as? RoomScene)?.house else { return [.living] }
        return house.rooms.filter { $0.lockLabel == nil }.sorted { ($0.storey, $0.id) < ($1.storey, $1.id) }.map(\.id)
    }

    /// The room's name as the player sees it (the garden is a balcony upstairs).
    var roomTitle: String {
        Self.title(of: activeRoom, upstairs: ((scene as? RoomScene)?.house.room(activeRoom)?.storey ?? 0) > 0)
    }

    static func title(of room: RoomID, upstairs: Bool) -> String {
        switch room {
        case .living: "Living room"
        case .bedroom: "Bedroom"
        case .kitchen: "Kitchen"
        case .garden: upstairs ? "Balcony" : "Garden"
        case .study: "Study"
        case .attic: "Attic"
        }
    }

    /// Goes to another open room (a tap on it, or the room arrows).
    func go(to room: RoomID) {
        guard let house = scene as? RoomScene, house.house.room(room)?.lockLabel == nil else { return }
        decorating = false
        selected = nil
        house.show(room: room)
        roomShown(room)
        GameSession.shared.append(.roomVisited(room), at: GameSession.shared.now())
    }

    /// The next or previous open room.
    func stepRoom(_ step: Int) {
        let rooms = openRooms
        guard rooms.count > 1, let index = rooms.firstIndex(of: activeRoom) else { return }
        go(to: rooms[(index + step + rooms.count) % rooms.count])
    }

    private func roomShown(_ room: RoomID) {
        guard let house = scene as? RoomScene else { return }
        activeRoom = room
        storey = house.storey
        canDecorate = house.storey == house.house.storey
        inventory = decorating ? GameSession.shared.inventory() : []
    }

    @ObservationIgnored private var arrival: GameSession.Arrival?
    @ObservationIgnored private let size: CGSize
    @ObservationIgnored private var room: SKScene?

    init(size: CGSize, now: Date = Date(), lastActive: Date?) {
        self.size = size
        // A home whose exteriors come as a download: ask for them (the cold open waits until they are here).
        HomePacks.prepare(GameWorld.style(GameSession.shared.state(at: now)))
        if ArrivalRules.showsExterior(lastActive: lastActive, now: now), let exterior = GameWorld.exteriorScene(
            size: size,
            at: now,
            state: GameSession.shared.state(at: now)
        ) {
            scene = exterior
            exterior.onDoorOpens = { Sound.play("door_open", volume: Tuning.Sound.door) }
            Sound.weather(exterior.model.weather)
            exterior.onEnter = { [weak self, weak exterior] in
                guard let self else { return }
                let room = preparedRoom()
                // Present from the exterior's own view so the push flows straight into the room.
                exterior?.view?.presentScene(room, transition: .crossFade(withDuration: Tuning.Exterior.roomFadeSeconds))
                scene = room
                greet()
                #if DEBUG
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(8))
                        self?.applyScreenshotState()
                    }
                #endif
            }
            // Build the room once the exterior is on screen, behind its first seconds.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Tuning.Exterior.roomBuildDelay))
                _ = self?.preparedRoom()
            }
        } else {
            scene = SKScene(size: size)
            scene = preparedRoom()
            greet()
            #if DEBUG
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    self?.applyScreenshotState()
                }
            #endif
        }
    }

    #if DEBUG
        /// Screenshot runs from the command line (HOUSECAT_SCREEN=decorate or upstairs): opens that state once the room is up.
        func applyScreenshotState() {
            // HOUSECAT_ROOM=<room>: go to that room and send the cat to use a piece of its furniture.
            if let name = ProcessInfo.processInfo.environment["HOUSECAT_ROOM"], let room = RoomID(rawValue: name),
               let house = scene as? RoomScene
            {
                go(to: room)
                let state = GameSession.shared.state(at: GameSession.shared.now())
                let offers = state.affordances(in: room, catalogue: GameSession.shared.content?.affordances ?? [:])
                let activities: [Activity] = [.sleep, .sit, .perch, .windowWatch, .hide, .bowlNag]
                if let activity = activities.first(where: { $0.affordance.map(offers.contains) ?? false }) {
                    house.send(BehaviourChoice(activity: activity, room: room))
                }
            }
            guard let wanted = ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"], let house = scene as? RoomScene else { return }
            switch wanted {
            case "decorate":
                toggleDecorating()
                house.selectForScreenshot("living_sofa")
            case "upstairs":
                changeStorey()
            case "walls":
                toggleDecorating()
                trayMode = .walls
            case "feed":
                feed()
            case "pet":
                petCat()
            case "shop":
                openShop = true
            case "play":
                openGame = "picker"
            case "nap":
                startNap()
            case "offer":
                trustRose = Tuning.Store.offerTrustTier
            case let screen where screen.hasPrefix("game:"):
                openGame = String(screen.dropFirst("game:".count))
            default:
                break
            }
        }
    #endif

    /// Shows the greeting while the cat notices you, then lets it go (SPEC: three seconds at most).
    private func greet() {
        if let house = scene as? RoomScene {
            Sound.ambience(for: house.house.sky, fire: house.furniture.values.contains { $0.childNode(withName: "fx.fire") != nil })
        }
        let session = GameSession.shared
        Sound.weather(GameWorld.now(state: session.state(at: session.now()), at: session.now()).weather)
        guard let line = arrival?.greeting else { return }
        let meow = Sound.meow(arrival?.meow)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.Arrival.noticeDelay))
            if let meow {
                Sound.play(meow, volume: Tuning.Sound.meow)
            }
            self?.greeting = line
            try? await Task.sleep(for: .seconds(Tuning.Arrival.greetingMaxSeconds))
            if self?.greeting == line {
                self?.greeting = nil
            }
        }
    }

    /// Decorate mode on or off (the room must be on screen).
    func toggleDecorating() {
        guard let house = scene as? RoomScene else { return }
        decorating.toggle()
        greeting = nil
        house.setDecorating(decorating)
        inventory = decorating ? GameSession.shared.inventory() : []
        RoomTour.shared.heard(.decorating(decorating))
    }

    /// Pieces owned but not placed, shown in a tray while decorating.
    private(set) var inventory: [GameSession.InventoryEntry] = []

    /// What the decorate tray shows: furniture to put out, or the room's wallpapers or floors.
    enum TrayMode: Int, CaseIterable {
        case furniture
        case shop
        case walls
        case floors

        var title: String {
            switch self {
            case .furniture: "Yours"
            case .shop: "Shop"
            case .walls: "Walls"
            case .floors: "Floors"
            }
        }

        /// Its painted icon.
        var icon: String {
            switch self {
            case .furniture: "sofa_for_furniture"
            case .shop: "shop_bag"
            case .walls: "wallpaper_roll"
            case .floors: "floorboards"
            }
        }
    }

    var trayMode = TrayMode.furniture

    /// The surfaces for the tray's walls or floors mode, with the one up now.
    var surfaceOptions: (options: [CatalogueFile.Surface], current: String?) {
        switch trayMode {
        case .furniture, .shop: ([], nil)
        case .walls: GameSession.shared.surfaces(.wall, in: activeRoom)
        case .floors: GameSession.shared.surfaces(.floor, in: activeRoom)
        }
    }

    /// The Bean catalogue for the room you are in.
    var shopEntries: [GameSession.ShopEntry] {
        GameSession.shared.shop(for: activeRoom)
    }

    /// Buys a piece and puts it straight into the room, picked up, ready to drag.
    func buy(_ itemID: String) {
        guard GameSession.shared.buy(itemID) else { return }
        refreshStats()
        trayMode = .furniture
        placeFromInventory(itemID)
    }

    // MARK: Room looks

    /// A room look being tried in its room (the shop's "Try it in your room"): its pieces see-through where
    /// they would go, nothing recorded, until bought or put away.
    private(set) var previewing: BundlesFile.Bundle?

    func preview(_ bundle: BundlesFile.Bundle) {
        guard let house = scene as? RoomScene else { return }
        if activeRoom != bundle.room {
            go(to: bundle.room)
        }
        guard activeRoom == bundle.room else { return }
        house.showPreview(GameSession.shared.preview(bundle, among: house.pieces()))
        previewing = bundle
        greeting = nil
    }

    func endPreview() {
        (scene as? RoomScene)?.clearPreview()
        previewing = nil
    }

    /// Puts a whole room look in its room at once (the shop's "Add the whole room"): each piece where it first
    /// fits, the wallpaper and floor up; what does not fit waits in the inventory.
    func addWholeRoom(_ bundle: BundlesFile.Bundle) {
        guard let house = scene as? RoomScene else { return }
        endPreview()
        if activeRoom != bundle.room {
            go(to: bundle.room)
        }
        guard activeRoom == bundle.room else { return }
        let session = GameSession.shared
        let placed = session.addWholeRoom(bundle, among: house.pieces())
        if let model = GameWorld.house(at: session.now(), state: session.state(at: session.now())) {
            house.update(house: model)
            house.setDecorating(decorating)
        }
        inventory = decorating ? session.inventory() : []
        refreshStats()
        show(
            toast: placed == bundle.items.count ? "\(bundle.name) is in" : "\(placed) pieces in, the rest in your things",
            icon: "sofa_for_furniture"
        )
    }

    /// Puts up a wallpaper or floor and rebuilds the house, staying in decorate mode.
    func chooseSurface(_ surfaceID: String) {
        guard let house = scene as? RoomScene, decorating else { return }
        let session = GameSession.shared
        session.changeSurface(surfaceID, in: activeRoom)
        if let model = GameWorld.house(at: session.now(), state: session.state(at: session.now())) {
            house.update(house: model)
            house.setDecorating(true)
        }
        selected = nil
    }

    /// Puts a piece from the tray into the room, picked up and ready to drag.
    func placeFromInventory(_ itemID: String) {
        guard let house = scene as? RoomScene, decorating,
              let placement = GameSession.shared.placeFromInventory(itemID, among: house.pieces(), room: activeRoom)
        else { return }
        house.place(placement)
        inventory = GameSession.shared.inventory()
        refreshStats()
        RoomTour.shared.heard(.placed)
    }

    private func offer(_ room: RoomID) {
        let state = GameSession.shared.state(at: GameSession.shared.now())
        let availability = RoomRules.availability(
            of: room,
            opened: state.openedRooms,
            level: state.level,
            beans: state.beans,
            clubActive: state.today?.clubDay == true
        )
        roomOffer = RoomOffer(room: room, availability: availability, level: state.level, beans: state.beans)
    }

    /// Opens the offered room with Beans and rebuilds the house around it.
    func openOfferedRoom() {
        guard let offer = roomOffer, case let .unlockable(cost) = offer.availability else { return }
        roomOffer = nil
        let session = GameSession.shared
        session.append(.roomOpened(offer.room, beans: cost), at: session.now())
        if let house = scene as? RoomScene, let model = GameWorld.house(at: session.now(), state: session.state(at: session.now())) {
            house.update(house: model)
        }
        refreshStats()
        // Into the new room, with the shop open: it starts empty.
        go(to: offer.room)
        if !decorating {
            toggleDecorating()
        }
        trayMode = .shop
    }

    /// Feed: the cat goes to its bowl and says its line.
    func feed() {
        guard let house = scene as? RoomScene, !decorating else { return }
        let trust = GameSession.shared.cat?.trust
        let line = GameSession.shared.feed()
        house.send(GameSession.shared.placed(BehaviourChoice(activity: .bowlNag), catRoom: house.catRoom, viewing: activeRoom))
        house.react("notes")
        say(line)
        refreshStats()
        // A new trust tier gets its own line once the feeding line has been read.
        if let after = GameSession.shared.cat?.trust, let trust, after > trust {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds))
                self?.say(GameSession.shared.line("progress.trust_\(String(describing: after))"))
                self?.show(toast: "Trust: \(String(describing: after).capitalized)", icon: "trust_heart_with_a_paw_print")
                self?.trustRose = after
            }
        }
        // Fed: the day's gift is drawn and drops later; one may already be waiting.
        offerGift()
        RoomTour.shared.heard(.fed)
        // The first feed ever: may the cat remind you? (SPEC: the pre-permission screen after the first feed.)
        // During the room tour it waits for the tour's end.
        if !Reminders.asked, !RoomTour.shared.isRunning {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds + 0.5))
                self?.askReminders = true
            }
        }
    }

    @ObservationIgnored private var petTaps = 0
    @ObservationIgnored private var lastPet = Date.distantPast

    /// A tap on the cat: a heart and a purr; too many in a row and most cats walk off.
    func petCat() {
        guard let house = scene as? RoomScene else { return }
        let now = Date()
        petTaps = now.timeIntervalSince(lastPet) < Tuning.Care.petRowSeconds ? petTaps + 1 : 1
        lastPet = now
        let (line, walksOff) = GameSession.shared.pet(taps: petTaps)
        house.react(walksOff ? "exclaim" : "heart")
        if walksOff {
            petTaps = 0
            house.send(GameSession.shared.nextActivity(catRoom: house.catRoom, viewing: activeRoom) ?? BehaviourChoice(activity: .hide))
        } else {
            GameWorld.purr()
        }
        say(line)
        refreshStats()
        RoomTour.shared.heard(.petted)
    }

    // MARK: The room tour

    /// The tour's stroke step: the cat comes to the front of the room you are in and sits for it.
    func callCatForTour() {
        guard let house = scene as? RoomScene else { return }
        house.send(BehaviourChoice(activity: .nearPlayer, room: activeRoom))
    }

    /// Where the cat is on screen, for the tour's paw.
    var catPoint: CGPoint? {
        (scene as? RoomScene)?.catPointInView
    }

    // MARK: Play and naps

    /// Play: true to open the games, or the cat's line once the day's five plays are used.
    func wantsToPlay() -> Bool {
        if GameSession.shared.playsLeft > 0 {
            return true
        }
        say(GameSession.shared.line("play.used_up"))
        return false
    }

    /// Back from a game: the room's numbers and what it paid.
    func played(_ reward: GameSession.Reward) {
        refreshStats()
        if reward.beans > 0 {
            show(toast: "+\(reward.beans) Beans", icon: "bean_coin")
        }
    }

    /// The nap: the cat curls up in its bed, the timer goes on the Lock Screen.
    func startNap() {
        guard let house = scene as? RoomScene, !Naps.shared.isNapping else { return }
        Naps.shared.start(catName: catName ?? "Your cat")
        house.send(GameSession.shared.placed(BehaviourChoice(activity: .sleep), catRoom: house.catRoom, viewing: activeRoom))
        house.react("zzz")
        Sound.loop("cat_sleep_breathing", volume: Tuning.Sound.purr)
    }

    /// Woken early: up again, and no XP.
    func wakeFromNap() {
        Naps.shared.wake()
        Sound.stop("cat_sleep_breathing", after: Tuning.Sound.fadeSeconds)
        if let house = scene as? RoomScene {
            house.send(GameSession.shared.nextActivity(catRoom: house.catRoom, viewing: activeRoom) ?? BehaviourChoice(activity: .sit))
        }
    }

    /// A nap whose time is up: recorded, and its XP shown (once a day).
    func checkNap() {
        guard Naps.shared.isNapping else { return }
        let paid = Naps.shared.check()
        guard !Naps.shared.isNapping else { return }
        Sound.stop("cat_sleep_breathing", after: Tuning.Sound.fadeSeconds)
        refreshStats()
        show(toast: paid ? "A good nap · +\(Tuning.XP.nap) XP" : "A good nap", icon: "nap_moon")
    }

    /// Shows a line in the bubble for a few seconds.
    func say(_ line: String?) {
        guard let line else { return }
        greeting = line
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds))
            if self?.greeting == line {
                self?.greeting = nil
            }
        }
    }

    /// Up the stairs to the next storey, or back down to the ground floor from the top: into its first open
    /// room, or just to look at it if none is open yet.
    func changeStorey() {
        guard let house = scene as? RoomScene, storeys.count > 1 else { return }
        let next = storeys.first { $0 > storey } ?? storeys[0]
        decorating = false
        selected = nil
        if let room = house.house.rooms.filter({ $0.storey == next && $0.lockLabel == nil }).min(by: { $0.id < $1.id }) {
            go(to: room.id)
        } else {
            house.showStorey(next)
            storey = house.storey
            canDecorate = house.storey == house.house.storey
        }
    }

    /// The label for the stairs button, if the house has more than one storey.
    var storeyTitle: String? {
        guard storeys.count > 1 else { return nil }
        return storeys.contains { $0 > storey } ? "Upstairs" : "Downstairs"
    }

    func turnSelection() {
        (scene as? RoomScene)?.turnSelection()
    }

    func storeSelection() {
        (scene as? RoomScene)?.storeSelection()
        inventory = GameSession.shared.inventory()
    }

    /// Tap to dismiss the greeting early.
    func dismissGreeting() {
        greeting = nil
    }

    private func preparedRoom() -> SKScene {
        if let room {
            return room
        }
        // The arrival is recorded when the room is built: that is when the save learns you came home.
        let arrival = GameSession.shared.arrive()
        self.arrival = arrival
        // The gift lands at your feet as the cat comes to you (or once it has arrived, if it never does).
        let built = GameWorld.roomScene(
            size: size,
            state: GameSession.shared.state(at: GameSession.shared.now()),
            arrival: arrival,
            onRub: { [weak self] in self?.offerGift(after: Tuning.Gifts.rubDropDelay) },
            onArrived: { [weak self] in self?.offerGift(after: 0) }
        )
        if let house = built as? RoomScene {
            storeys = house.storeys
            storey = house.storey
            house.onDecorate = { [weak self] in GameSession.shared.record($0, in: self?.activeRoom ?? .living) }
            house.onSelect = { [weak self] in self?.selected = $0 }
            house.onClosedRoomTapped = { [weak self] in self?.offer($0) }
            house.nextActivity = { [weak self] catRoom in
                GameSession.shared.nextActivity(catRoom: catRoom, viewing: self?.activeRoom ?? .living)
            }
            house.onRoomTapped = { [weak self] in self?.go(to: $0) }
            house.onActiveRoomChanged = { [weak self] in self?.roomShown($0) }
            house.onCatTapped = { [weak self] in self?.petCat() }
            house.onGiftTapped = { [weak self] in self?.collectGift() }
        }
        room = built
        refreshStats()
        return built
    }

    /// When the app was last in the foreground, kept on this device only (it decides the cold open, not game state).
    static var lastActive: Date? {
        get { UserDefaults.standard.object(forKey: "lastActive") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastActive") }
    }
}
