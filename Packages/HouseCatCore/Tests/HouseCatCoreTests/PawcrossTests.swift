import Foundation
@testable import HouseCatCore
import Testing

@Suite("Pawcross")
struct PawcrossTests {
    static let cross = PawcrossPuzzle(id: "test", title: "A test", art: "ui/icon_xp_star.png",
                                      rows: ["..#..", "..#..", "#####", "..#..", "..#.."])

    @Test func cluesAreTheRunsOfFilledSquares() {
        #expect(Pawcross.clues([false, true, true, false, true]) == [2, 1])
        #expect(Pawcross.clues([false, false]) == [0])
        #expect(Pawcross.clues([true, true, true]) == [3])
        #expect(Self.cross.rowClues == [[1], [1], [5], [1], [1]])
        #expect(Self.cross.columnClues == [[1], [1], [5], [1], [1]])
    }

    @Test func theSolverFinishesAFairPuzzleAndLeavesAGuessUndecided() {
        #expect(Pawcross.isFair(Self.cross))
        // Two squares on a diagonal: either diagonal fits the same numbers.
        let diagonal = PawcrossPuzzle(id: "d", title: "D", art: "", rows: ["#.", ".#"])
        #expect(!Pawcross.isFair(diagonal))
        let solved = Pawcross.solve(rows: diagonal.rowClues, columns: diagonal.columnClues)
        #expect(solved.allSatisfy { $0.allSatisfy { $0 == nil } })
    }

    @Test func aBoardIsSolvedByItsFilledSquaresWhateverItsCrosses() {
        var board = PawcrossBoard(puzzle: Self.cross)
        #expect(!board.isSolved)
        for r in 0 ..< 5 {
            for c in 0 ..< 5 where Self.cross.filled(r, c) {
                board.set(r, c, .filled)
            }
        }
        board.set(0, 0, .crossed)
        #expect(board.isSolved)
        #expect(board.rowDone(2) && board.columnDone(2))
        board.set(4, 4, .filled)
        #expect(!board.isSolved)
        #expect(!board.rowDone(4))
    }

    @Test func aHintPutsOneSquareRightInTheLineNearestDone() {
        var board = PawcrossBoard(puzzle: Self.cross)
        for c in 0 ..< 4 {
            board.set(2, c, .filled)
        }
        let at = board.hint()
        #expect(at?.row == 2 && at?.column == 4)
        #expect(board.marks[2][4] == .filled)
        #expect(board.hints == 1)
        // A wrong square is put right too.
        board.set(0, 0, .filled)
        while board.hint() != nil {}
        #expect(board.isSolved)
        #expect(board.marks[0][0] == .crossed)
    }

    @Test func puzzleNumbersGoRoundTheList() {
        let file = PawcrossFile(version: 1, puzzles: [Self.cross, PawcrossPuzzle(id: "b", title: "B", art: "", rows: ["#"])])
        #expect(Pawcross.puzzle(number: 1, in: file)?.id == "test")
        #expect(Pawcross.puzzle(number: 2, in: file)?.id == "b")
        #expect(Pawcross.puzzle(number: 3, in: file)?.id == "test")
        #expect(Pawcross.puzzle(number: 0, in: file)?.id == "b")
    }

    @Test func everyPuzzleInTheFileIsFairAndItsPaintingIsThere() throws {
        let repo = ContentValidationTests.repo
        let file = try JSONDecoder().decode(PawcrossFile.self, from: Data(contentsOf: repo.appendingPathComponent("Content/pawcross.json")))
        let art = try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent("App/Art/art.json"))) as? [String: Any]
        let files = try #require(art?["files"] as? [String: Any])
        #expect(file.puzzles.count >= 28, "four weeks at least")
        #expect(Set(file.puzzles.map(\.id)).count == file.puzzles.count)
        for (index, puzzle) in file.puzzles.enumerated() {
            #expect(Set(puzzle.rows.map(\.count)).count == 1, "\(puzzle.id) rows")
            #expect(puzzle.rows.joined().allSatisfy { $0 == "#" || $0 == "." }, "\(puzzle.id) marks")
            #expect(Pawcross.isFair(puzzle), "\(puzzle.id) needs a guess")
            let title = puzzle.title.replacingOccurrences(of: "{cat}", with: "Biscuit")
            #expect(!title.contains("{") && ContentValidationTests.problems(in: title, limit: 32).isEmpty, "\(puzzle.title)")
            if puzzle.art.hasPrefix("cat:") {
                #expect(CatPose(rawValue: String(puzzle.art.dropFirst(4))) != nil, "\(puzzle.id) pose")
            } else {
                #expect(files[puzzle.art] != nil, "\(puzzle.id): \(puzzle.art) is not in the app")
            }
            // Small early in the week, big at the weekend (No. 1 is a Monday).
            let weekday = index % 7
            let size = max(puzzle.width, puzzle.height)
            #expect(weekday < 2 ? size <= 10 : weekday < 4 ? size <= 12 : (12 ... 15).contains(size), "\(puzzle.id) on weekday \(weekday)")
            // A picture fills between about a quarter and three quarters of its grid, with no empty line.
            let filled = puzzle.rows.joined().filter { $0 == "#" }.count
            #expect((0.28 ... 0.75).contains(Double(filled) / Double(puzzle.width * puzzle.height)), "\(puzzle.id) fill")
            #expect(!puzzle.rowClues.contains([0]) && !puzzle.columnClues.contains([0]), "\(puzzle.id) has an empty line")
        }
        #expect(Tuning.Arcade.Puzzle.firstDay.weekday == 1)
    }
}
