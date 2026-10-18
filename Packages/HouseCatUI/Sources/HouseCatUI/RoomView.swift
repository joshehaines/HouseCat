import SpriteKit
import SwiftUI

/// Hosts a game scene (the exterior or a room) in SwiftUI. Shared by the iPhone
/// and iPad app and the Mac menu-bar window. A new scene cross-fades in.
public struct RoomView: View {
    private let scene: SKScene
    private let fade: TimeInterval
    private let onFirstFrame: (() -> Void)?
    @State private var drawn = FirstFrame()

    /// Whether the first frame has been reported (a class, so the render callback can flip it once).
    private final class FirstFrame: @unchecked Sendable {
        var reported = false
    }

    /// `onFirstFrame` runs once the view has drawn its first scene.
    public init(scene: SKScene, fade: TimeInterval = 0.5, onFirstFrame: (() -> Void)? = nil) {
        self.scene = scene
        self.fade = fade
        self.onFirstFrame = onFirstFrame
    }

    public var body: some View {
        SpriteView(
            scene: scene,
            transition: .crossFade(withDuration: fade),
            preferredFramesPerSecond: 60,
            options: [.ignoresSiblingOrder],
            shouldRender: { [drawn] _ in
                if !drawn.reported, let onFirstFrame {
                    drawn.reported = true
                    DispatchQueue.main.async(execute: onFirstFrame)
                }
                return true
            }
        )
        .accessibilityElement()
        .accessibilityLabel("Your home. Your cat is here.")
    }
}
