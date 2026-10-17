import SpriteKit
import SwiftUI

/// Hosts a game scene (the exterior or a room) in SwiftUI. Shared by the iPhone
/// and iPad app and the Mac menu-bar window. A new scene cross-fades in.
public struct RoomView: View {
    private let scene: SKScene
    private let fade: TimeInterval

    public init(scene: SKScene, fade: TimeInterval = 0.5) {
        self.scene = scene
        self.fade = fade
    }

    public var body: some View {
        SpriteView(scene: scene, transition: .crossFade(withDuration: fade), preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
            .accessibilityElement()
            .accessibilityLabel("Your home. Your cat is here.")
    }
}
