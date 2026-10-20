import SpriteKit
import SwiftUI

/// A game's SpriteKit scene in SwiftUI (Zoomies, Catapult, Purrfect Match, the quick games), made again for each new
/// scene. SwiftUI's SpriteView keeps showing the first scene it was given: handed a new one it never presents it, so
/// the new scene never moves (Josh, 20 Oct: "Zoomies bugged out when I tried again and the cat didn't run again";
/// Run again made a new run's scene, and the old one stayed on screen with the cat sitting). Keyed by the scene, each
/// new one gets a SpriteView of its own.
public struct GameSceneView: View {
    private let scene: SKScene
    private let options: SpriteView.Options

    public init(scene: SKScene, options: SpriteView.Options = [.ignoresSiblingOrder]) {
        self.scene = scene
        self.options = options
    }

    public var body: some View {
        SpriteView(scene: scene, options: options)
            .id(ObjectIdentifier(scene))
    }
}
