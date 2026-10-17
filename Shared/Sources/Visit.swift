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
            }
            // Build the room once the exterior is on screen, behind its first seconds.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Tuning.Exterior.roomBuildDelay))
                _ = self?.preparedRoom()
            }
        } else {
            scene = GameWorld.roomScene(size: size)
        }
    }

    private func preparedRoom() -> SKScene {
        if let room {
            return room
        }
        let built = GameWorld.roomScene(size: size)
        room = built
        return built
    }

    /// When the app was last in the foreground, kept on this device only (it decides the cold open, not game state).
    static var lastActive: Date? {
        get { UserDefaults.standard.object(forKey: "lastActive") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastActive") }
    }
}
