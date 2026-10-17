import Foundation
import HouseCatCore
import HouseCatGame
import SpriteKit
#if canImport(UIKit)
    import UIKit
#endif

/// Loads the bundled art and content and builds the game's scenes.
@MainActor
enum GameWorld {
    static let content: ContentBundle? = Bundle.main.url(forResource: "Content", withExtension: nil)
        .flatMap { try? ContentBundle.load(from: $0) }
    static let art: ArtLibrary? = try? ArtLibrary(bundle: .main)

    /// The living room with the demo layout and the cat arriving, or a blank scene if the art is missing.
    static func roomScene(size: CGSize, arrive: Bool = true) -> SKScene {
        guard let art, let content, let model = try? art.data("rooms/layout_living_demo.json", as: RoomModel.self),
              let rig = try? art.data("cat/rig.json", as: PuppetRig.self)
        else {
            return SKScene(size: size)
        }
        let scene = RoomScene(size: size, art: art, content: content, model: model)
        scene.addCat(rig: rig, at: 4.6, 4.8, pose: .loafThreeQuarterFront)
        if arrive {
            scene.playArrival(then: nextChoice(in: scene, content: content), onRub: purr, onDone: {})
        }
        return scene
    }

    /// What the cat does next, from the behaviour table (HouseCatCore owns the rule).
    static func nextChoice(in scene: RoomScene, content: ContentBundle) -> BehaviourChoice {
        let clock = DayClock()
        let now = Date()
        let available = scene.model.items.reduce(into: Set<Affordance>()) { result, placement in
            result.formUnion(content.affordances[placement.id] ?? [])
        }
        let context = BehaviourContext(
            mood: .content,
            weather: .sun,
            personality: .velcro,
            timeOfDay: TimeOfDay.at(localMinutes: clock.localMinutes(of: now), clock: clock),
            available: available.subtracting([.none]),
            sunlit: true
        )
        var rng = DaySeed(household: 1, day: clock.day(of: now), purpose: "brain", salt: "arrival")
        return BehaviourTable.choose(context, rng: &rng)
    }

    /// The rub along the bottom edge: a soft haptic (the purr sound joins with the audio step).
    static func purr() {
        #if canImport(UIKit) && !os(watchOS)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}
