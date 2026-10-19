import Foundation

/// Pawcross, Pat's daily puzzle (a picture logic puzzle): fill the squares the numbers ask for, each number a run
/// of filled squares in that row or column, in order; the finished picture turns into the painting it was cut from.
/// One a day (`ArcadePuzzles.number`), the same for everyone, small on Monday and big at the weekend
/// (Content/pawcross.json, made by tools/content/pawcross.py). Every puzzle can be solved a line at a time with no
/// guessing (`Pawcross.solve`, checked by the content tests).
public struct PawcrossPuzzle: Codable, Equatable, Sendable {
    public var id: String
    /// What the picture is, shown once it is solved ("A brass key").
    public var title: String
    /// The painting it turns into: an art path, or `cat:<pose>` for the player's own cat in that pose.
    public var art: String
    /// Top row first: "#" filled, "." empty.
    public var rows: [String]

    public init(id: String, title: String, art: String, rows: [String]) {
        self.id = id
        self.title = title
        self.art = art
        self.rows = rows
    }

    public var height: Int {
        rows.count
    }

    public var width: Int {
        rows.first?.count ?? 0
    }

    public func filled(_ row: Int, _ column: Int) -> Bool {
        Array(rows[row])[column] == "#"
    }

    public var rowClues: [[Int]] {
        (0 ..< height).map { r in Pawcross.clues((0 ..< width).map { filled(r, $0) }) }
    }

    public var columnClues: [[Int]] {
        (0 ..< width).map { c in Pawcross.clues((0 ..< height).map { filled($0, c) }) }
    }
}

public struct PawcrossFile: Codable, Sendable {
    public var version: Int
    public var puzzles: [PawcrossPuzzle]
}

public enum Pawcross {
    /// The runs of filled squares along a line ([0] for none).
    public static func clues(_ line: [Bool]) -> [Int] {
        var runs: [Int] = []
        var run = 0
        for filled in line {
            if filled {
                run += 1
            } else if run > 0 {
                runs.append(run)
                run = 0
            }
        }
        if run > 0 { runs.append(run) }
        return runs.isEmpty ? [0] : runs
    }

    /// Every way a clue fits a line of `length`.
    static func placements(_ clue: [Int], length: Int) -> [[Bool]] {
        if clue == [0] { return [Array(repeating: false, count: length)] }
        var out: [[Bool]] = []
        func place(_ index: Int, _ start: Int, _ line: [Bool]) {
            if index == clue.count {
                out.append(line + Array(repeating: false, count: length - line.count))
                return
            }
            let rest = clue[(index + 1)...].reduce(0, +) + clue.count - index - 1
            guard start <= length - rest - clue[index] else { return }
            for s in start ... (length - rest - clue[index]) {
                var next = line + Array(repeating: false, count: s - line.count) + Array(repeating: true, count: clue[index])
                if index < clue.count - 1 { next.append(false) }
                place(index + 1, next.count, next)
            }
        }
        place(0, 0, [])
        return out
    }

    /// Solves a line at a time from the clues alone: each square decided (filled or not) or nil where the lines
    /// never settle it. A puzzle is fair when nothing is left nil.
    public static func solve(rows: [[Int]], columns: [[Int]]) -> [[Bool?]] {
        let height = rows.count, width = columns.count
        var grid = Array(repeating: [Bool?](repeating: nil, count: width), count: height)
        var rowWays = rows.map { placements($0, length: width) }
        var columnWays = columns.map { placements($0, length: height) }
        var changed = true
        while changed {
            changed = false
            for r in 0 ..< height {
                rowWays[r] = rowWays[r].filter { way in (0 ..< width).allSatisfy { grid[r][$0] == nil || grid[r][$0] == way[$0] } }
                for c in 0 ..< width where grid[r][c] == nil {
                    if let first = rowWays[r].first?[c], rowWays[r].allSatisfy({ $0[c] == first }) {
                        grid[r][c] = first
                        changed = true
                    }
                }
            }
            for c in 0 ..< width {
                columnWays[c] = columnWays[c].filter { way in (0 ..< height).allSatisfy { grid[$0][c] == nil || grid[$0][c] == way[$0] } }
                for r in 0 ..< height where grid[r][c] == nil {
                    if let first = columnWays[c].first?[r], columnWays[c].allSatisfy({ $0[r] == first }) {
                        grid[r][c] = first
                        changed = true
                    }
                }
            }
        }
        return grid
    }

    public static func isFair(_ puzzle: PawcrossPuzzle) -> Bool {
        let solved = solve(rows: puzzle.rowClues, columns: puzzle.columnClues)
        return (0 ..< puzzle.height).allSatisfy { r in (0 ..< puzzle.width).allSatisfy { solved[r][$0] == puzzle.filled(r, $0) } }
    }

    /// The puzzle for a puzzle number (No. 1 is the first; the list goes round again when it runs out).
    public static func puzzle(number: Int, in file: PawcrossFile) -> PawcrossPuzzle? {
        guard !file.puzzles.isEmpty else { return nil }
        let count = file.puzzles.count
        return file.puzzles[((number - 1) % count + count) % count]
    }
}

/// What the player has put in a square.
public enum PawcrossMark: Int, Codable, Sendable {
    case empty, filled, crossed
}

/// A puzzle being solved: the marks, and the hints taken.
public struct PawcrossBoard: Equatable, Sendable {
    public let puzzle: PawcrossPuzzle
    public private(set) var marks: [[PawcrossMark]]
    public private(set) var hints = 0

    public init(puzzle: PawcrossPuzzle) {
        self.puzzle = puzzle
        marks = Array(repeating: Array(repeating: .empty, count: puzzle.width), count: puzzle.height)
    }

    public mutating func set(_ row: Int, _ column: Int, _ mark: PawcrossMark) {
        guard row >= 0, row < puzzle.height, column >= 0, column < puzzle.width else { return }
        marks[row][column] = mark
    }

    /// Solved: exactly the picture's squares are filled (crosses are only the player's notes).
    public var isSolved: Bool {
        (0 ..< puzzle.height).allSatisfy { r in (0 ..< puzzle.width).allSatisfy { (marks[r][$0] == .filled) == puzzle.filled(r, $0) } }
    }

    /// A row or column whose filled squares already make its clue (its numbers fade).
    public func rowDone(_ row: Int) -> Bool {
        Pawcross.clues(marks[row].map { $0 == .filled }) == puzzle.rowClues[row]
    }

    public func columnDone(_ column: Int) -> Bool {
        Pawcross.clues(marks.map { $0[column] == .filled }) == puzzle.columnClues[column]
    }

    /// A hint: one square put right, the first wrong one in the row nearest done (a wrong fill is cleared, a missing
    /// one filled). Nearest done is the fewest squares wrong, then the most already filled right, so the hint lands
    /// on the line the player has been working on. Returns where, or nil when nothing is wrong.
    @discardableResult
    public mutating func hint() -> (row: Int, column: Int)? {
        var best: (row: Int, column: Int, left: Int, right: Int)?
        for r in 0 ..< puzzle.height {
            let wrong = (0 ..< puzzle.width).filter { (marks[r][$0] == .filled) != puzzle.filled(r, $0) }
            guard let first = wrong.first else { continue }
            let right = (0 ..< puzzle.width).filter { marks[r][$0] == .filled && puzzle.filled(r, $0) }.count
            if best == nil || wrong.count < best!.left || (wrong.count == best!.left && right > best!.right) {
                best = (r, first, wrong.count, right)
            }
        }
        guard let best else { return nil }
        marks[best.row][best.column] = puzzle.filled(best.row, best.column) ? .filled : .crossed
        hints += 1
        return (best.row, best.column)
    }
}
