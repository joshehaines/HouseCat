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
    @ObservationIgnored private var arrival: GameSession.Arrival?
    @ObservationIgnored private let size: CGSize
    @ObservationIgnored private var room: SKScene?

    init(size: CGSize, now: Date = Date(), lastActive: Date?) {
        self.size = size
        if ArrivalRules.showsExterior(lastActive: lastActive, now: now), let exterior = GameWorld.exteriorScene(size: size, at: now) {
            scene = exterior
            exterior.onEnter = { [weak self, weak exterior] in
                guard let self else { return }
                let room = preparedRoom()
                // Present from the exterior's own view so the push flows straight into the room.
                exterior?.view?.presentScene(room, transition: .crossFade(withDuration: Tuning.Exterior.roomFadeSeconds))
                scene = room
                greet()
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
        }
    }

    /// Shows the greeting while the cat notices you, then lets it go (SPEC: three seconds at most).
    private func greet() {
        guard let line = arrival?.greeting else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.Arrival.noticeDelay))
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
            house.onDecorate = { GameSession.shared.record($0) }
            house.onSelect = { [weak self] in self?.selected = $0 }
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
