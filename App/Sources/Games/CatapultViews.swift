import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Catapult (the Games menu's pounce game): the places down the side, the player's home first, each place's ten
/// levels with their stars; a level opens once the one before it is cleared.
struct CatapultScreen: View {
    let catName: String
    let back: () -> Void
    @State private var place: Biome = .city
    @State private var playing: CatapultLevel?
    @State private var tick = 0

    private var home: Biome {
        GameSession.shared.state(at: GameSession.shared.now()).homePlace.biome
    }

    var body: some View {
        ZStack {
            if let level = playing {
                CatapultPlay(level: level, catName: catName) { next in
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
        .onAppear { place = home }
        #if DEBUG
            .onAppear {
                if let id = ProcessInfo.processInfo.environment["HOUSECAT_LEVEL"].flatMap(Int.init),
                   let level = GameSession.arcadeContent?.catapult.levels.first(where: { $0.id == id }) {
                    playing = level
                }
            }
        #endif
    }

    private var picker: some View {
        let arcade = GameSession.shared.arcade
        let content = GameSession.arcadeContent
        let levels = content?.catapultLevels(in: place) ?? []
        return VStack(spacing: 0) {
            GamesPlank(title: content?.file.game(.catapult)?.name ?? "Catapult", icon: "arcade/ui/tile_catapult.png", back: back) {
                GamesPill(icon: "ui/icon_xp_star.png", value: "\(arcade.totalStars(.catapult))", label: "of \(Tuning.Arcade.catapultLevels * 3)")
            }
            HStack(alignment: .top, spacing: 14) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(ArcadeContent.places(home: home), id: \.self) { biome in
                            placeTab(biome, arcade: arcade, content: content)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(width: 168)
                VStack(spacing: 10) {
                    ZStack(alignment: .bottomLeading) {
                        if let painting = GamesLook.picture("arcade/pounce/place_\(place.rawValue).jpg") {
                            painting.resizable().scaledToFill().frame(height: 96).clipped()
                        }
                        Text(place == home ? "Where you live" : (content?.file.places[place.rawValue] ?? ""))
                            .font(Theme.title(20)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .padding(10)
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GameHUD.gold, lineWidth: 3))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(levels, id: \.id) { level in
                            levelButton(level, arcade: arcade)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .id(tick)
        .foregroundStyle(Theme.ink)
    }

    private func placeTab(_ biome: Biome, arcade: ArcadeState, content: ArcadeContent?) -> some View {
        let ids = content?.catapultLevels(in: biome).map(\.id) ?? []
        let stars = ids.reduce(0) { $0 + arcade.stars(.catapult, level: $1) }
        let chosen = biome == place
        return Button {
            withAnimation(.spring(duration: 0.3)) { place = biome }
        } label: {
            HStack(spacing: 6) {
                Text(biome == home ? "Home · \(content?.file.places[biome.rawValue] ?? "")" : (content?.file.places[biome.rawValue] ?? ""))
                    .font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                PaintedIcon("xp_star", size: 14)
                Text("\(stars)").font(.caption.weight(.heavy)).monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(chosen ? Theme.cream : Color(red: 0.98, green: 0.92, blue: 0.82).opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(chosen ? GameHUD.deepGold : Theme.rim, lineWidth: chosen ? 2.5 : 1))
        }
        .buttonStyle(PressStyle())
    }

    private func levelButton(_ level: CatapultLevel, arcade: ArcadeState) -> some View {
        let open = arcade.isOpen(.catapult, level: level.id)
        let stars = arcade.stars(.catapult, level: level.id)
        let number = level.id % Tuning.Arcade.Catapult.levelsPerPlace + 1
        return Button {
            guard open else { return }
            playing = level
        } label: {
            VStack(spacing: 3) {
                if open {
                    Text("\(number)").font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text(level.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.inkSoft)
                    StarsRow(count: stars, size: 14)
                } else {
                    PaintedIcon("padlock", size: 30)
                    Text(level.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .goldCard(corner: 14)
            .opacity(open ? 1 : 0.6)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(open ? "Level \(number), \(level.title), \(stars) stars" : "Level \(number), \(level.title), locked")
    }
}

/// One Catapult level: the scene, the mice to go and the pounces left along the top, the end card.
struct CatapultPlay: View {
    let level: CatapultLevel
    let catName: String
    /// Back to the levels (nil), or on to the next level.
    let done: (CatapultLevel?) -> Void
    @State private var scene: CatapultScene?
    @State private var progress = CatapultScene.Progress()
    @State private var finished: CatapultGame?
    @State private var reward: GameSession.ArcadeReward?
    @State private var hint = true

    var body: some View {
        ZStack {
            if let scene {
                GameSceneView(scene: scene).ignoresSafeArea()
            } else {
                GamesPaper()
            }
            // The HUD and cards scale with the screen (an iPad's are larger), the level itself fills it.
            GamesScaled {
                VStack {
                    hud
                    Spacer()
                    if hint, progress.pouncesLeft == level.pouncesGiven, finished == nil {
                        Text("Drag back anywhere, aim, and let go")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.ink.opacity(0.75)))
                            .padding(.bottom, 10)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
            }
            if let finished {
                Color.black.opacity(0.35).ignoresSafeArea()
                GamesScaled { results(finished) }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
        .task { start() }
    }

    private var hud: some View {
        let place = GameSession.arcadeContent?.file.places[level.place.rawValue] ?? ""
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("\(place) · \(level.id % Tuning.Arcade.Catapult.levelsPerPlace + 1)").font(Theme.title(19))
                Text(level.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                Divider().frame(height: 22)
                if let mouse = GamesLook.picture("arcade/ui/icon_game_mouse.png") {
                    mouse.resizable().scaledToFit().frame(width: 28, height: 28)
                }
                Text("\(progress.knocked) / \(progress.mice)").font(.system(size: 19, weight: .heavy, design: .rounded)).monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .paper(Capsule())
            HStack(spacing: 4) {
                ForEach(0 ..< level.pouncesGiven, id: \.self) { index in
                    pounceToken(used: index >= progress.pouncesLeft)
                }
                Text("pounces").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft).padding(.leading, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .paper(Capsule())
            Spacer()
            Button {
                done(nil)
            } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36).paper(Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Leave the level")
        }
        .foregroundStyle(Theme.ink)
    }

    private func pounceToken(used: Bool) -> some View {
        Group {
            if let cat = GameSession.shared.cat, let face = CatScreens.headshot(cat.look) {
                Image(decorative: face, scale: 1).resizable().scaledToFit()
            } else {
                Circle().fill(Theme.ink)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(GameHUD.gold, lineWidth: 2))
        .grayscale(used ? 1 : 0)
        .opacity(used ? 0.4 : 1)
    }

    private func results(_ game: CatapultGame) -> some View {
        let next = GameSession.arcadeContent?.catapult.levels.first { $0.id == level.id + 1 && $0.place == level.place }
        var lines: [String] = []
        if game.won {
            lines.append(game.used == 1 ? "Cleared in one pounce" : "Cleared in \(game.used) pounces")
            if game.stars < 3 {
                lines.append("Clear it in \(level.par) for three stars")
            }
        } else {
            lines.append("\(game.knocked.count) of \(level.mice.count) toy mice knocked off")
        }
        var buttons: [(title: String, prominent: Bool, action: () -> Void)] = [("Levels", false, { done(nil) }), ("Try again", !game.won, { done(level) })]
        if game.won, let next {
            buttons.append(("Next level", true, { done(next) }))
        }
        return GamesResultCard(
            title: game.won ? (game.stars == 3 ? "Purrfect pounce!" : "Cleared!") : "So close",
            stars: game.stars,
            reward: reward,
            catName: catName,
            lines: lines,
            buttons: buttons
        )
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func start() {
        guard scene == nil, let art = GameWorld.art, let catArt = GameWorld.catArt, let rig = GameWorld.rig else { return }
        let session = GameSession.shared
        let made = CatapultScene(size: CGSize(width: 956, height: 440), level: level, art: art, catArt: catArt, rig: rig,
                                 look: session.cat?.look ?? .midnight, outfit: session.wornOutfit)
        made.onProgress = { next in
            if next != progress {
                if next.pouncesLeft < progress.pouncesLeft { hint = false }
                progress = next
            }
        }
        made.onBeat = { beat in
            switch beat {
            case .knocked:
                // Several mice off in one pounce make one purr, not a run of chirps.
                Sound.purr()
                #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            case .settled:
                Sound.play("ui_place_item", volume: Tuning.Sound.tap)
            case .won, .lost:
                break
            }
        }
        made.onFinish = { game in
            reward = GameSession.shared.finishArcade(ArcadeResult(game: .catapult, level: level.id, score: game.knocked.count,
                                                                  stars: game.stars, won: game.won, stats: game.stats))
            withAnimation(.spring(duration: 0.4)) { finished = game }
        }
        #if DEBUG
            made.autoplay = ProcessInfo.processInfo.environment["HOUSECAT_AUTOPLAY"] != nil
        #endif
        progress = CatapultScene.Progress(knocked: 0, mice: level.mice.count, pouncesLeft: level.pouncesGiven, flying: false)
        scene = made
    }
}
