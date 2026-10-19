import HouseCatCore
import HouseCatGame
import SpriteKit
import SwiftUI

/// The HouseCat logo with Midnight bounding onto it and curling up asleep on the letters (HouseCatGame `LogoScene`):
/// the wordmark's picture in its box, and the cat's scene over it, running out past the box's sides to the edge of the
/// screen and well above it, so the cat comes in from off screen and has room to leap. With Reduce Motion the cat is
/// already asleep there, still.
struct AnimatedLogo<Picture: View>: View {
    let act: LogoScene.Act
    let ink: LogoScene.Ink
    /// The wordmark in its box (`assets/brand/logo/wordmark_on_*.png`, or the launch screen's copy of it).
    @ViewBuilder let picture: Picture

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: LogoScene?

    var body: some View {
        picture
            .overlay {
                GeometryReader { geometry in
                    let box = geometry.size
                    // Out to the screen's edges on both sides (the box is centred, or near the left on the intro).
                    let side = max(0, geometry.frame(in: .global).minX)
                    let above = box.height * CGFloat(Tuning.Logo.headroom)
                    if let scene {
                        SpriteView(scene: scene, options: [.allowsTransparency])
                            .frame(width: box.width + 2 * side, height: box.height + above)
                            .position(x: box.width / 2, y: box.height - (box.height + above) / 2)
                            .allowsHitTesting(false)
                            .onChange(of: CGRect(x: side, y: 0, width: box.width, height: box.height), initial: true) { _, rect in
                                scene.box = rect
                            }
                    }
                }
            }
            .onAppear {
                guard scene == nil, let art = GameWorld.art, let rig = GameWorld.rig else { return }
                scene = LogoScene(
                    size: CGSize(width: 1024, height: 512),
                    art: art,
                    rig: rig,
                    ink: ink,
                    act: reduceMotion ? .still : act
                )
            }
    }
}
