import HouseCatCore
import HouseCatUI
import SwiftUI

/// The Games menu (Josh, 19 Oct: "build out the games section massively - this needs to be the retention angle and
/// daily use"; CLAUDE.md "The Games menu"). The room's Play button opens it: today along the top (Pat's daily
/// puzzle with its week, the three challenges), the games along the bottom (Zoomies, Catapult, Purrfect Match, Cats
/// in a Row, and the quick games with the cat), each opening its own screen in here.
struct GamesMenu: View {
    enum Screen: Equatable {
        case menu, quick, zoomies, catapult, match, row, puzzle
    }

    let catName: String
    let close: () -> Void
    /// A quick game with the cat picked: the menu closes and the room plays it (PlayView's `MiniGameView`).
    let playQuick: (MinigamesFile.Game) -> Void
    @State private var screen: Screen = .menu
    @State private var tick = 0

    var body: some View {
        ZStack {
            switch screen {
            case .menu, .quick:
                GamesFrame { menu }
                    .transition(.opacity)
            case .zoomies:
                ZoomiesView(catName: catName) { back() }
                    .transition(.move(edge: .trailing))
            case .catapult:
                CatapultScreen(catName: catName) { back() }
                    .transition(.move(edge: .trailing))
            case .match:
                MatchScreen(catName: catName) { back() }
                    .transition(.move(edge: .trailing))
            case .row:
                RowScreen(catName: catName) { back() }
                    .transition(.move(edge: .trailing))
            case .puzzle:
                PuzzleScreen(catName: catName) { back() }
                    .transition(.move(edge: .trailing))
            }
            if screen == .quick, let games = GameWorld.content?.minigames.games {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { withAnimation { screen = .menu } }
                    PlayPicker(games: games, playsLeft: GameSession.shared.playsLeft) { game in
                        playQuick(game)
                    } close: {
                        withAnimation { screen = .menu }
                    }
                    .padding(24)
                }
                .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: screen)
        .onAppear { Music.hush(.miniGame, true) }
        .onDisappear { Music.hush(.miniGame, false) }
        #if DEBUG
            .onAppear {
                if let open = ProcessInfo.processInfo.environment["HOUSECAT_GAMES"] {
                    screen = switch open {
                    case "zoomies": .zoomies
                    case "catapult": .catapult
                    case "match": .match
                    case "row": .row
                    case "puzzle": .puzzle
                    default: .menu
                    }
                }
            }
        #endif
    }

    private func back() {
        tick += 1
        withAnimation { screen = .menu }
    }

    // MARK: The menu

    private var menu: some View {
        let session = GameSession.shared
        let arcade = session.arcade
        let day = session.arcadeDay
        return VStack(spacing: 0) {
            GamesPlank(title: "Games", icon: "arcade/ui/icon_game_games.png") {
                HStack(spacing: 10) {
                    GamesPill(icon: "ui/icon_streak_paw_print_with_a_small_flame.png", value: "\(arcade.puzzleStreak(on: day))",
                              label: "puzzle days")
                    GamesPill(icon: "ui/icon_bean_coin.png", value: session.state(at: session.now()).beans.formatted())
                    CloseButton(action: close)
                }
            }
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    puzzleCard(arcade: arcade, day: day)
                    challengesCard
                }
                .frame(height: 124)
                HStack(spacing: 11) {
                    gameCard(.zoomies, art: "arcade/ui/tile_zoomies.png", status: zoomiesStatus(arcade, day: day))
                    gameCard(.catapult, art: "arcade/ui/tile_catapult.png", status: catapultStatus(arcade))
                    gameCard(.match, art: "arcade/ui/tile_match.png", status: matchStatus(arcade))
                    gameCard(.row, art: "arcade/ui/tile_row.png", status: rowStatus(arcade))
                    quickCard
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .id(tick)
        .foregroundStyle(Theme.ink)
    }

    private func puzzleCard(arcade: ArcadeState, day: GameDay) -> some View {
        let number = ArcadePuzzles.number(on: day)
        let solved = arcade.solvedToday(on: day)
        let streak = arcade.puzzleStreak(on: day)
        return Button {
            withAnimation { screen = .puzzle }
        } label: {
            HStack(spacing: 8) {
                if let art = GamesLook.picture("arcade/ui/tile_puzzle.png") {
                    art.resizable().scaledToFit().frame(width: 112)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("No. \(number)").font(Theme.title(21))
                    Text(solved ? "Solved today. A new one tomorrow." : "Today's puzzle, the same for everyone")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    WeekStrip(streak: streak, solvedToday: solved, day: day)
                }
                Spacer(minLength: 4)
                VStack(spacing: 6) {
                    if solved {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(GamesLook.green)
                    } else {
                        Text("Solve").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(GamesLook.green))
                            .shadow(color: GamesLook.green.mix(with: .black, by: 0.35), radius: 0, y: 3)
                        HStack(spacing: 3) {
                            PaintedIcon("bean_coin", size: 16)
                            Text("\(Tuning.Arcade.Puzzle.beans)").font(.caption.weight(.heavy))
                        }
                    }
                }
                .padding(.trailing, 12)
            }
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .goldCard()
            .overlay(alignment: .topLeading) {
                Ribbon("Pat's daily puzzle", colour: GamesLook.puzzle).offset(x: 16, y: -11)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(solved ? "Pat's daily puzzle number \(number), solved" : "Pat's daily puzzle number \(number)")
    }

    private var challengesCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(GameSession.shared.arcadeChallenges, id: \.challenge.id) { item in
                HStack(spacing: 8) {
                    if let icon = GamesLook.picture(challengeIcon(item.challenge.game)) {
                        icon.resizable().scaledToFit().frame(width: 26, height: 26)
                    }
                    Text(item.text).font(.system(size: 13, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if item.done {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(GamesLook.green)
                    } else {
                        ProgressView(value: Double(item.progress), total: Double(item.challenge.target))
                            .tint(Theme.accent).frame(width: 52)
                        Text("\(item.progress)/\(item.challenge.target)").font(.caption2.weight(.bold)).foregroundStyle(Theme.inkSoft)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .goldCard()
        .overlay(alignment: .topLeading) {
            Ribbon("Today's challenges · \(Tuning.Arcade.Challenges.beans) Beans each").offset(x: 16, y: -11)
        }
    }

    private func challengeIcon(_ game: ArcadeGame) -> String {
        switch game {
        case .zoomies: "arcade/ui/icon_game_biscuit.png"
        case .catapult: "arcade/ui/icon_game_cushion.png"
        case .match: "arcade/match/match_box.png"
        case .row: "arcade/ui/icon_game_two_cats.png"
        }
    }

    private func gameCard(_ game: ArcadeGame, art: String, status: (line: String, chip: String, icon: String)) -> some View {
        let name = GameSession.arcadeContent?.file.game(game)?.name ?? game.rawValue.capitalized
        return Button {
            withAnimation {
                screen = switch game {
                case .zoomies: .zoomies
                case .catapult: .catapult
                case .match: .match
                case .row: .row
                }
            }
        } label: {
            VStack(spacing: 0) {
                CardBand(title: name, colour: GamesLook.colour(game))
                ZStack {
                    RadialGradient(colors: [Color(red: 1, green: 0.92, blue: 0.65).opacity(0.9), .clear], center: .center,
                                   startRadius: 2, endRadius: 70)
                    if let picture = GamesLook.picture(art) {
                        picture.resizable().scaledToFit().padding(6)
                            .shadow(color: Color(red: 0.3, green: 0.15, blue: 0.08).opacity(0.25), radius: 3, y: 3)
                    }
                }
                .frame(maxHeight: .infinity)
                Text(status.line).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    .padding(.horizontal, 6)
                HStack(spacing: 3) {
                    PaintedIcon(status.icon, size: 15)
                    Text(status.chip).font(.system(size: 11.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.75)))
                .padding(.top, 3)
                .padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .goldCard()
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(name). \(status.line). \(status.chip)")
    }

    private var quickCard: some View {
        let plays = GameSession.shared.playsLeft
        return Button {
            withAnimation { screen = .quick }
        } label: {
            VStack(spacing: 0) {
                CardBand(title: "Play with \(catName)", colour: GamesLook.quick)
                ZStack(alignment: .bottomTrailing) {
                    if let cat = GameSession.shared.cat, let portrait = CatScreens.portrait(cat.look) {
                        Image(decorative: portrait, scale: 1).resizable().scaledToFit().padding(.vertical, 8).padding(.trailing, 26)
                    }
                    PaintedIcon("play_laser_dot", size: 44).padding(.trailing, 4).padding(.bottom, 6)
                }
                .frame(maxHeight: .infinity)
                // However many quick games Content/minigames.json has (their names are in the picker).
                Text("\(GameWorld.content?.minigames.games.count ?? 0) quick games").font(.system(size: 12, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                HStack(spacing: 3) {
                    PaintedIcon("clock", size: 15)
                    Text(plays > 0 ? "\(plays) plays left" : "Just for fun today").font(.system(size: 11.5, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.75)))
                .padding(.top, 3)
                .padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .goldCard()
        }
        .buttonStyle(PressStyle())
    }

    // MARK: What each card says

    private func zoomiesStatus(_ arcade: ArcadeState, day: GameDay) -> (line: String, chip: String, icon: String) {
        let best = arcade.best[ArcadeGame.zoomies.rawValue] ?? 0
        let left = arcade.paidPlaysLeft(.zoomies, on: day)
        return (best > 0 ? "Best \(best.formatted())" : "Gallop for biscuits",
                left > 0 ? "\(left) paid runs left" : "Just for fun today", "bean_coin")
    }

    private func catapultStatus(_ arcade: ArcadeState) -> (line: String, chip: String, icon: String) {
        let home = GameSession.shared.state(at: GameSession.shared.now()).home.place?.biome ?? .city
        let place = GameSession.arcadeContent?.file.places[home.rawValue] ?? home.rawValue.capitalized
        let perPlace = Tuning.Arcade.Catapult.levelsPerPlace
        let base = (Biome.allCases.firstIndex(of: home) ?? 0) * perPlace
        let cleared = (0 ..< perPlace).filter { arcade.stars(.catapult, level: base + $0) > 0 }.count
        return ("\(place) · \(min(cleared + 1, perPlace)) of \(perPlace)", "\(arcade.totalStars(.catapult)) of \(Tuning.Arcade.catapultLevels * 3)",
                "xp_star")
    }

    private func matchStatus(_ arcade: ArcadeState) -> (line: String, chip: String, icon: String) {
        ("Level \(arcade.nextLevel(.match) + 1)", "\(arcade.totalStars(.match)) of \(Tuning.Arcade.matchLevels * 3)", "xp_star")
    }

    private func rowStatus(_ arcade: ArcadeState) -> (line: String, chip: String, icon: String) {
        let opponents = GameSession.arcadeContent?.file.opponents ?? []
        let next = opponents.first { !arcade.beaten.contains($0.id) }
        return (next.map { "Next: \($0.name)" } ?? "Every cat beaten", "\(arcade.beaten.count) of \(opponents.count) cats beaten", "star_rosette")
    }
}

/// The puzzle's week: Monday to Sunday, the days of the streak ticked, the streak's prize days marked.
struct WeekStrip: View {
    let streak: Int
    let solvedToday: Bool
    let day: GameDay

    var body: some View {
        let today = day.weekday
        HStack(spacing: 4) {
            ForEach(1 ... 7, id: \.self) { weekday in
                // Days back from today; the streak covers today once solved, else up to yesterday.
                let back = today - weekday
                let inStreak = back >= 0 && (solvedToday ? back < streak : (back >= 1 && back <= streak))
                // A day still to come (or today, unsolved): the streak it would make, and whether that pays extra.
                let wouldBe: Int? = back < 0 || (back == 0 && !solvedToday) ? streak + (solvedToday ? 0 : 1) + max(0, -back) : nil
                let prize = wouldBe.map { ArcadePuzzles.streakBonus(day: $0) > 0 } ?? false
                VStack(spacing: 0) {
                    Text(["M", "T", "W", "T", "F", "S", "S"][weekday - 1]).font(.system(size: 9, weight: .heavy))
                    if inStreak {
                        PaintedIcon("xp_star", size: 14)
                    } else {
                        Color.clear.frame(width: 14, height: 14)
                    }
                }
                .frame(width: 22, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(inStreak ? Color(red: 1, green: 0.86, blue: 0.5) : .white.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(weekday == today ? Theme.accent : Theme.rim, lineWidth: weekday == today ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if prize, !inStreak {
                        PaintedIcon("gift_box_with_a_ribbon", size: 13).offset(x: 5, y: -5)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(streak) days in a row")
    }
}
