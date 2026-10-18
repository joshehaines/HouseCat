import SpriteKit
import SwiftUI

/// Hosts a game scene (the exterior or a room) in SwiftUI. Shared by the iPhone
/// and iPad app and the Mac menu-bar window. A new scene cross-fades in.
public struct RoomView: View {
    private let scene: SKScene
    private let fade: TimeInterval
    private let onFirstFrame: (() -> Void)?
    private let label: String
    private let actions: [Action]
    @State private var drawn = FirstFrame()

    /// Something VoiceOver can do in the scene (pet the cat).
    public struct Action {
        public var name: String
        public var run: () -> Void

        public init(_ name: String, run: @escaping () -> Void) {
            self.name = name
            self.run = run
        }
    }

    /// Whether the first frame has been reported (a class, so the render callback can flip it once).
    private final class FirstFrame: @unchecked Sendable {
        var reported = false
    }

    /// `onFirstFrame` runs once the view has drawn its first scene.
    public init(
        scene: SKScene,
        fade: TimeInterval = 0.5,
        label: String = "Your home. Your cat is here.",
        actions: [Action] = [],
        onFirstFrame: (() -> Void)? = nil
    ) {
        self.label = label
        self.actions = actions
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
        .accessibilityLabel(label)
        // VoiceOver: the cat is a picture in a game scene, so what a tap on it does is an action here.
        .accessibilityActions {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.name, action: action.run)
            }
        }
    }
}
