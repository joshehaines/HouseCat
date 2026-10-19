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

    /// Whether the first frame has been reported (a class, so the scene's action can flip it once).
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
            options: [.ignoresSiblingOrder]
        )
        // The first frame is the first time SpriteKit runs the scene's actions, which it does as it draws it. (It was
        // SpriteView's shouldRender, which on some launches is never called, so the launch curtain never lifted:
        // 19 Oct, a new player's first visit.)
        .task(id: ObjectIdentifier(scene)) {
            guard let onFirstFrame, !drawn.reported else { return }
            let (frames, frame) = AsyncStream.makeStream(of: Void.self)
            scene.run(.run {
                frame.yield()
                frame.finish()
            }, withKey: "firstFrame")
            for await _ in frames {}
            guard !Task.isCancelled, !drawn.reported else { return }
            drawn.reported = true
            onFirstFrame()
        }
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
