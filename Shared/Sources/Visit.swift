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
        }
        room = built
        return built
    }

    /// When the app was last in the foreground, kept on this device only (it decides the cold open, not game state).
    static var lastActive: Date? {
        get { UserDefaults.standard.object(forKey: "lastActive") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastActive") }
    }
}
