import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Zoomies (the Games menu's runner): the scene full screen, the biscuits, mice and score along the top, a short
/// count with how to play, and the results card (its Beans for the day's first three runs, the best, the challenges).
struct ZoomiesView: View {
    let catName: String
    let back: () -> Void
    @State private var scene: ZoomiesScene?
    @State private var progress = ZoomiesScene.Progress()
    @State private var countdown = 3
    @State private var showHowTo = true
    @State private var finished = false
    @State private var reward: GameSession.ArcadeReward?
    @State private var result: ZoomiesRun?
    @State private var paused = false

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder]).ignoresSafeArea()
            } else {
                GamesPaper()
            }
            // The HUD and cards scale with the screen (an iPad's are larger), the run itself fills it.
            GamesScaled {
                ZStack {
                    VStack {
                        hud
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    if countdown > 0, !finished {
                        countIn
                    }
                    if paused, !finished {
                        pauseCard
                    }
                }
            }
            if finished, let result {
                Color.black.opacity(0.35).ignoresSafeArea()
                GamesScaled { results(result) }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
        .task { await start() }
    }

    private var hud: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                art("arcade/ui/icon_game_biscuit.png", 30)
                Text("\(progress.biscuits)").font(.system(size: 21, weight: .heavy, design: .rounded)).monospacedDigit()
                art("arcade/ui/icon_game_mouse.png", 30)
                Text("\(progress.mice)").font(.system(size: 21, weight: .heavy, design: .rounded)).monospacedDigit()
                Divider().frame(height: 24)
                Text(progress.score.formatted()).font(Theme.title(21)).monospacedDigit()
                    .contentTransition(.numericText()).animation(.spring(duration: 0.25), value: progress.score)
                let best = GameSession.shared.arcade.best[ArcadeGame.zoomies.rawValue] ?? 0
                if best > 0 {
                    Text("best \(best.formatted())").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                }
                StarsRow(count: Tuning.Arcade.Zoomies.stars.filter { progress.score >= $0 }.count, size: 18)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .paper(Capsule())
            if progress.catnip > 0 || progress.shield {
                HStack(spacing: 6) {
                    if progress.catnip > 0 {
                        art("arcade/ui/icon_game_catnip.png", 24)
                        ProgressView(value: progress.catnip).tint(GamesLook.green).frame(width: 54)
                    }
                    if progress.shield {
                        art("arcade/ui/icon_game_box.png", 24)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .paper(Capsule())
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            Button {
                paused = true
                scene?.pause(true)
            } label: {
                Image(systemName: "pause.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36).paper(Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Pause")
        }
        .foregroundStyle(Theme.ink)
        .animation(.spring(duration: 0.3), value: progress.catnip > 0)
    }

    private func art(_ path: String, _ size: CGFloat) -> some View {
        Group {
            if let picture = GamesLook.picture(path) {
                picture.resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }

    private var countIn: some View {
        VStack(spacing: 12) {
            Text("\(countdown)").font(.system(size: 84, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .contentTransition(.numericText(countsDown: true))
            if showHowTo {
                HStack(spacing: 16) {
                    howTo("arrow.up.arrow.down", "Swipe up or down: change lane")
                    howTo("hand.tap", "Tap: jump")
                    howTo("hand.point.down", "Hold: slide under")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.ink.opacity(0.78)))
            }
        }
        .allowsHitTesting(false)
    }

    private func howTo(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
    }

    private var pauseCard: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Paused").font(Theme.title(28))
                HStack(spacing: 12) {
                    HUDButton("Leave", symbol: "xmark") { back() }
                    ChunkyButton("Carry on", colour: GamesLook.green) {
                        paused = false
                        scene?.pause(false)
                    }
                }
                Text("Leaving ends the run without paying.").font(.footnote).foregroundStyle(Theme.inkSoft)
            }
            .padding(24)
            .goldCard(corner: 24)
            .foregroundStyle(Theme.ink)
        }
    }

    private func results(_ run: ZoomiesRun) -> some View {
        let stars = run.stars
        var lines: [String] = ["\(run.biscuits) biscuits · \(run.mice) mice · \(Int(run.distance)) metres"]
        if reward?.payout.newBest == true {
            lines.append("A new best!")
        }
        if reward?.payout.paidPlay == nil {
            lines.append("Today's three paid runs are done, so this one was for fun. Back tomorrow for Beans.")
        } else if let play = reward?.payout.paidPlay {
            lines.append("Paid run \(play) of \(Tuning.Arcade.paidPlaysPerDay) today")
        }
        return GamesResultCard(
            title: stars == 3 ? "Zoomies!" : stars > 0 ? "What a run" : "Good try",
            subtitle: "\(run.score.formatted()) points",
            stars: stars,
            reward: reward,
            catName: catName,
            lines: lines,
            buttons: [("Back", false, back), ("Run again", true, { Task { await restart() } })]
        )
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: Running

    private func start() async {
        guard scene == nil, let art = GameWorld.art, let catArt = GameWorld.catArt, let rig = GameWorld.rig else { return }
        let session = GameSession.shared
        let cat = session.cat
        let made = ZoomiesScene(size: CGSize(width: 956, height: 440), seed: session.arcadeSeed(.zoomies), art: art, catArt: catArt,
                                rig: rig, look: cat?.look ?? .midnight, outfit: session.wornOutfit)
        made.onProgress = { next in
            let starsBefore = Tuning.Arcade.Zoomies.stars.filter { progress.score >= $0 }.count
            progress = next
            if Tuning.Arcade.Zoomies.stars.filter({ next.score >= $0 }).count > starsBefore {
                Sound.play("ui_bean_chime", volume: Tuning.Sound.levelUp)
            }
        }
        made.onBeat = { beat in hear(beat) }
        made.onFinish = { run in finish(run) }
        #if DEBUG
            made.autoplay = ProcessInfo.processInfo.environment["HOUSECAT_AUTOPLAY"] != nil
        #endif
        scene = made
        Sound.play("cat_chirp", volume: Tuning.Sound.meow)
        for count in stride(from: 3, through: 1, by: -1) {
            withAnimation { countdown = count }
            Sound.play("ui_tap", volume: Tuning.Sound.levelUp)
            try? await Task.sleep(for: .seconds(0.7))
        }
        withAnimation { countdown = 0 }
        made.start()
    }

    private func restart() async {
        withAnimation(.easeOut(duration: 0.2)) { finished = false }
        reward = nil
        result = nil
        progress = ZoomiesScene.Progress()
        showHowTo = false
        scene = nil
        countdown = 3
        await start()
    }

    private func hear(_ beat: ZoomiesBeat) {
        switch beat {
        case let .collected(item):
            switch item.thing {
            case .biscuit: Sound.play("ui_bean_chime", volume: Tuning.Sound.tap)
            case .mouse: Sound.play("cat_chirp", volume: Tuning.Sound.meow)
            default: Sound.play("ui_sparkle", volume: Tuning.Sound.levelUp)
            }
        case .shieldUsed:
            Sound.play("ui_knock_off", volume: Tuning.Sound.place)
        case .bumped:
            Sound.play("ui_knock_off", volume: Tuning.Sound.place)
            #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            #endif
        case .zone:
            Sound.play("ui_place_item", volume: Tuning.Sound.tap)
        }
    }

    private func finish(_ run: ZoomiesRun) {
        reward = GameSession.shared.finishArcade(ArcadeResult(game: .zoomies, score: run.score, stars: run.stars, won: run.stars > 0,
                                                              stats: run.stats))
        result = run
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(run.stars > 0 ? .success : .warning)
        #endif
        withAnimation(.spring(duration: 0.4)) { finished = true }
    }
}
