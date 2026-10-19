import Foundation
@testable import HouseCatCore
import Testing

@Suite("Cats in a Row")
struct CatsInARowTests {
    static func seed(_ salt: String) -> DaySeed {
        DaySeed(household: 11, day: GameDay(index: 20000), purpose: "row", salt: salt)
    }

    /// A full board with no line of four anywhere (pairs of columns alternating, row by row).
    static let drawn = ["1122112", "2211221", "1122112", "2211221", "1122112", "2211221"]

    @Test func countersStackFromTheBottomAndAFullColumnTakesNoMore() {
        var board = RowBoard()
        for row in 0 ..< RowBoard.rows {
            #expect(board.drop(row % 2 == 0 ? .first : .second, in: 3) == row)
        }
        #expect(!board.canDrop(in: 3))
        #expect(board.drop(.first, in: 3) == nil)
        #expect(board.drop(.first, in: 7) == nil)
        #expect(board.drop(.first, in: -1) == nil)
        #expect(board.openColumns == [0, 1, 2, 4, 5, 6])
        #expect(board.side(at: RowCell(column: 3, row: 0)) == .first)
        #expect(board.side(at: RowCell(column: 3, row: 5)) == .second)
        #expect(board.side(at: RowCell(column: 2, row: 0)) == nil)
    }

    @Test func fourInALineWinsInEveryDirection() {
        let lines: [(String, [String], [RowCell])] = [
            ("along a row", [".......", ".......", ".......", ".......", ".......", "..1111."],
             (2 ... 5).map { RowCell(column: $0, row: 0) }),
            ("up a column", [".......", ".......", "......1", "......1", "......1", "......1"],
             (0 ... 3).map { RowCell(column: 6, row: $0) }),
            ("rising", [".......", ".......", "...1...", "..12...", ".122...", "1222..."],
             (0 ... 3).map { RowCell(column: $0, row: $0) }),
            ("falling", ["1......", "11.....", "221....", "2221...", "2112...", "1221..."],
             (0 ... 3).map { RowCell(column: $0, row: 5 - $0) }),
        ]
        for (name, picture, cells) in lines {
            let board = RowBoard(picture: picture)
            #expect(board.hasWon(.first), "\(name)")
            #expect(!board.hasWon(.second), "\(name)")
            #expect(board.winningCells(.first) == Set(cells), "\(name)")
        }
    }

    @Test func threeInALineOrALineBrokenAcrossColumnsIsNoWin() {
        // Three along, three up, and a column's top three with the next column's bottom one (adjacent bits, were
        // the columns not kept apart).
        let board = RowBoard(picture: [".......", "1......", "1......", "1......", ".......", ".1.111."])
        #expect(!board.hasWon(.first))
        #expect(board.winningCells(.first).isEmpty)
        let wrap = RowBoard(picture: ["1......", "1......", "1......", "2......", "2......", "21....."])
        #expect(!wrap.hasWon(.first))
        // The far edge to the near edge along a row.
        let edges = RowBoard(picture: [".......", ".......", ".......", ".......", "1.....1", "11...11"])
        #expect(!edges.hasWon(.first))
    }

    @Test func aFullBoardWithNoLineIsADraw() throws {
        let board = RowBoard(picture: Self.drawn)
        #expect(board.isFull)
        #expect(!board.hasWon(.first) && !board.hasWon(.second))
        // Played out as a game, turn by turn, it ends in a draw.
        let moves = try #require(Self.order(Self.drawn))
        var game = RowGame()
        for column in moves {
            #expect(game.outcome == .playing)
            #expect(game.play(column) != nil)
        }
        #expect(game.outcome == .draw)
        #expect(game.play(0) == nil)
    }

    @Test func aGameEndsOnTheWinningCounterAndTakesNoMoreMoves() {
        var game = RowGame()
        for column in [0, 6, 1, 6, 2, 6] {
            game.play(column)
        }
        #expect(game.turn == .first)
        #expect(game.play(3) == RowCell(column: 3, row: 0))
        #expect(game.outcome == .won(.first, Set((0 ... 3).map { RowCell(column: $0, row: 0) })))
        #expect(game.play(5) == nil)
        #expect(game.history == [0, 6, 1, 6, 2, 6, 3])
    }

    @Test func everyCatTakesAWinOnTheBoard() {
        // The second side has three up the last column and three along the bottom-left; any cat finishes one.
        let board = RowBoard(picture: [".......", ".......", "......2", "......2", "1.....2", "111...1"])
        for depth in 1 ... 6 {
            var seed = Self.seed("win\(depth)")
            let column = RowBrain.move(on: board, for: .second, skill: RowSkill(depth: depth, whim: 0.9), seed: &seed)
            #expect(board.wins(.second, droppingIn: column))
        }
    }

    @Test func fromTheSecondCatOnALossNextTurnIsBlocked() {
        let board = RowBoard(picture: [".......", ".......", ".......", ".......", "2......", "2111..2"])
        for depth in 2 ... 7 {
            for game in 0 ..< 5 {
                var seed = Self.seed("block\(depth).\(game)")
                #expect(RowBrain.move(on: board, for: .second, skill: RowSkill(depth: depth, whim: 0.5), seed: &seed) == 4)
            }
        }
    }

    @Test func aThinkingCatNeverSetsUpYourWin() {
        // Dropping in column 3 would let the first side win on top of it (column 3, row 3 completes a rising line).
        let board = RowBoard(picture: [".......", ".......", ".......", "..1....", ".122...", "1221..."])
        var trap = board
        trap.drop(.second, in: 3)
        #expect(trap.wins(.first, droppingIn: 3))
        for depth in 3 ... 7 {
            for game in 0 ..< 6 {
                var seed = Self.seed("trap\(depth).\(game)")
                #expect(RowBrain.move(on: board, for: .second, skill: RowSkill(depth: depth, whim: 0.6), seed: &seed) != 3)
            }
        }
    }

    @Test func theSameSeedPlaysTheSameMove() {
        let board = RowBoard(picture: [".......", ".......", ".......", ".......", "...2...", "..11..."])
        for depth in [1, 3, 6] {
            var a = Self.seed("same"), b = Self.seed("same")
            let skill = RowSkill(depth: depth, whim: 0.3)
            #expect(RowBrain.move(on: board, for: .second, skill: skill, seed: &a) == RowBrain.move(on: board, for: .second, skill: skill, seed: &b))
        }
    }

    @Test func theCleverestCatBeatsACatPlayingAtRandom() {
        var wins = 0
        for game in 0 ..< 12 {
            var g = RowGame()
            var seed = Self.seed("match\(game)")
            while g.outcome == .playing {
                let side = g.turn
                let skill = side == .first ? RowSkill(depth: 1, whim: 1) : RowSkill(depth: 5, whim: 0)
                g.play(RowBrain.move(on: g.board, for: side, skill: skill, seed: &seed))
            }
            if case .won(.second, _) = g.outcome {
                wins += 1
            }
        }
        #expect(wins == 12)
    }

    @Test func aDeeperLookBeatsAShallowOneMostOfTheTime() {
        var deep = 0, shallow = 0
        for game in 0 ..< 16 {
            var g = RowGame()
            var seed = Self.seed("deep\(game)")
            // Alternate who starts so the first move's edge evens out.
            let deepFirst = game % 2 == 0
            while g.outcome == .playing {
                let deepTurn = (g.turn == .first) == deepFirst
                let skill = deepTurn ? RowSkill(depth: 6, whim: 0) : RowSkill(depth: 2, whim: 0.15)
                g.play(RowBrain.move(on: g.board, for: g.turn, skill: skill, seed: &seed))
            }
            if case let .won(side, _) = g.outcome {
                if (side == .first) == deepFirst { deep += 1 } else { shallow += 1 }
            }
        }
        #expect(deep >= 12)
        #expect(shallow <= 2)
    }

    @Test func theDeepestSearchAnswersQuicklyOnAnEmptyBoard() {
        var seed = Self.seed("time")
        // This thread's own working time, so a busy machine running other tests doesn't count against it.
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let column = RowBrain.move(on: RowBoard(), for: .first, skill: RowSkill(depth: Tuning.Arcade.Row.deepest, whim: 0), seed: &seed)
        let seconds = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
        #expect(column == 3)
        #expect(seconds < 1, "\(seconds) s")
    }

    /// An order of moves, turn by turn from the first side, that ends on `picture`'s board.
    static func order(_ picture: [String]) -> [Int]? {
        let target = RowBoard(picture: picture)
        var board = RowBoard()
        var moves: [Int] = []
        func search(_ side: RowSide) -> Bool {
            if board.isFull {
                return true
            }
            for column in board.openColumns where target.side(at: RowCell(column: column, row: board.heights[column])) == side {
                board.drop(side, in: column)
                moves.append(column)
                if !board.hasWon(side), search(side.other) {
                    return true
                }
                board.lift(from: column)
                moves.removeLast()
            }
            return false
        }
        return search(.first) ? moves : nil
    }
}
