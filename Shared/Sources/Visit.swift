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
    /// Decorate mode, and the piece picked up in it.
    private(set) var decorating = false
    private(set) var selected: UUID?
    /// What the save says now, for the status readout.
    struct Stats: Equatable {
        var level = 1
        var beans = 0
        var streak = 0
    }

    private(set) var stats = Stats()

    /// Reads the level, Beans and streak again after anything that changes them; a new level gets its fanfare.
    func refreshStats() {
        let state = GameSession.shared.state(at: GameSession.shared.now())
        let before = stats
        stats = Stats(level: state.level, beans: state.beans, streak: state.streak.current)
        if statsRead, stats.level > before.level {
            Sound.play("ui_level_up", volume: Tuning.Sound.levelUp)
            show(toast: "Level \(stats.level)")
            say(GameSession.shared.line("progress.level_up"))
        }
        statsRead = true
    }

    @ObservationIgnored private var statsRead = false

    /// A short note over the room ("+10 Beans", "Level 3"), gone after a moment.
    private(set) var toast: String?

    private func show(toast text: String) {
        toast = text
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
    private func offerGift() {
        guard let house = scene as? RoomScene, let waiting = GameSession.shared.waitingGift(), let art = GameWorld.art,
              !house.hasGift else { return }
        gift = waiting
        house.dropGift(art.texture(waiting.sprite))
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
        show(toast: "\(gift.name) · +\(earned) Beans")
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
    @ObservationIgnored private var arrival: GameSession.Arrival?
    @ObservationIgnored private let size: CGSize
    @ObservationIgnored private var room: SKScene?

    init(size: CGSize, now: Date = Date(), lastActive: Date?) {
        self.size = size
        if ArrivalRules.showsExterior(lastActive: lastActive, now: now), let exterior = GameWorld.exteriorScene(size: size, at: now) {
            scene = exterior
            exterior.onDoorOpens = { Sound.play("door_open", volume: Tuning.Sound.door) }
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
        offerGift()
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
    }

    /// Pieces owned but not placed, shown in a tray while decorating.
    private(set) var inventory: [GameSession.InventoryEntry] = []

    /// What the decorate tray shows: furniture to put out, or the room's wallpapers or floors.
    enum TrayMode: Int, CaseIterable {
        case furniture
        case walls
        case floors

        var title: String {
            switch self {
            case .furniture: "Furniture"
            case .walls: "Walls"
            case .floors: "Floors"
            }
        }
    }

    var trayMode = TrayMode.furniture

    /// The surfaces for the tray's walls or floors mode, with the one up now.
    var surfaceOptions: (options: [CatalogueFile.Surface], current: String?) {
        switch trayMode {
        case .furniture: ([], nil)
        case .walls: GameSession.shared.surfaces(.wall)
        case .floors: GameSession.shared.surfaces(.floor)
        }
    }

    /// Puts up a wallpaper or floor and rebuilds the house, staying in decorate mode.
    func chooseSurface(_ surfaceID: String) {
        guard let house = scene as? RoomScene, decorating else { return }
        let session = GameSession.shared
        session.changeSurface(surfaceID)
        if let model = GameWorld.house(at: session.now(), state: session.state(at: session.now())) {
            house.update(house: model)
            house.setDecorating(true)
        }
        selected = nil
    }

    /// Puts a piece from the tray into the room, picked up and ready to drag.
    func placeFromInventory(_ itemID: String) {
        guard let house = scene as? RoomScene, decorating,
              let placement = GameSession.shared.placeFromInventory(itemID, among: house.pieces())
        else { return }
        house.place(placement)
        inventory = GameSession.shared.inventory()
        refreshStats()
    }

    private func offer(_ room: RoomID) {
        let state = GameSession.shared.state(at: GameSession.shared.now())
        let availability = RoomRules.availability(
            of: room,
            opened: state.openedRooms,
            level: state.level,
            beans: state.beans,
            clubActive: false
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
    }

    /// Feed: the cat goes to its bowl and says its line.
    func feed() {
        guard let house = scene as? RoomScene, !decorating else { return }
        let trust = GameSession.shared.cat?.trust
        let line = GameSession.shared.feed()
        house.send(BehaviourChoice(activity: .bowlNag))
        house.react("notes")
        say(line)
        refreshStats()
        // A new trust tier gets its own line once the feeding line has been read.
        if let after = GameSession.shared.cat?.trust, let trust, after > trust {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds))
                self?.say(GameSession.shared.line("progress.trust_\(String(describing: after))"))
                self?.show(toast: "Trust: \(String(describing: after).capitalized)")
            }
        }
        // Fed: the day's gift is drawn and drops later; one may already be waiting.
        offerGift()
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
            house.send(GameSession.shared.nextActivity() ?? BehaviourChoice(activity: .hide))
        } else {
            GameWorld.purr()
        }
        say(line)
        refreshStats()
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

    /// Up the stairs to the next storey, or back down to the ground floor from the top.
    func changeStorey() {
        guard let house = scene as? RoomScene, storeys.count > 1 else { return }
        let next = storeys.first { $0 > storey } ?? storeys[0]
        decorating = false
        selected = nil
        house.showStorey(next)
        storey = house.storey
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
        let built = GameWorld.roomScene(size: size, state: GameSession.shared.state(at: GameSession.shared.now()), arrival: arrival)
        if let house = built as? RoomScene {
            storeys = house.storeys
            storey = house.storey
            house.onDecorate = { GameSession.shared.record($0) }
            house.onSelect = { [weak self] in self?.selected = $0 }
            house.onClosedRoomTapped = { [weak self] in self?.offer($0) }
            house.nextActivity = { GameSession.shared.nextActivity() }
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
