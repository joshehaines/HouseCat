import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Purrfect Match (the Games menu's match-three): the sixty levels in rows with their stars, the next one ringed;
/// a level opens once the one before it is cleared.
struct MatchScreen: View {
    let catName: String
    let back: () -> Void
    @State private var playing: MatchLevel?
    @State private var tick = 0

    var body: some View {
        ZStack {
            if let level = playing {
                MatchPlay(level: level, catName: catName) { next in
                    tick += 1
                    playing = next
                }
                .id(tick)
                .transition(.move(edge: .trailing))
            } else {
                GamesFrame { picker }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: tick)
        #if DEBUG
            .onAppear {
                if let id = ProcessInfo.processInfo.environment["HOUSECAT_LEVEL"].flatMap(Int.init),
                   let level = GameSession.arcadeContent?.match.levels.first(where: { $0.id == id }) {
                    playing = level
                }
            }
        #endif
    }

    private var picker: some View {
        let arcade = GameSession.shared.arcade
        let levels = GameSession.arcadeContent?.match.levels ?? []
        let next = arcade.nextLevel(.match)
        return VStack(spacing: 0) {
            GamesPlank(title: GameSession.arcadeContent?.file.game(.match)?.name ?? "Purrfect Match", icon: "arcade/ui/tile_match.png",
                       back: back) {
                GamesPill(icon: "ui/icon_xp_star.png", value: "\(arcade.totalStars(.match))", label: "of \(Tuning.Arcade.matchLevels * 3)")
            }
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(levels, id: \.id) { level in
                            levelButton(level, arcade: arcade, isNext: level.id == next).id(level.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .onAppear { reader.scrollTo(max(0, next - 6), anchor: .top) }
            }
        }
        .id(tick)
        .foregroundStyle(Theme.ink)
    }

    private func levelButton(_ level: MatchLevel, arcade: ArcadeState, isNext: Bool) -> some View {
        let open = arcade.isOpen(.match, level: level.id)
        let stars = arcade.stars(.match, level: level.id)
        return Button {
            guard open else { return }
            playing = level
        } label: {
            VStack(spacing: 3) {
                if open {
                    Text("\(level.id + 1)").font(.system(size: 24, weight: .heavy, design: .rounded))
                } else {
                    PaintedIcon("padlock", size: 26)
                }
                Text(level.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(Theme.inkSoft)
                StarsRow(count: stars, size: 13).opacity(open ? 1 : 0)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .goldCard(corner: 14)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isNext ? GamesLook.green : .clear, lineWidth: 3.5))
            .opacity(open ? 1 : 0.55)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(open ? "Level \(level.id + 1), \(level.title), \(stars) stars" : "Level \(level.id + 1), locked")
    }
}

/// One Purrfect Match level: the goals, the moves and the stars on the left with the cat, the board on the right.
struct MatchPlay: View {
    let level: MatchLevel
    let catName: String
    let done: (MatchLevel?) -> Void
    @State private var scene: MatchScene?
    @State private var progress = MatchScene.Progress()
    @State private var finished: MatchGame?
    @State private var reward: GameSession.ArcadeReward?
    @State private var cheer = false

    var body: some View {
        GamesFrame {
            ZStack {
                HStack(spacing: 14) {
                    side
                        .frame(width: 290)
                    if let scene {
                        GameSceneView(scene: scene, options: [.allowsTransparency, .ignoresSiblingOrder])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                if let finished {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    results(finished)
                }
            }
        }
        .task { start() }
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { done(nil) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34).paper(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Levels")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Level \(level.id + 1)").font(.caption.weight(.heavy)).foregroundStyle(GamesLook.match)
                    Text(level.title).font(Theme.title(19)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(spacing: -2) {
                    Text("\(progress.movesLeft)").font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true)).animation(.spring(duration: 0.25), value: progress.movesLeft)
                    Text("MOVES").font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(Circle().fill(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom)))
                .shadow(color: GameHUD.deepGold.mix(with: .black, by: 0.3), radius: 0, y: 3)
            }
            HStack(spacing: 12) {
                ForEach(level.parsedGoals, id: \.self) { goal in
                    HStack(spacing: 4) {
                        goalPicture(goal).frame(width: 40, height: 40)
                        let left = progress.remaining[goal] ?? 0
                        if left == 0 {
                            Image(systemName: "checkmark").font(.system(size: 18, weight: .heavy)).foregroundStyle(GamesLook.green)
                        } else {
                            Text("\(left)").font(Theme.title(21)).monospacedDigit()
                        }
                    }
                }
            }
            starBar
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                if let cat = GameSession.shared.cat, let portrait = CatScreens.portrait(cat.look) {
                    Image(decorative: portrait, scale: 1).resizable().scaledToFit().frame(height: 130)
                        .scaleEffect(cheer ? 1.08 : 1, anchor: .bottom)
                        .animation(.spring(duration: 0.3, bounce: 0.6), value: cheer)
                }
                Text(howTo).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .padding(10)
                    .goldCard(corner: 12)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .goldCard(corner: 22)
        .foregroundStyle(Theme.ink)
    }

    private var howTo: String {
        if level.parsedGoals.contains(.dust) { return "Match on the dust to clear it." }
        if level.parsedGoals.contains(.parcels) { return "Match beside a parcel to open it." }
        return "Four in a row: a paw swipe. An L: a box. Five: the laser dot."
    }

    private func goalPicture(_ goal: MatchGoal) -> some View {
        let path = switch goal {
        case let .collect(kind, _): "arcade/match/match_\(kind.name).png"
        case .dust: "arcade/match/match_dust.png"
        case .parcels: "arcade/match/match_parcel1.png"
        }
        return Group {
            if let picture = GamesLook.picture(path) {
                picture.resizable().scaledToFit()
            }
        }
    }

    private var starBar: some View {
        let top = Double(level.stars.last ?? 1)
        return HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.rim)
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.97, green: 0.74, blue: 0.3), Theme.accent], startPoint: .leading,
                                                  endPoint: .trailing))
                        .frame(width: proxy.size.width * min(1, Double(progress.score) / max(1, top)))
                        .animation(.spring(duration: 0.4), value: progress.score)
                }
            }
            .frame(height: 12)
            StarsRow(count: progress.won ? progress.stars : 0, size: 18)
        }
    }

    private func results(_ game: MatchGame) -> some View {
        let next = GameSession.arcadeContent?.match.levels.first { $0.id == level.id + 1 }
        var buttons: [(title: String, prominent: Bool, action: () -> Void)] = [("Levels", false, { done(nil) }), ("Try again", !game.goalsMet, { done(level) })]
        if game.goalsMet, let next {
            buttons.append(("Next level", true, { done(next) }))
        }
        return GamesResultCard(
            title: game.goalsMet ? (game.stars == 3 ? "Purrfect!" : "Tidied up!") : "Out of moves",
            subtitle: "\(game.score.formatted()) points",
            stars: game.stars,
            reward: reward,
            catName: catName,
            lines: game.goalsMet ? [] : ["So nearly there. Have another go."],
            buttons: buttons
        )
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func start() {
        guard scene == nil, let art = GameWorld.art else { return }
        let made = MatchScene(size: CGSize(width: 470, height: 372), level: level, seed: GameSession.shared.arcadeSeed(.match), art: art)
        made.onProgress = { next in progress = next }
        made.onMoment = { moment in
            switch moment {
            case .swapped: Sound.play("ui_tap", volume: Tuning.Sound.tap)
            case .refused: Sound.play("ui_tap", volume: Tuning.Sound.tap * 0.6)
            case let .cleared(count, cascade):
                if count > 0 {
                    Sound.play(cascade > 1 ? "ui_sparkle" : "ui_place_item", volume: Tuning.Sound.place)
                }
            case .made:
                Sound.play("ui_bean_chime", volume: Tuning.Sound.levelUp)
                cheer.toggle()
            case .fired:
                Sound.play("ui_knock_off", volume: Tuning.Sound.place)
                #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            case .shuffled:
                Sound.play("ui_sparkle", volume: Tuning.Sound.place)
            }
        }
        made.onFinish = { game in
            var stats = ["clears": game.goalsMet ? 1 : 0, "threeStars": game.stars == 3 ? 1 : 0, "dust": game.dustCleared]
            stats["boxes"] = game.made[.box, default: 0]
            stats["lasers"] = game.made[.laser, default: 0]
            reward = GameSession.shared.finishArcade(ArcadeResult(game: .match, level: level.id, score: game.score, stars: game.stars,
                                                                  won: game.goalsMet, stats: stats))
            withAnimation(.spring(duration: 0.4)) { finished = game }
        }
        #if DEBUG
            made.autoplay = ProcessInfo.processInfo.environment["HOUSECAT_AUTOPLAY"] != nil
        #endif
        scene = made
        made.report()
    }
}
