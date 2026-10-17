import SpriteKit
import SwiftUI

/// Hosts a game scene (the exterior or a room) in SwiftUI. Shared by the iPhone
/// and iPad app and the Mac menu-bar window.
public struct RoomView: View {
    private let scene: SKScene

    public init(scene: SKScene) {
        self.scene = scene
    }

    public var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
            .accessibilityElement()
            .accessibilityLabel("Living room. Your cat is here.")
    }
}
