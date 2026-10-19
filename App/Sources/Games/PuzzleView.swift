import HouseCatCore
import HouseCatUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Pat's daily puzzle, Pawcross (a picture logic puzzle, recommended from the three mockups Josh was shown): today's
/// grid with its numbers, Fill and Cross, a drag paints a line of squares, three hints; solved, the squares turn into
/// the painting they were cut from, and it pays once (with the streak's extra on its third and seventh day).
struct PuzzleScreen: View {
    let catName: String
    let back: () -> Void
    @State private var board: PawcrossBoard?
    @State private var crossing = false
    @State private var seconds = 0
    @State private var solved = false
    @State private var reward: GameSession.ArcadeReward?
    @State private var showCard = false
    @State private var stroke: (mark: PawcrossMark, done: Set<[Int]>)?

    static let file: PawcrossFile? = Bundle.main.url(forResource: "Content/pawcross.json", withExtension: nil)
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(PawcrossFile.self, from: $0) }

    private var number: Int {
        ArcadePuzzles.number(on: GameSession.shared.arcadeDay)
    }

    var body: some View {
        GamesFrame {
            ZStack {
                VStack(spacing: 0) {
                    GamesPlank(title: "Pawcross · No. \(number)", icon: "arcade/ui/tile_puzzle.png", back: leave) {
                        HStack(spacing: 10) {
                            GamesPill(icon: "ui/icon_clock.png", value: String(format: "%d:%02d", seconds / 60, seconds % 60))
                            let streak = GameSession.shared.arcade.puzzleStreak(on: GameSession.shared.arcadeDay)
                            GamesPill(icon: "ui/icon_streak_paw_print_with_a_small_flame.png", value: "\(streak)",
                                      label: streak == 1 ? "day" : "days")
                        }
                    }
                    if let board {
                        HStack(alignment: .center, spacing: 18) {
                            grid(board)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            side(board)
                                .frame(width: 250)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    } else {
                        Spacer()
                        Text("Pat is still setting today's puzzle.").font(Theme.title(22))
                        Spacer()
                    }
                }
                if showCard, let board {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    GamesResultCard(
                        title: board.puzzle.title.replacingOccurrences(of: "{cat}", with: catName),
                        subtitle: String(format: "Solved in %d:%02d", seconds / 60, seconds % 60),
                        stars: 0,
                        showsStars: false,
                        reward: reward,
                        catName: catName,
                        lines: lines,
                        buttons: [("Back to the games", true, leave)]
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .foregroundStyle(Theme.ink)
        }
        .task { load() }
        .task(id: solved) {
            // The clock runs while the puzzle is open and unsolved.
            while !solved, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !solved { seconds += 1 }
            }
        }
    }

    private var lines: [String] {
        var lines: [String] = []
        if let reward, reward.payout.streakBonus > 0 {
            lines.append("\(reward.payout.puzzleStreak) days in a row: \(reward.payout.streakBonus) Beans more")
        } else if let reward, reward.payout.puzzleStreak > 1 {
            lines.append("\(reward.payout.puzzleStreak) days in a row")
        }
        lines.append("A new one tomorrow: No. \(number + 1)")
        return lines
    }

    // MARK: The grid

    private func grid(_ board: PawcrossBoard) -> some View {
        GeometryReader { proxy in
            let rowClues = board.puzzle.rowClues, columnClues = board.puzzle.columnClues
            let clueColumns = CGFloat(rowClues.map(\.count).max() ?? 1)
            let clueRows = CGFloat(columnClues.map(\.count).max() ?? 1)
            let cell = floor(min(proxy.size.width / (CGFloat(board.puzzle.width) + clueColumns * 0.62),
                                 proxy.size.height / (CGFloat(board.puzzle.height) + clueRows * 0.62)))
            let left = clueColumns * cell * 0.62, top = clueRows * cell * 0.62
            let width = cell * CGFloat(board.puzzle.width), height = cell * CGFloat(board.puzzle.height)
            ZStack(alignment: .topLeading) {
                // Column numbers over the grid, row numbers to its left; a line's numbers fade once it is done.
                ForEach(0 ..< board.puzzle.width, id: \.self) { c in
                    VStack(spacing: 0) {
                        ForEach(Array(columnClues[c].enumerated()), id: \.offset) { _, n in
                            Text("\(n)").font(.system(size: cell * 0.48, weight: .heavy, design: .rounded)).frame(height: cell * 0.62)
                        }
                    }
                    .foregroundStyle(board.columnDone(c) ? Theme.inkSoft.opacity(0.45) : Theme.ink)
                    .frame(width: cell, height: top, alignment: .bottom)
                    .offset(x: left + CGFloat(c) * cell)
                }
                ForEach(0 ..< board.puzzle.height, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(Array(rowClues[r].enumerated()), id: \.offset) { _, n in
                            Text("\(n)").font(.system(size: cell * 0.48, weight: .heavy, design: .rounded)).frame(width: cell * 0.62)
                        }
                    }
                    .foregroundStyle(board.rowDone(r) ? Theme.inkSoft.opacity(0.45) : Theme.ink)
                    .frame(width: left, height: cell, alignment: .trailing)
                    .offset(y: top + CGFloat(r) * cell)
                }
                // The squares.
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color(red: 1, green: 0.985, blue: 0.95))
                    ForEach(0 ..< board.puzzle.height, id: \.self) { r in
                        ForEach(0 ..< board.puzzle.width, id: \.self) { c in
                            square(board.marks[r][c], size: cell)
                                .offset(x: CGFloat(c) * cell, y: CGFloat(r) * cell)
                        }
                    }
                    lines(width: board.puzzle.width, height: board.puzzle.height, cell: cell)
                    if solved {
                        reveal(board.puzzle).frame(width: width, height: height).transition(.opacity)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: Color(red: 0.3, green: 0.15, blue: 0.05).opacity(0.2), radius: 4, y: 3)
                // Before the offset, so a touch is measured from the grid's own corner.
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in paint(at: value.location, cell: cell) }
                    .onEnded { _ in endStroke() })
                .offset(x: left, y: top)
            }
            .frame(width: left + width, height: top + height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func square(_ mark: PawcrossMark, size: CGFloat) -> some View {
        ZStack {
            switch mark {
            case .filled:
                RoundedRectangle(cornerRadius: size * 0.12).fill(Theme.ink).padding(size * 0.05)
            case .crossed:
                Image(systemName: "xmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Theme.inkSoft)
            case .empty:
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    /// Thin lines between squares, a thicker one every five.
    private func lines(width: Int, height: Int, cell: CGFloat) -> some View {
        Canvas { context, size in
            for c in 0 ... width {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(c) * cell, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(c) * cell, y: size.height))
                context.stroke(path, with: .color(Theme.ink.opacity(c % 5 == 0 ? 0.55 : 0.18)), lineWidth: c % 5 == 0 ? 1.6 : 0.7)
            }
            for r in 0 ... height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: CGFloat(r) * cell))
                path.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * cell))
                context.stroke(path, with: .color(Theme.ink.opacity(r % 5 == 0 ? 0.55 : 0.18)), lineWidth: r % 5 == 0 ? 1.6 : 0.7)
            }
        }
        .allowsHitTesting(false)
    }

    /// The painting the picture was cut from, over the squares (the player's own cat for a cat puzzle).
    private func reveal(_ puzzle: PawcrossPuzzle) -> some View {
        ZStack {
            Color(red: 1, green: 0.97, blue: 0.9)
            if let image = Self.painting(puzzle) {
                image.resizable().scaledToFit().padding(4)
            }
        }
    }

    static func painting(_ puzzle: PawcrossPuzzle) -> Image? {
        if puzzle.art.hasPrefix("cat:"), let catArt = GameWorld.catArt, let cat = GameSession.shared.cat {
            let sprite = catArt.builder.pose(String(puzzle.art.dropFirst(4)), look: cat.look)
            return catArt.image(sprite, look: cat.look).map { Image(decorative: $0, scale: 1) }
        }
        return GamesLook.picture(puzzle.art)
    }

    // MARK: The side

    private func side(_ board: PawcrossBoard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                modeButton("Fill", symbol: "square.fill", on: !crossing) { crossing = false }
                modeButton("Cross", symbol: "xmark", on: crossing) { crossing = true }
            }
            Button {
                hint()
            } label: {
                HStack(spacing: 6) {
                    if let glass = GamesLook.picture("arcade/ui/icon_game_magnifier.png") {
                        glass.resizable().scaledToFit().frame(width: 26, height: 26)
                    }
                    Text("Hint").font(.system(size: 16, weight: .heavy, design: .rounded))
                    Text("\(Tuning.Arcade.Puzzle.hints - board.hints) left").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .paper(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(board.hints >= Tuning.Arcade.Puzzle.hints || solved)
            .opacity(board.hints >= Tuning.Arcade.Puzzle.hints || solved ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("How to play").font(Theme.title(16))
                Text("Each number is a run of filled squares in its row or column, in order, with a gap between runs. Fill the squares the numbers ask for; cross the ones that must stay empty.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .goldCard(corner: 14)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                if let pat = GamesLook.picture("brand/icon/AppIcon_layer2_cat.png") {
                    pat.resizable().scaledToFit().frame(width: 64, height: 64)
                }
                Text(solved ? "Lovely. See you tomorrow." : "Today's picture is a surprise. Solve it to see it painted.")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(10)
                    .paper(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func modeButton(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(on ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(on ? GamesLook.puzzle : Theme.cream))
                .overlay(Capsule().strokeBorder(Theme.rim, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Playing

    private func load() {
        guard board == nil, let file = Self.file, let puzzle = Pawcross.puzzle(number: number, in: file) else { return }
        var made = PawcrossBoard(puzzle: puzzle)
        let session = GameSession.shared
        if session.arcade.solvedToday(on: session.arcadeDay) {
            // Already solved today: shown finished.
            for r in 0 ..< puzzle.height {
                for c in 0 ..< puzzle.width where puzzle.filled(r, c) {
                    made.set(r, c, .filled)
                }
            }
            solved = true
            seconds = session.arcade.puzzles[number]?.seconds ?? 0
        } else if let saved = Self.saved(number, puzzle), saved.marks.count == puzzle.width * puzzle.height {
            // Carried on from earlier today (kept on this device only).
            for (index, raw) in saved.marks.enumerated() {
                made.set(index / puzzle.width, index % puzzle.width, PawcrossMark(rawValue: raw) ?? .empty)
            }
            seconds = saved.seconds
        }
        board = made
    }

    private func paint(at point: CGPoint, cell: CGFloat) {
        guard var board, !solved else { return }
        let r = Int(point.y / cell), c = Int(point.x / cell)
        guard r >= 0, r < board.puzzle.height, c >= 0, c < board.puzzle.width else { return }
        let current = board.marks[r][c]
        // The first square of a stroke decides what the stroke does: put its mark down, or take it away.
        let stroke = self.stroke ?? {
            let wanted: PawcrossMark = crossing ? .crossed : .filled
            return (current == wanted ? .empty : wanted, [])
        }()
        guard !stroke.done.contains([r, c]) else { return }
        board.set(r, c, stroke.mark)
        self.stroke = (stroke.mark, stroke.done.union([[r, c]]))
        self.board = board
        Sound.tap()
        #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
        #endif
        if board.isSolved {
            finish()
        }
    }

    private func endStroke() {
        stroke = nil
        save()
    }

    private func hint() {
        guard var board, !solved, board.hints < Tuning.Arcade.Puzzle.hints else { return }
        board.hint()
        self.board = board
        Sound.play("ui_sparkle", volume: Tuning.Sound.place)
        save()
        if board.isSolved { finish() }
    }

    private func finish() {
        guard let board, !solved else { return }
        withAnimation(.easeInOut(duration: 0.8)) { solved = true }
        reward = GameSession.shared.solvePuzzle(PuzzleSolve(number: number, seconds: seconds, hints: board.hints))
        Self.clear(number, board.puzzle)
        Sound.play("ui_streak_milestone", volume: Tuning.Sound.levelUp)
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.spring(duration: 0.4)) { showCard = true }
        }
    }

    private func leave() {
        save()
        back()
    }

    // MARK: Today's marks, kept on this device

    private struct Saved: Codable {
        var marks: [Int]
        var seconds: Int
    }

    /// Keyed by the puzzle as well as its number, so a picture changed in an update never gets another's marks.
    private static func key(_ number: Int, _ puzzle: PawcrossPuzzle) -> String {
        "pawcross.progress.\(number).\(puzzle.id)"
    }

    private static func saved(_ number: Int, _ puzzle: PawcrossPuzzle) -> Saved? {
        UserDefaults.standard.data(forKey: key(number, puzzle)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }

    private static func clear(_ number: Int, _ puzzle: PawcrossPuzzle) {
        UserDefaults.standard.removeObject(forKey: key(number, puzzle))
    }

    private func save() {
        guard let board, !solved else { return }
        let marks = board.marks.flatMap { $0.map(\.rawValue) }
        if let data = try? JSONEncoder().encode(Saved(marks: marks, seconds: seconds)) {
            UserDefaults.standard.set(data, forKey: Self.key(number, board.puzzle))
        }
    }
}
