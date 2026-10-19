import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Pictures of the cats for Cats in a Row: each sitting and as a face on a counter, made once.
@MainActor
enum RowPictures {
    private static var portraits: [String: CGImage] = [:]
    private static var faces: [String: CGImage] = [:]

    static func look(_ preset: String) -> CatLook {
        GameWorld.catArt?.builder.preset(preset)?.look ?? .midnight
    }

    /// A cat sitting (the player's own wears what it has on).
    static func portrait(_ key: String, look: CatLook, own: Bool) -> CGImage? {
        if let cached = portraits[key] { return cached }
        let image = CatScreens.portrait(look, outfit: own ? GameSession.shared.wornOutfit : nil)
        portraits[key] = image
        return image
    }

    /// Its face, cut square for a counter.
    static func face(_ key: String, look: CatLook, own: Bool) -> CGImage? {
        if let cached = faces[key] { return cached }
        guard let catArt = GameWorld.catArt, let image = portrait(key, look: look, own: own) else { return nil }
        let sprite = catArt.builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: look)
        let face = Headshot.cut(image, face: catArt.face(sprite.path))
        faces[key] = face
        return face
    }
}

/// Cats in a Row (the Games menu's four in a row): the eight cats from the intro's homes, easiest first (beat one to
/// meet the next; beaten ones can be played again), or two people on one device.
struct RowScreen: View {
    let catName: String
    let back: () -> Void
    @State private var playing: (opponent: ArcadeFile.Opponent?, key: Int)?
    @State private var tick = 0

    var body: some View {
        ZStack {
            if let playing {
                RowPlay(opponent: playing.opponent, catName: catName) { again in
                    tick += 1
                    self.playing = again ? (playing.opponent, tick) : nil
                }
                .id(playing.key)
                .transition(.move(edge: .trailing))
            } else {
                GamesFrame { ladder }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playing?.key)
    }

    private var ladder: some View {
        let arcade = GameSession.shared.arcade
        let opponents = GameSession.arcadeContent?.file.opponents ?? []
        let next = opponents.firstIndex { !arcade.beaten.contains($0.id) } ?? opponents.count
        return VStack(spacing: 0) {
            GamesPlank(title: GameSession.arcadeContent?.file.game(.row)?.name ?? "Cats in a Row", icon: "arcade/ui/tile_row.png", back: back) {
                GamesPill(icon: "ui/icon_star_rosette.png", value: "\(arcade.beaten.count)", label: "of \(opponents.count) beaten")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(opponents.enumerated()), id: \.element.id) { index, opponent in
                        opponentCard(opponent, beaten: arcade.beaten.contains(opponent.id), open: index <= next, isNext: index == next)
                    }
                    twoPlayersCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: .infinity)
            Text("Win against each cat once for \(Tuning.Arcade.firstWinBeans) Beans. Your first three games a day pay their stars too.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                .padding(.bottom, 12)
        }
        .id(tick)
        .foregroundStyle(Theme.ink)
    }

    private func opponentCard(_ opponent: ArcadeFile.Opponent, beaten: Bool, open: Bool, isNext: Bool) -> some View {
        Button {
            guard open else { return }
            tick += 1
            playing = (opponent, tick)
        } label: {
            VStack(spacing: 0) {
                CardBand(title: opponent.name, colour: isNext ? GamesLook.green : GamesLook.row)
                ZStack {
                    if let portrait = RowPictures.portrait(opponent.id, look: RowPictures.look(opponent.preset), own: false) {
                        Image(decorative: portrait, scale: 1).resizable().scaledToFit().padding(8)
                            .grayscale(open ? 0 : 0.9).opacity(open ? 1 : 0.55)
                    }
                    if !open {
                        PaintedIcon("padlock", size: 40)
                    }
                }
                .frame(maxHeight: .infinity)
                Text(opponent.home).font(.system(size: 12, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(opponent.style).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                HStack(spacing: 3) {
                    if beaten {
                        PaintedIcon("star_rosette", size: 15)
                        Text("Beaten").font(.system(size: 11, weight: .heavy)).foregroundStyle(GamesLook.green)
                    } else if open {
                        PaintedIcon("bean_coin", size: 15)
                        Text("+\(Tuning.Arcade.firstWinBeans) for a win").font(.system(size: 11, weight: .bold))
                    } else {
                        Text("Beat the cat before").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.top, 3)
                .padding(.bottom, 9)
            }
            .frame(width: 132, height: 250)
            .goldCard()
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(opponent.name) from \(opponent.home). \(beaten ? "Beaten" : open ? "Play" : "Locked")")
    }

    private var twoPlayersCard: some View {
        Button {
            tick += 1
            playing = (nil, tick)
        } label: {
            VStack(spacing: 0) {
                CardBand(title: "Two players", colour: GamesLook.quick)
                if let picture = GamesLook.picture("arcade/ui/icon_game_two_cats.png") {
                    picture.resizable().scaledToFit().padding(14).frame(maxHeight: .infinity)
                }
                Text("Pass the device").font(.system(size: 12, weight: .bold))
                Text("Your cat and another").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .padding(.bottom, 12)
            }
            .frame(width: 132, height: 250)
            .goldCard()
        }
        .buttonStyle(PressStyle())
    }
}

/// One game of Cats in a Row: the player's cat on the left (teal counters), the other cat on the right (coral),
/// the board between. Tap a column to drop a counter; the other cat thinks, then plays.
struct RowPlay: View {
    let opponent: ArcadeFile.Opponent?
    let catName: String
    /// Done: true for another game against the same cat.
    let done: (Bool) -> Void
    @State private var game = RowGame()
    @State private var falling: (cell: RowCell, side: RowSide)?
    @State private var thinking = false
    @State private var reward: GameSession.ArcadeReward?
    @State private var over = false
    @State private var line: String?
    @State private var seed = DaySeed(household: 0, day: GameDay(index: 0), purpose: "row")

    private static let teal = Color(red: 0.18, green: 0.6, blue: 0.57)
    private static let coral = Color(red: 0.88, green: 0.44, blue: 0.3)
    /// The board picture's hole centres as shares of its size (measured on the painting) and its aspect.
    private static let holes = (left: 0.165, right: 0.842, top: 0.141, bottom: 0.795, size: 0.085)
    private static let aspect = 2084.0 / 1786.0

    private var ownLook: CatLook {
        GameSession.shared.cat?.look ?? .midnight
    }

    /// The second player's cat: the opponent's, or for two people the first cat that is not the player's own look.
    private var otherLook: CatLook {
        if let opponent { return RowPictures.look(opponent.preset) }
        return ownLook == RowPictures.look("ginger_tabby") ? RowPictures.look("tuxedo") : RowPictures.look("ginger_tabby")
    }

    private var otherKey: String {
        opponent?.id ?? "two"
    }

    private var otherName: String {
        opponent?.name ?? "Player two"
    }

    var body: some View {
        GamesFrame {
            ZStack {
                HStack(spacing: 10) {
                    player(name: catName, look: ownLook, key: "own", own: true, colour: Self.teal, side: .first)
                        .frame(width: 170)
                    board
                    player(name: otherName, look: otherLook, key: otherKey, own: false, colour: Self.coral, side: .second)
                        .frame(width: 170)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                VStack {
                    HStack {
                        Button { done(false) } label: {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink)
                                .frame(width: 34, height: 34).paper(Circle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Back to the cats")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(14)
                if over {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    results
                }
            }
        }
        .task {
            let session = GameSession.shared
            seed = session.arcadeSeed(.row)
            if let opponent { line = opponent.meet }
        }
    }

    private func player(name: String, look: CatLook, key: String, own: Bool, colour: Color, side: RowSide) -> some View {
        let turn = game.outcome == .playing && game.turn == side
        return VStack(spacing: 8) {
            if let portrait = RowPictures.portrait(key, look: look, own: own) {
                Image(decorative: portrait, scale: 1).resizable().scaledToFit().frame(height: 170)
                    .scaleEffect(turn ? 1.04 : 1, anchor: .bottom)
                    .animation(.spring(duration: 0.35), value: turn)
            }
            VStack(spacing: 2) {
                Text(name).font(Theme.title(19)).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Circle().fill(colour).frame(width: 10, height: 10)
                    Text(turn ? (side == .second && opponent != nil ? (thinking ? "Thinking…" : "Their turn") : "Your turn")
                        : (opponent?.style ?? " "))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .goldCard(corner: 14)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(turn ? colour : .clear, lineWidth: 3))
            if side == .second, let line, opponent != nil {
                GreetingBubble(line, name: otherName).frame(maxWidth: 170).transition(.opacity)
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private var board: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height * Self.aspect)
            let height = width / Self.aspect
            let h = Self.holes
            let cellX = { (column: Int) in width * (h.left + (h.right - h.left) * Double(column) / 6) }
            let cellY = { (row: Int) in height * (h.bottom - (h.bottom - h.top) * Double(row) / 5) }
            let token = width * h.size * 1.12
            ZStack(alignment: .topLeading) {
                ForEach(0 ..< RowBoard.columns, id: \.self) { column in
                    ForEach(0 ..< RowBoard.rows, id: \.self) { row in
                        let cell = RowCell(column: column, row: row)
                        if let side = game.board.side(at: cell), falling?.cell != cell {
                            counter(side, size: token, glow: winning.contains(cell))
                                .position(x: cellX(column), y: cellY(row))
                        }
                    }
                }
                if let falling {
                    counter(falling.side, size: token, glow: false)
                        .position(x: cellX(falling.cell.column), y: cellY(falling.cell.row))
                        .transition(.asymmetric(insertion: .offset(y: -cellY(falling.cell.row) - token), removal: .identity))
                        .id("\(falling.cell.column)-\(falling.cell.row)")
                }
                if let board = GamesLook.picture("arcade/row/row_board.png") {
                    board.resizable().frame(width: width, height: height).allowsHitTesting(false)
                        .shadow(color: Color(red: 0.3, green: 0.15, blue: 0.05).opacity(0.3), radius: 6, y: 5)
                }
                // Columns to tap.
                HStack(spacing: 0) {
                    ForEach(0 ..< RowBoard.columns, id: \.self) { column in
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { tap(column) }
                            .accessibilityElement()
                            .accessibilityLabel("Column \(column + 1)")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .frame(width: width * (h.right - h.left + h.size), height: height)
                .offset(x: width * (h.left - h.size / 2))
            }
            .frame(width: width, height: height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var winning: Set<RowCell> {
        if case let .won(_, cells) = game.outcome { return cells }
        return []
    }

    private func counter(_ side: RowSide, size: CGFloat, glow: Bool) -> some View {
        let own = side == .first
        let face = RowPictures.face(own ? "own" : otherKey, look: own ? ownLook : otherLook, own: own)
        return ZStack {
            Circle().fill(Color.white)
            if let face {
                Image(decorative: face, scale: 1).resizable().scaledToFit().clipShape(Circle()).padding(size * 0.08)
            }
            Circle().strokeBorder(own ? Self.teal : Self.coral, lineWidth: size * 0.11)
        }
        .frame(width: size, height: size)
        .shadow(color: glow ? Color(red: 1, green: 0.85, blue: 0.3) : .black.opacity(0.25), radius: glow ? 8 : 2, y: glow ? 0 : 2)
        .scaleEffect(glow ? 1.08 : 1)
    }

    // MARK: Playing

    private func tap(_ column: Int) {
        guard !over, !thinking, game.outcome == .playing, opponent == nil || game.turn == .first else { return }
        drop(column)
    }

    private func drop(_ column: Int) {
        let side = game.turn
        guard let cell = game.play(column) else { return }
        Sound.play("ui_place_item", volume: Tuning.Sound.place)
        #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
            falling = (cell, side)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.none) { falling = nil }
            afterMove()
        }
    }

    private func afterMove() {
        switch game.outcome {
        case .playing:
            if opponent != nil, game.turn == .second {
                think()
            }
        case .won, .draw:
            finish()
        }
    }

    /// The other cat takes a moment, works out its move off the main thread, and plays it.
    private func think() {
        guard let opponent else { return }
        thinking = true
        let board = game.board
        let start = seed
        let skill = opponent.skill
        Task { @MainActor in
            let started = Date()
            let (column, after) = await Task.detached(priority: .userInitiated) {
                var local = start
                let column = RowBrain.move(on: board, for: .second, skill: skill, seed: &local)
                return (column, local)
            }.value
            self.seed = after
            let wait = Tuning.Arcade.Row.thinkSeconds - Date().timeIntervalSince(started)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            thinking = false
            drop(column)
        }
    }

    private func finish() {
        let won: Bool, stars: Int
        switch game.outcome {
        case let .won(side, _):
            won = side == .first
            stars = won ? 3 : 0
        default:
            won = false
            stars = 1
        }
        var stats = ["games": 1]
        stats["wins"] = won ? 1 : 0
        reward = GameSession.shared.finishArcade(ArcadeResult(game: .row, score: won ? 1 : 0, stars: stars, opponent: opponent?.id, won: won,
                                                              stats: stats))
        if let opponent {
            line = won ? opponent.loses : opponent.wins
        }
        Sound.play(won ? "ui_streak_milestone" : "cat_meow_soft", volume: Tuning.Sound.levelUp)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.spring(duration: 0.4)) { over = true }
        }
    }

    private var results: some View {
        let won: Bool, title: String
        switch game.outcome {
        case let .won(side, _):
            won = side == .first
            title = opponent == nil ? "\(side == .first ? catName : otherName) wins!" : (won ? "You win!" : "\(otherName) wins")
        default:
            won = false
            title = "A draw"
        }
        var lines: [String] = []
        if reward?.payout.firstWin == true, let opponent {
            lines.append("First win against \(opponent.name)!")
        }
        if won, reward?.payout.paidPlay == nil {
            lines.append("Today's three paid games are done; wins against a new cat still pay.")
        }
        return GamesResultCard(
            title: title,
            stars: won ? 3 : game.outcome == .draw ? 1 : 0,
            showsStars: opponent != nil,
            reward: reward,
            catName: catName,
            lines: lines,
            buttons: [("Back", false, { done(false) }), ("Play again", true, { done(true) })]
        )
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
