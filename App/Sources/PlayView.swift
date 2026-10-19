import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Play (SPEC "Care": the mini-games, five plays a day): the three games, each with what it asks and its stars.
struct PlayPicker: View {
    let games: [MinigamesFile.Game]
    let playsLeft: Int
    let choose: (MinigamesFile.Game) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                PaintedIcon("play_laser_dot", size: 36)
                Text("Play").font(Theme.title(30))
                Spacer()
                Text("\(playsLeft) of \(Tuning.MiniGames.playsPerDay) plays left today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(games, id: \.id) { game in
                    Button {
                        choose(game)
                    } label: {
                        card(game)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 760)
        .paper(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) { CloseButton(action: close).offset(x: 10, y: -10) }
        .foregroundStyle(Theme.ink)
    }

    private func card(_ game: MinigamesFile.Game) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let picture = CatScreens.picture(MiniGameView.art(game.id)) {
                    picture.resizable().scaledToFit()
                }
            }
            .frame(height: 70)
            .frame(maxWidth: .infinity)
            Text(game.name).font(Theme.title(19))
            Text(MiniGameView.howTo(game.id)).font(.caption).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                PaintedIcon("clock", size: 16)
                Text("\(game.durationSeconds) s").font(.caption.weight(.semibold))
                Spacer()
                ForEach(0 ..< 3, id: \.self) { _ in PaintedIcon("xp_star", size: 14) }
            }
        }
        .padding(14)
        .frame(width: 220, height: 210, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
    }
}

/// One game: a countdown with the cat's line, the game with its clock, score and stars, then what it paid.
struct MiniGameView: View {
    let game: MinigamesFile.Game
    let catName: String
    /// Back to the room, with what the last game paid (nil when left before the end).
    let done: (GameSession.Reward?) -> Void

    @State private var scene: MiniGameScene?
    @State private var progress = MiniGameScene.Progress(elapsed: 0, duration: 1, score: 0)
    @State private var countdown = 3
    @State private var startLine: String?
    @State private var reward: GameSession.Reward?
    @State private var stars = 0
    @State private var finished = false

    static func art(_ id: String) -> String {
        switch id {
        case "knock_it_off": "gifts/gift_keepsakes_little_ceramic_fish.png"
        case "string_chase": "fx/reactions/fx_reactions_sparkle.png"
        default: "ui/icon_play_laser_dot.png"
        }
    }

    static func howTo(_ id: String) -> String {
        switch id {
        case "knock_it_off": "Tap when the paw is over something. Hits in a row count double the fun."
        case "string_chase": "Draw a string with your finger. The cat follows it to the sparkles."
        default: "Drag the dot and keep it moving. The cat scores while it's on it."
        }
    }

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
            } else {
                Theme.paper.ignoresSafeArea()
            }
            VStack {
                hud
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            if countdown > 0, !finished {
                VStack(spacing: 10) {
                    Text("\(countdown)").font(.system(size: 88, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        .contentTransition(.numericText(countsDown: true))
                    if let startLine {
                        GreetingBubble(startLine, name: catName).frame(maxWidth: 420)
                    }
                    Text(Self.howTo(game.id)).font(.headline).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                }
            }
            if finished {
                Color.black.opacity(0.35).ignoresSafeArea()
                results
            }
        }
        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
        .task { await run() }
        // The games have their own sounds: the music waits in the room.
        .onAppear { Music.hush(.miniGame, true) }
        .onDisappear { Music.hush(.miniGame, false) }
    }

    private var hud: some View {
        HStack(spacing: 14) {
            Text(game.name).font(Theme.title(20))
            ProgressView(value: min(progress.elapsed / max(progress.duration, 1), 1))
                .tint(Theme.accent)
                .frame(maxWidth: 220)
            Text(scoreText(progress.score)).font(.system(size: 18, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
            HStack(spacing: 2) {
                ForEach(0 ..< 3, id: \.self) { index in
                    PaintedIcon("xp_star", size: 22)
                        .opacity(MiniGameRules.stars(score: progress.score, thresholds: game.stars) > index ? 1 : 0.25)
                }
            }
            Spacer()
            CloseButton {
                // Leaving early records nothing (no play is used).
                done(nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .paper(Capsule())
        .foregroundStyle(Theme.ink)
    }

    private func scoreText(_ score: Double) -> String {
        game.id == "laser_pointer" ? "\(Int(score)) s" : "\(Int(score)) of 5"
    }

    private var results: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { index in
                    PaintedIcon("xp_star", size: 54)
                        .opacity(stars > index ? 1 : 0.22)
                        .scaleEffect(stars > index ? 1 : 0.8)
                }
            }
            Text(stars == 3 ? "Perfect!" : stars > 0 ? "Well played" : "Good try").font(Theme.title(28))
            Text(scoreText(progress.score)).font(.headline).foregroundStyle(Theme.inkSoft)
            if let reward, reward.beans == 0, reward.xp == 0 {
                Text("Today's five plays are used, so this one was just for fun. Back tomorrow for Beans.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            if let reward {
                HStack(spacing: 16) {
                    if reward.beans > 0 {
                        Label { Text("+\(reward.beans)") } icon: { PaintedIcon("bean_coin", size: 22) }
                    }
                    if reward.xp > 0 {
                        Label { Text("+\(reward.xp) XP") } icon: { PaintedIcon("xp_star", size: 22) }
                    }
                }
                .font(.headline)
                if let line = reward.line {
                    GreetingBubble(line, name: catName).frame(maxWidth: 420)
                }
            }
            HStack(spacing: 12) {
                HUDButton("Back to the room", icon: "house") { done(reward) }
                let left = GameSession.shared.playsLeft
                if left > 0 {
                    HUDButton("Again · \(left) left", icon: "play_laser_dot", prominent: true) {
                        Task { await restart() }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .paper(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(Theme.ink)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// Another play of the same game.
    private func restart() async {
        withAnimation(.easeOut(duration: 0.2)) { finished = false }
        reward = nil
        stars = 0
        countdown = 3
        scene = nil
        await run()
    }

    /// The scene, the countdown, the game, the reward.
    private func run() async {
        guard scene == nil, let art = GameWorld.art, let catArt = GameWorld.catArt, let rig = GameWorld.rig else { return }
        let session = GameSession.shared
        let state = session.state(at: session.now())
        let cat = state.cats.first
        let personality = cat?.personality ?? .aloof
        let model: MiniGameScene.Game
        switch game.id {
        case "knock_it_off":
            model = .knock(KnockItOff(duration: Double(game.durationSeconds), personality: personality))
        case "string_chase":
            var seed = session.miniGameSeed(game.id)
            model = .string(StringChase(duration: Double(game.durationSeconds), personality: personality, seed: &seed))
        default:
            model = .laser(LaserChase(duration: Double(game.durationSeconds), personality: personality))
        }
        let tiles = session.livingRoomTiles()
        let made = MiniGameScene(
            size: CGSize(width: 1024, height: 600),
            game: model,
            art: art,
            catArt: catArt,
            rig: rig,
            look: cat?.look ?? .midnight,
            floor: tiles.floor,
            wall: tiles.wall,
            objects: Tuning.MiniGames.shelfThings.map { "gifts/\($0).png" }
        )
        made.onProgress = { progress = $0 }
        made.onMoment = { moment in
            switch moment {
            case .hit: Sound.play("ui_knock_off", volume: Tuning.Sound.place)
            case .miss: Sound.tap()
            case .sparkle: Sound.play("ui_sparkle", volume: Tuning.Sound.place)
            }
            #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: moment == .miss ? .soft : .medium).impactOccurred()
            #endif
        }
        made.onFinish = { score in finish(score) }
        #if DEBUG
            made.autoplay = ProcessInfo.processInfo.environment["HOUSECAT_AUTOPLAY"] != nil
        #endif
        progress = MiniGameScene.Progress(elapsed: 0, duration: Double(game.durationSeconds), score: 0)
        scene = made
        startLine = session.line("play.start")
        Sound.play("cat_chirp", volume: Tuning.Sound.meow)
        for count in stride(from: 3, through: 1, by: -1) {
            withAnimation { countdown = count }
            try? await Task.sleep(for: .seconds(0.8))
        }
        withAnimation { countdown = 0 }
        made.start()
        if game.id == "laser_pointer" {
            Sound.play("cat_zoomies_thumps", volume: Tuning.Sound.place)
        }
    }

    private func finish(_ score: Double) {
        stars = MiniGameRules.stars(score: score, thresholds: game.stars)
        reward = GameSession.shared.playMiniGame(game.id, stars: stars)
        Sound.play(stars > 0 ? "ui_streak_milestone" : "cat_meow_soft", volume: Tuning.Sound.levelUp)
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(stars > 0 ? .success : .warning)
        #endif
        withAnimation(.spring(duration: 0.4)) { finished = true }
    }
}
