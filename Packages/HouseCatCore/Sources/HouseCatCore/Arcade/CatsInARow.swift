import Foundation

/// Cats in a Row (the Games menu): four in a row on a seven by six board, the counters the two cats' faces. The
/// player's cat plays first against one of the cats in `ArcadeFile.opponents` (or a second person on the same
/// device). The board is two bitboards, a column's cells `rows + 1` bits apart, so a win is four shifts.
public enum RowSide: Int, Codable, Sendable, CaseIterable {
    /// The player's cat (it always starts).
    case first = 1
    /// The other cat.
    case second = 2

    public var other: RowSide {
        self == .first ? .second : .first
    }
}

/// A cell on the board: column from the left, row from the bottom.
public struct RowCell: Hashable, Codable, Sendable {
    public let column: Int
    public let row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public struct RowBoard: Equatable, Sendable {
    public static let columns = Tuning.Arcade.Row.columns
    public static let rows = Tuning.Arcade.Row.rows
    static let height = rows + 1

    /// Each side's counters, bit `column * height + row`.
    private(set) var bits: [UInt64] = [0, 0]
    /// How many counters each column holds.
    public private(set) var heights = [Int](repeating: 0, count: columns)
    public private(set) var moves = 0

    public init() {}

    /// A board from a picture, top row first: "1" the first side, "2" the second, "." empty (for tests).
    public init(picture: [String]) {
        for (index, line) in picture.reversed().enumerated() {
            for (column, mark) in line.enumerated() where mark != "." {
                bits[mark == "1" ? 0 : 1] |= Self.bit(column, index)
                heights[column] = max(heights[column], index + 1)
                moves += 1
            }
        }
    }

    static func bit(_ column: Int, _ row: Int) -> UInt64 {
        1 << UInt64(column * height + row)
    }

    public func canDrop(in column: Int) -> Bool {
        column >= 0 && column < Self.columns && heights[column] < Self.rows
    }

    public var openColumns: [Int] {
        (0 ..< Self.columns).filter { canDrop(in: $0) }
    }

    public var isFull: Bool {
        moves == Self.columns * Self.rows
    }

    public func side(at cell: RowCell) -> RowSide? {
        let bit = Self.bit(cell.column, cell.row)
        if bits[0] & bit != 0 { return .first }
        if bits[1] & bit != 0 { return .second }
        return nil
    }

    /// Drops a counter in `column`; returns the row it lands in (nil if the column is full).
    @discardableResult
    public mutating func drop(_ side: RowSide, in column: Int) -> Int? {
        guard canDrop(in: column) else { return nil }
        let row = heights[column]
        bits[side.rawValue - 1] |= Self.bit(column, row)
        heights[column] += 1
        moves += 1
        return row
    }

    /// Takes back the top counter of `column` (the search's undo).
    mutating func lift(from column: Int) {
        let row = heights[column] - 1
        let bit = Self.bit(column, row)
        bits[0] &= ~bit
        bits[1] &= ~bit
        heights[column] -= 1
        moves -= 1
    }

    /// The shifts for the four directions: up a column, along a row, and the two diagonals.
    static let directions: [Int] = [1, height, height - 1, height + 1]

    static func hasLine(_ b: UInt64) -> Bool {
        for shift in directions {
            let s = UInt64(shift)
            let pairs = b & (b >> s)
            if pairs & (pairs >> (2 * s)) != 0 {
                return true
            }
        }
        return false
    }

    public func hasWon(_ side: RowSide) -> Bool {
        Self.hasLine(bits[side.rawValue - 1])
    }

    /// Whether dropping in `column` would win for `side` right now.
    public func wins(_ side: RowSide, droppingIn column: Int) -> Bool {
        guard canDrop(in: column) else { return false }
        return Self.hasLine(bits[side.rawValue - 1] | Self.bit(column, heights[column]))
    }

    /// Every cell in a winning line of `side` (all of them, when a counter makes two lines at once).
    public func winningCells(_ side: RowSide) -> Set<RowCell> {
        var cells = Set<RowCell>()
        for line in Self.windows where line.allSatisfy({ self.side(at: $0) == side }) {
            cells.formUnion(line)
        }
        return cells
    }

    /// Every line of four cells on the board (69 on a seven by six board).
    static let windows: [[RowCell]] = {
        let n = Tuning.Arcade.Row.lineLength
        var lines: [[RowCell]] = []
        for column in 0 ..< columns {
            for row in 0 ..< rows {
                for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                    let endColumn = column + dc * (n - 1), endRow = row + dr * (n - 1)
                    guard endColumn >= 0, endColumn < columns, endRow >= 0, endRow < rows else { continue }
                    lines.append((0 ..< n).map { RowCell(column: column + dc * $0, row: row + dr * $0) })
                }
            }
        }
        return lines
    }()

    /// The window masks, for the evaluation.
    static let windowMasks: [UInt64] = windows.map { line in
        line.reduce(0) { $0 | bit($1.column, $1.row) }
    }

    static let centreMask: UInt64 = (0 ..< rows).reduce(0) { $0 | bit(columns / 2, $1) }

    /// How good the board looks for `side`: open lines of one, two and three, and the middle column.
    func score(for side: RowSide) -> Int {
        let mine = bits[side.rawValue - 1], theirs = bits[side.other.rawValue - 1]
        let values = Tuning.Arcade.Row.windowScores
        var total = 0
        for mask in Self.windowMasks {
            let m = (mine & mask).nonzeroBitCount, t = (theirs & mask).nonzeroBitCount
            if t == 0, m < 4 {
                total += values[m]
            } else if m == 0, t < 4 {
                total -= values[t]
            }
        }
        total += Tuning.Arcade.Row.centreScore * ((mine & Self.centreMask).nonzeroBitCount - (theirs & Self.centreMask).nonzeroBitCount)
        return total
    }
}

/// A game in progress: whose turn, the moves so far and how it ended.
public struct RowGame: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case playing
        case won(RowSide, Set<RowCell>)
        case draw
    }

    public private(set) var board = RowBoard()
    public private(set) var turn = RowSide.first
    public private(set) var history: [Int] = []
    public private(set) var outcome = Outcome.playing

    public init() {}

    /// Plays the side whose turn it is in `column`; returns where the counter landed, nil if the move is not allowed.
    @discardableResult
    public mutating func play(_ column: Int) -> RowCell? {
        guard outcome == .playing, let row = board.drop(turn, in: column) else { return nil }
        history.append(column)
        if board.hasWon(turn) {
            outcome = .won(turn, board.winningCells(turn))
        } else if board.isFull {
            outcome = .draw
        } else {
            turn = turn.other
        }
        return RowCell(column: column, row: row)
    }
}

/// A cat to play against: how far it looks ahead and how often it plays a move on a whim instead.
public struct RowSkill: Codable, Equatable, Sendable {
    public var depth: Int
    /// 0…1: the share of its moves played at random (never a move that hands the game over, from depth 2).
    public var whim: Double

    public init(depth: Int, whim: Double) {
        self.depth = depth
        self.whim = whim
    }
}

/// How a cat chooses its move (negamax with alpha-beta, the middle columns first). Deterministic for a seed.
public enum RowBrain {
    static let win = 1_000_000

    /// The column `side` plays on `board`.
    public static func move(on board: RowBoard, for side: RowSide, skill: RowSkill, seed: inout DaySeed) -> Int {
        let open = board.openColumns
        precondition(!open.isEmpty, "no move on a full board")
        // A win on the board is always taken, and from depth 2 a loss next turn is always blocked.
        if let winning = open.first(where: { board.wins(side, droppingIn: $0) }) {
            return winning
        }
        let threats = open.filter { board.wins(side.other, droppingIn: $0) }
        if skill.depth >= 2, let block = threats.first {
            return block
        }
        // Moves that do not set up the other side's win straight after.
        let safe = open.filter { column in
            var next = board
            next.drop(side, in: column)
            return !next.openColumns.contains { next.wins(side.other, droppingIn: $0) }
        }
        if Double(seed.below(1000)) / 1000 < skill.whim {
            let pool = skill.depth >= 3 && !safe.isEmpty ? safe : open
            return pool[seed.below(pool.count)]
        }
        let depth = min(max(skill.depth, 1), Tuning.Arcade.Row.deepest)
        var best = Int.min, choices: [Int] = []
        var scratch = board
        for column in ordered(open) {
            scratch.drop(side, in: column)
            // Only a move as good as the best so far needs its exact value (ties stay in, for variety), so the
            // window shuts below that and the rest are cut short.
            let floor = best == Int.min ? -win * 2 : best - 1
            let value = -negamax(&scratch, side: side.other, depth: depth - 1, alpha: -win * 2, beta: -floor)
            scratch.lift(from: column)
            if value > best {
                best = value
                choices = [column]
            } else if value == best {
                choices.append(column)
            }
        }
        return choices[seed.below(choices.count)]
    }

    /// The middle columns first, so alpha-beta cuts early.
    static func ordered(_ columns: [Int]) -> [Int] {
        let middle = Double(RowBoard.columns - 1) / 2
        return columns.sorted { abs(Double($0) - middle) < abs(Double($1) - middle) }
    }

    /// The value of the position for `side`, to move, looking `depth` moves ahead. Quicker wins score higher.
    static func negamax(_ board: inout RowBoard, side: RowSide, depth: Int, alpha: Int, beta: Int) -> Int {
        let open = board.openColumns
        if open.isEmpty {
            return 0
        }
        for column in open where board.wins(side, droppingIn: column) {
            return win + depth
        }
        if depth <= 0 {
            return board.score(for: side)
        }
        var alpha = alpha
        var best = -win * 2
        for column in ordered(open) {
            board.drop(side, in: column)
            let value = -negamax(&board, side: side.other, depth: depth - 1, alpha: -beta, beta: -alpha)
            board.lift(from: column)
            best = max(best, value)
            alpha = max(alpha, value)
            if alpha >= beta {
                break
            }
        }
        return best
    }
}
