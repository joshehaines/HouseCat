import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Play (SPEC "Care": the mini-games, five plays a day): the four games, each with what it asks, how long it is and
/// the player's best.
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
            // In a row; on a small phone on its side the row scrolls.
            ViewThatFits(in: .horizontal) {
                cards
                ScrollView(.horizontal, showsIndicators: false) { cards }
            }
        }
        .padding(18)
        .frame(maxWidth: 760)
        .paper(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) { CloseButton(action: close).offset(x: 10, y: -10) }
        .foregroundStyle(Theme.ink)
    }

    /// Four cards fit across a phone on its side inside the Games menu (about 670 points there).
    private var cards: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(games, id: \.id) { game in button(game) }
        }
    }

    private func button(_ game: MinigamesFile.Game) -> some View {
        Button {
            choose(game)
        } label: {
            card(game)
        }
        .buttonStyle(PressStyle())
    }

    private func card(_ game: MinigamesFile.Game) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let picture = CatScreens.picture(MiniGameView.art(game.id)) {
                    picture.resizable().scaledToFit()
                }
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            Text(game.name).font(Theme.title(19))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(MiniGameView.howTo(game.id)).font(.caption).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // Two lines, so neither is cut short in a card this narrow: the length and the stars won, then the best.
            let best = MiniGameView.best(game.id)
            HStack(spacing: 4) {
                PaintedIcon("clock", size: 16)
                Text("\(game.durationSeconds) s").font(.caption.weight(.semibold)).fixedSize()
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        PaintedIcon("xp_star", size: 14)
                            .opacity(MiniGameRules.stars(score: Double(best), thresholds: game.stars) > index ? 1 : 0.3)
                    }
                }
            }
            Text(best > 0 ? "Best \(best)" : "Not played yet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(width: 156, height: 250, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
    }
}

/// One game: a quick count with the cat's line and the star targets, the game with its clock, score, combo and
/// stars filling, then what it paid.
struct MiniGameView: View {
    let game: MinigamesFile.Game
    let catName: String
    /// Back to the room, with what the last game paid (nil when left before the end).
    let done: (GameSession.Reward?) -> Void

    @State private var scene: MiniGameScene?
    @State private var progress = MiniGameScene.Progress(elapsed: 0, duration: 1, score: 0)
    @State private var countdown = 3
    @State private var going = false
    @State private var startLine: String?
    @State private var midLine: String?
    @State private var reward: GameSession.Reward?
    @State private var stars = 0
    /// The stars on the results card, popping in one at a time.
    @State private var shownStars = 0
    @State private var finished = false
    @State private var newBest = false
    @State private var saidCombo = false
    @State private var lastTick = 0

    static func art(_ id: String) -> String {
        switch id {
        case "knock_it_off": "gifts/gift_keepsakes_little_ceramic_fish.png"
        case "string_chase": "fx/reactions/fx_reactions_sparkle.png"
        case "hide_and_seek": "furniture/living/furn_living_box_R.png"
        default: "ui/icon_play_laser_dot.png"
        }
    }

    static func howTo(_ id: String) -> String {
        switch id {
        case "knock_it_off": "Tap as the cat reaches something to swipe it off. Hits in a row score more."
        case "string_chase": "Draw a string through the sparkles before they fade. Chain them quickly."
        case "hide_and_seek": "Watch for ears. Tap where the cat is hiding; quick finds score double."
        default: "Drag the dot. When the cat crouches, hold still and it pounces."
        }
    }

    /// The player's best score at a game, on this device.
    static func best(_ id: String) -> Int {
        UserDefaults.standard.integer(forKey: "minigame.best.\(id)")
    }

    private var left: Int {
        max(0, Int((progress.duration - progress.elapsed).rounded(.up)))
    }

    private var hurry: Bool {
        !finished && countdown == 0 && left <= 5
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
                if let midLine, !finished {
                    HStack {
                        GreetingBubble(midLine, name: catName).frame(maxWidth: 360)
                        Spacer()
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
            if countdown > 0 || going, !finished {
                countIn
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
        .onChange(of: left) { _, seconds in
            // The last five seconds tick.
            if hurry, seconds != lastTick, seconds > 0 {
                lastTick = seconds
                Sound.play("ui_tap", volume: Tuning.Sound.levelUp)
            }
        }
    }

    private var countIn: some View {
        VStack(spacing: 10) {
            Text(going ? "Go!" : "\(countdown)")
                .font(.system(size: 88, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .contentTransition(.numericText(countsDown: true))
            if let startLine {
                GreetingBubble(startLine, name: catName).frame(maxWidth: 420)
            }
            Text(Self.howTo(game.id)).font(.headline).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            HStack(spacing: 14) {
                ForEach(Array(game.stars.enumerated()), id: \.offset) { index, target in
                    HStack(spacing: 2) {
                        ForEach(0 ... index, id: \.self) { _ in PaintedIcon("xp_star", size: 16) }
                        Text("\(target)").font(.subheadline.weight(.heavy))
                    }
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        }
        .allowsHitTesting(false)
    }

    private var hud: some View {
        HStack(spacing: 14) {
            Text(game.name).font(Theme.title(20))
            Text("\(left)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(hurry ? Color(red: 0.86, green: 0.22, blue: 0.2) : Theme.ink)
                .scaleEffect(hurry ? 1.15 : 1)
                .animation(.spring(duration: 0.25), value: left)
                .frame(minWidth: 34)
            HStack(spacing: 6) {
                Text("\(Int(progress.score))").font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: Int(progress.score))
                if progress.multiplier > 1 || progress.zoomies {
                    comboBadge
                }
            }
            .frame(minWidth: 110, alignment: .leading)
            StarTrack(score: progress.score, thresholds: game.stars)
                .frame(width: 210, height: 28)
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

    private var comboBadge: some View {
        let zoom = progress.zoomies
        return Text(zoom ? "×\(progress.multiplier) Zoomies" : "×\(progress.multiplier)")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(zoom ? Color(red: 0.35, green: 0.68, blue: 0.3) : Theme.accent))
            .id(progress.multiplier)
            .transition(.scale(scale: 1.6).combined(with: .opacity))
    }

    private func scoreText(_ score: Double) -> String {
        "\(Int(score)) points"
    }

    private var results: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { index in
                    PaintedIcon("xp_star", size: 54)
                        .opacity(shownStars > index ? 1 : 0.22)
                        .scaleEffect(shownStars > index ? 1 : 0.8)
                        .animation(.spring(duration: 0.35, bounce: 0.55), value: shownStars)
                }
            }
            Text(stars == 3 ? "Perfect!" : stars > 0 ? "Well played" : "Good try").font(Theme.title(28))
            HStack(spacing: 10) {
                Text(scoreText(progress.score)).font(.headline)
                if newBest {
                    Text("New best!")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            if progress.bestCombo > 1 {
                Text("Best combo \(progress.bestCombo) in a row").font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            if stars < 3 {
                Text("Next star at \(game.stars[stars])").font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
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
        shownStars = 0
        newBest = false
        saidCombo = false
        midLine = nil
        countdown = 3
        scene = nil
        await run()
    }

    /// The scene, the count, the game, the reward.
    private func run() async {
        guard scene == nil, let art = GameWorld.art, let catArt = GameWorld.catArt, let rig = GameWorld.rig else { return }
        let session = GameSession.shared
        let state = session.state(at: session.now())
        let cat = state.cats.first
        let personality = cat?.personality ?? .aloof
        let duration = Double(game.durationSeconds)
        var seed = session.miniGameSeed(game.id)
        let model: MiniGameScene.Game = switch game.id {
        case "knock_it_off": .knock(KnockItOff(duration: duration, personality: personality, seed: &seed))
        case "string_chase": .string(StringChase(duration: duration, personality: personality, seed: &seed))
        case "hide_and_seek": .hide(HideAndSeek(duration: duration, personality: personality, seed: &seed))
        default: .laser(LaserChase(duration: duration, personality: personality, seed: &seed))
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
            objects: Tuning.MiniGames.shelfThings.map { "gifts/\($0).png" },
            catnip: "gifts/\(Tuning.MiniGames.catnip).png"
        )
        made.onProgress = { next in
            let before = MiniGameRules.stars(score: progress.score, thresholds: game.stars)
            withAnimation(.spring(duration: 0.3)) { progress = next }
            if MiniGameRules.stars(score: next.score, thresholds: game.stars) > before {
                Sound.play("ui_bean_chime", volume: Tuning.Sound.levelUp)
            }
        }
        made.onBeat = { beat in hear(beat) }
        made.onFinish = { score in finish(score) }
        #if DEBUG
            made.autoplay = ProcessInfo.processInfo.environment["HOUSECAT_AUTOPLAY"] != nil
        #endif
        progress = MiniGameScene.Progress(elapsed: 0, duration: duration, score: 0)
        lastTick = 0
        scene = made
        startLine = session.line("play.start")
        Sound.play("cat_chirp", volume: Tuning.Sound.meow)
        for count in stride(from: 3, through: 1, by: -1) {
            withAnimation { countdown = count }
            Sound.play("ui_tap", volume: Tuning.Sound.levelUp)
            try? await Task.sleep(for: .seconds(Tuning.MiniGames.countSeconds))
        }
        withAnimation {
            countdown = 0
            going = true
        }
        made.start()
        Sound.play("ui_place_item", volume: Tuning.Sound.levelUp)
        try? await Task.sleep(for: .seconds(0.45))
        withAnimation(.easeOut(duration: 0.2)) { going = false }
    }

    /// A beat of the game heard and felt: its sound, a haptic, now and then the cat's line.
    private func hear(_ beat: PlayBeat) {
        #if canImport(UIKit)
            func bump(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
                UIImpactFeedbackGenerator(style: style).impactOccurred()
            }
        #endif
        switch beat {
        case let .scored(hit):
            if hit.golden {
                Sound.play("ui_bean_chime", volume: Tuning.Sound.levelUp)
            }
            switch game.id {
            case "knock_it_off": Sound.play("ui_knock_off", volume: Tuning.Sound.place)
            case "string_chase": Sound.play("ui_sparkle", volume: Tuning.Sound.place)
            case "hide_and_seek": Sound.play(hit.perfect ? "cat_trill" : "cat_chirp", volume: Tuning.Sound.meow)
            default: Sound.play(hit.perfect ? "ui_sparkle" : "ui_place_item", volume: Tuning.Sound.place)
            }
            #if canImport(UIKit)
                bump(hit.golden ? .heavy : hit.points >= 6 ? .medium : .light)
            #endif
            // The combo at its top for the first time this game: the cat says so.
            if !saidCombo, Combo.worth(hit.combo) == Tuning.MiniGames.comboCap {
                saidCombo = true
                say("play.combo", meow: "cat_chirp")
            }
        case .missed:
            Sound.play("ui_tap", volume: Tuning.Sound.place)
            #if canImport(UIKit)
                bump(.soft)
            #endif
        case .zoomies:
            Sound.play("cat_zoomies_thumps", volume: Tuning.Sound.place)
            #if canImport(UIKit)
                bump(.heavy)
            #endif
            say("play.zoomies", meow: "cat_trill")
        case .goldenAppeared:
            Sound.play("ui_sparkle", volume: Tuning.Sound.levelUp)
        case .rustled:
            Sound.play("ui_place_item", volume: Tuning.Sound.tap)
        case .cameOut:
            Sound.play("cat_meow_short", volume: Tuning.Sound.meow)
        case .comboLapsed, .zoomiesOver, .crouched, .sprang, .hid, .peeked:
            break
        }
    }

    /// The cat's line for a moment in the game, for a couple of seconds.
    private func say(_ context: String, meow: String) {
        guard let line = GameSession.shared.line(context) else { return }
        Sound.play(meow, volume: Tuning.Sound.meow)
        withAnimation(.spring(duration: 0.35)) { midLine = line }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if midLine == line {
                withAnimation(.easeOut(duration: 0.3)) { midLine = nil }
            }
        }
    }

    private func finish(_ score: Double) {
        stars = MiniGameRules.stars(score: score, thresholds: game.stars)
        reward = GameSession.shared.playMiniGame(game.id, stars: stars)
        let key = "minigame.best.\(game.id)"
        newBest = Int(score) > UserDefaults.standard.integer(forKey: key)
        if newBest {
            UserDefaults.standard.set(Int(score), forKey: key)
        }
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(stars > 0 ? .success : .warning)
        #endif
        withAnimation(.spring(duration: 0.4)) {
            midLine = nil
            finished = true
        }
        // The stars one at a time, each with its chime; the fanfare after the last.
        Task { @MainActor in
            for index in 0 ..< stars {
                try? await Task.sleep(for: .seconds(0.3))
                shownStars = index + 1
                Sound.play("ui_bean_chime", volume: Tuning.Sound.levelUp)
                #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            }
            try? await Task.sleep(for: .seconds(0.25))
            Sound.play(stars > 0 ? "ui_streak_milestone" : "cat_meow_soft", volume: Tuning.Sound.levelUp)
        }
    }
}

/// The stars filling as the score climbs: a bar to the third star's target with each star where its target is.
private struct StarTrack: View {
    let score: Double
    let thresholds: [Int]

    var body: some View {
        GeometryReader { proxy in
            let top = Double(thresholds.last ?? 1)
            let width = proxy.size.width - 14
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.14)).frame(height: 8).padding(.horizontal, 7)
                Capsule().fill(Theme.accent)
                    .frame(width: max(8, width * min(1, score / top) + 7), height: 8)
                    .padding(.leading, 7)
                    .animation(.spring(duration: 0.3), value: score)
                ForEach(Array(thresholds.enumerated()), id: \.offset) { _, target in
                    let reached = score >= Double(target)
                    PaintedIcon("xp_star", size: 24)
                        .opacity(reached ? 1 : 0.35)
                        .scaleEffect(reached ? 1.1 : 0.85)
                        .animation(.spring(duration: 0.35, bounce: 0.6), value: reached)
                        .position(x: 7 + width * Double(target) / top, y: proxy.size.height / 2)
                }
            }
        }
    }
}
