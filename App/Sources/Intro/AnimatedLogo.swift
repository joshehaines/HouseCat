import AVFoundation
import HouseCatCore
import HouseCatGame
import SpriteKit
import SwiftUI

/// The HouseCat logo with Midnight bounding onto it and curling up asleep on the letters (HouseCatGame `LogoScene`):
/// the wordmark's picture in its box, and the cat over it, running out past the box's sides to the edge of the screen
/// and well above it, so the cat comes in from off screen and has room to leap. The launch and the intro play the
/// scene's films (`LaunchFilm`, rendered with the generated film of the cat landing and curling up; the launch's plays
/// on while the app is busy building the home), and once the cat is asleep it breathes. Without the films the scene
/// plays itself; with Reduce Motion the cat is already asleep there, still.
struct AnimatedLogo<Picture: View>: View {
    let act: LogoScene.Act
    let ink: LogoScene.Ink
    /// The wordmark in its box (`assets/brand/logo/wordmark_on_*.png`, or the launch screen's copy of it).
    @ViewBuilder let picture: Picture

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: LogoScene?
    @State private var film: AVPlayer?
    /// The film has ended on the cat asleep: it breathes.
    @State private var breathing = false

    var body: some View {
        picture
            .overlay {
                GeometryReader { geometry in
                    let box = geometry.size
                    if let film {
                        // The film's box sits over the picture; the film runs on past it to the left and above.
                        let logo = Tuning.Logo.self
                        let size = CGSize(
                            width: box.width * CGFloat(logo.filmLeft + logo.filmRight),
                            height: box.height * CGFloat(logo.filmHeight)
                        )
                        LaunchFilmView(player: film)
                            .frame(width: size.width, height: size.height)
                            // A breath: the film drawn a little taller and back, from the cat's feet.
                            .scaleEffect(x: 1, y: breathing ? 1 + CGFloat(Tuning.Puppet.breathSleep[0]) : 1, anchor: Self.feet)
                            .animation(
                                breathing ? .easeInOut(duration: 0.5 / Tuning.Puppet.breathSleep[1])
                                    .repeatForever(autoreverses: true) : nil,
                                value: breathing
                            )
                            .position(x: size.width / 2 - box.width * CGFloat(logo.filmLeft), y: box.height - size.height / 2)
                            .allowsHitTesting(false)
                            .onReceive(NotificationCenter.default.publisher(
                                for: AVPlayerItem.didPlayToEndTimeNotification,
                                object: film.currentItem
                            )) { _ in
                                breathing = true
                            }
                    } else if let scene {
                        // Out to the screen's edges on both sides (the box is centred, or near the left on the intro).
                        let side = max(0, geometry.frame(in: .global).minX)
                        let above = box.height * CGFloat(Tuning.Logo.headroom)
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
                guard scene == nil, film == nil else { return }
                if !reduceMotion, let player = act == .launch ? LaunchFilm.player(dark: ink == .dark) : LaunchFilm.intro() {
                    film = player
                    return
                }
                guard let art = GameWorld.art, let rig = GameWorld.rig else { return }
                scene = LogoScene(
                    size: CGSize(width: 1024, height: 512),
                    art: art,
                    rig: rig,
                    ink: ink,
                    act: reduceMotion ? .still : act,
                    catArt: GameWorld.catArt
                )
            }
    }

    /// Where the cat lies in the film's frame, which a breath grows from.
    private static var feet: UnitPoint {
        let logo = Tuning.Logo.self
        return UnitPoint(
            x: (logo.filmLeft + logo.bed / logo.boxSize[0]) / (logo.filmLeft + logo.filmRight),
            y: 1 - logo.valleyTop / logo.boxSize[1] / logo.filmHeight
        )
    }
}
