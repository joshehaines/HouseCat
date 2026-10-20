#if canImport(AppKit)
    import AppKit
    @testable import HouseCatUI
    import SpriteKit
    import SwiftUI
    import Testing

    @MainActor
    private final class Holder: ObservableObject {
        @Published var scene: SKScene? = SKScene(size: CGSize(width: 100, height: 100))
    }

    private struct Host: View {
        @ObservedObject var holder: Holder

        var body: some View {
            ZStack {
                if let scene = holder.scene {
                    GameSceneView(scene: scene)
                }
            }
            .frame(width: 200, height: 200)
        }
    }

    @MainActor
    private func shownScene(in view: NSView) -> SKScene? {
        if let sprite = view as? SKView {
            return sprite.scene
        }
        return view.subviews.lazy.compactMap { shownScene(in: $0) }.first
    }

    /// Play, finish, play again, as Zoomies' Run again and a quick game's Again do: the old scene goes and a new one
    /// comes in the same moment, and the new one must be the one on screen (Josh, 20 Oct: "Zoomies bugged out when I
    /// tried again and the cat didn't run again"). With SpriteView alone this fails: it keeps the first scene, and the
    /// new one is never shown or run. (The test runner draws no frames, so that the new run's cat runs is checked in
    /// the simulator, `UITests/GamesTests`.)
    @MainActor
    @Test func aNewRunsSceneIsTheOneShown() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let holder = Holder()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Host(holder: holder))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let first = holder.scene
        #expect(shownScene(in: window.contentView!) === first)
        holder.scene = nil
        let again = SKScene(size: CGSize(width: 100, height: 100))
        holder.scene = again
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        #expect(shownScene(in: window.contentView!) === again, "the new run's scene is on screen")
        window.orderOut(nil)
    }
#endif
