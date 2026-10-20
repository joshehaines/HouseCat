import Foundation
@testable import HouseCatCore
import Testing

@Suite("Purrfect Match")
struct PurrfectMatchTests {
    static func seed(_ salt: String) -> DaySeed {
        DaySeed(household: 3, day: GameDay(index: 20000), purpose: "match", salt: salt)
    }

    static func level(_ layout: [String] = Array(repeating: "ooooo", count: 5), moves: Int = 10, kinds: Int = 6,
                      goals: [String] = ["collect:fish:3"], stars: [Int] = [400, 800]) -> MatchLevel
    {
        MatchLevel(id: 0, layout: layout, moves: moves, kinds: kinds, goals: goals, stars: stars, title: "Test")
    }

    static func game(_ picture: [String], level: MatchLevel = level(), salt: String = "board") -> MatchGame {
        var game = MatchGame(level: level, seed: seed(salt))
        game.set(picture)
        return game
    }

    @Test func aNewBoardHasNothingLinedUpAndAMoveWhateverTheShape() {
        let layouts: [[String]] = [
            Array(repeating: "oooooooo", count: 8),
            ["..oooo..", ".oooooo.", "oooooooo", "oooooooo", ".oooooo.", "..oooo.."],
            ["ooooooo", "oopppoo", "ooooooo", "ddddddd", "ooooooo"],
        ]
        for (n, layout) in layouts.enumerated() {
            for attempt in 0 ..< 30 {
                let game = MatchGame(level: Self.level(layout, kinds: 4 + attempt % 3), seed: Self.seed("\(n).\(attempt)"))
                #expect(!game.moves().isEmpty)
                var lined = false
                for y in 0 ..< game.height {
                    for x in 0 ..< game.width - 2 {
                        let kinds = (0 ..< 3).map { game.piece(at: MatchPoint(x + $0, y))?.kind }
                        if let k = kinds[0], kinds.allSatisfy({ $0 == k }) { lined = true }
                    }
                }
                for x in 0 ..< game.width {
                    for y in 0 ..< game.height - 2 {
                        let kinds = (0 ..< 3).map { game.piece(at: MatchPoint(x, y + $0))?.kind }
                        if let k = kinds[0], kinds.allSatisfy({ $0 == k }) { lined = true }
                    }
                }
                #expect(!lined)
            }
        }
        // The same seed deals the same board.
        let a = MatchGame(level: Self.level(), seed: Self.seed("same")), b = MatchGame(level: Self.level(), seed: Self.seed("same"))
        #expect((0 ..< 25).allSatisfy { a.piece(at: MatchPoint($0 % 5, $0 / 5)) == b.piece(at: MatchPoint($0 % 5, $0 / 5)) })
    }

    @Test func aSwapThatLinesNothingUpIsNotAMoveAndCostsNothing() {
        var game = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f y c e"])
        #expect(!game.canSwap(MatchPoint(0, 0), MatchPoint(1, 0)))
        #expect(game.swap(MatchPoint(0, 0), MatchPoint(1, 0)).isEmpty)
        #expect(!game.canSwap(MatchPoint(0, 0), MatchPoint(2, 0)))
        #expect(game.movesLeft == 10 + Tuning.Arcade.Match.spareMoves)
        #expect(game.piece(at: MatchPoint(0, 0))?.kind == .yarn)
    }

    @Test func threeInALineClearAndThePiecesAboveFallIntoTheGap() throws {
        var game = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f y c e"])
        let waves = game.swap(MatchPoint(2, 3), MatchPoint(2, 4))
        let first = try #require(waves.first)
        #expect(Set(first.cleared.keys) == [MatchPoint(0, 4), MatchPoint(1, 4), MatchPoint(2, 4)])
        #expect(first.made.isEmpty)
        #expect(game.collected[.fish, default: 0] >= 3)
        #expect(game.movesLeft == 9 + Tuning.Arcade.Match.spareMoves)
        // Each of the three columns drops one: four falls a column (the swapped yarn included) and one new piece.
        #expect(first.falls.count == 12)
        #expect(first.spawned.count == 3)
        #expect(Set(first.spawned.keys) == [MatchPoint(0, 0), MatchPoint(1, 0), MatchPoint(2, 0)])
        #expect(first.falls.contains { $0.from == MatchPoint(2, 3) && $0.to == MatchPoint(2, 4) })
        #expect(first.points == 30)
    }

    @Test func fourAlongARowMakeAPawSwipeThatClearsAColumn() throws {
        var game = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f y f e"])
        let first = try #require(game.swap(MatchPoint(2, 3), MatchPoint(2, 4)).first)
        #expect(first.made == [MatchPoint(2, 4): MatchPiece(kind: .fish, special: .swipeColumn)])
        #expect(game.made[.swipeColumn] == 1)
        // A swipe in a line goes off: its whole column with it.
        var swipe = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f| f c f e"])
        let blast = try #require(swipe.swap(MatchPoint(2, 4), MatchPoint(2, 3)).first)
        #expect(blast.fired[MatchPoint(0, 4)] == .swipeColumn)
        for y in 0 ..< 5 {
            #expect(blast.cleared[MatchPoint(0, y)] != nil)
        }
    }

    @Test func anLMakesABoxThatClearsTheNineRoundIt() throws {
        var game = Self.game(["y m b c e", "m f c e y", "b f e y m", "f c f m b", "c f y c e"])
        let first = try #require(game.swap(MatchPoint(1, 3), MatchPoint(1, 4)).first)
        #expect(first.made == [MatchPoint(1, 3): MatchPiece(kind: .fish, special: .box)])
        #expect(first.cleared.count == 5)
        var box = Self.game(["y m b c e", "m b c e y", "b f f# y m", "c e y f m", "f m m c e"])
        let blast = try #require(box.swap(MatchPoint(3, 3), MatchPoint(3, 2)).first)
        #expect(blast.fired[MatchPoint(2, 2)] == .box)
        for dy in -1 ... 1 {
            for dx in -1 ... 1 {
                #expect(blast.cleared[MatchPoint(2 + dx, 2 + dy)] != nil)
            }
        }
    }

    @Test func fiveInALineMakeTheLaserWhichClearsEveryPieceOfAKind() throws {
        var game = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f c f f"])
        let first = try #require(game.swap(MatchPoint(2, 3), MatchPoint(2, 4)).first)
        #expect(first.made == [MatchPoint(2, 4): MatchPiece(kind: nil, special: .laser)])
        var laser = Self.game(["y f b c e", "m b c f y", "f c e y m", "c e y m f", "L f m c e"])
        #expect(laser.canSwap(MatchPoint(0, 4), MatchPoint(1, 4)))
        let blast = try #require(laser.swap(MatchPoint(0, 4), MatchPoint(1, 4)).first)
        let fish = blast.cleared.values.filter { $0.kind == .fish }.count
        #expect(fish == 5)
        #expect(blast.fired[MatchPoint(1, 4)] == .laser)
    }

    @Test func twoLasersTogetherClearTheWholeBoard() throws {
        var game = Self.game(["y f b c e", "m b c f y", "f c e y m", "c e y m f", "L L m c e"])
        let blast = try #require(game.swap(MatchPoint(0, 4), MatchPoint(1, 4)).first)
        #expect(blast.cleared.count >= 23)
    }

    @Test func dustIsClearedByMatchingOnItAndDoubleDustTakesTwo() throws {
        let level = Self.level(["ooooo", "ooooo", "ooooo", "ooooo", "dDdoo"], goals: ["dust"])
        var game = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f y c e"], level: level)
        #expect(game.remaining(.dust) == 4)
        let first = try #require(game.swap(MatchPoint(2, 3), MatchPoint(2, 4)).first)
        #expect(first.dustCleared == [MatchPoint(0, 4), MatchPoint(1, 4), MatchPoint(2, 4)])
        #expect(game.dust(at: MatchPoint(1, 4)) >= 0 && game.dust(at: MatchPoint(1, 4)) <= 1)
        #expect(game.dust(at: MatchPoint(0, 4)) == 0)
        #expect(game.remaining(.dust) <= 1)
    }

    @Test func aParcelOpensToAMatchBesideItAndPiecesSlideRoundIt() throws {
        let level = Self.level(["ooooo", "ooooo", "ooooo", "ooooo", "oooPo"], goals: ["parcels"])
        var game = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f y . e"], level: level)
        #expect(game.parcel(at: MatchPoint(3, 4)) == 2)
        #expect(!game.canSwap(MatchPoint(3, 3), MatchPoint(3, 4)))
        let first = try #require(game.swap(MatchPoint(2, 3), MatchPoint(2, 4)).first)
        #expect(first.parcelsHit == [MatchPoint(3, 4)])
        #expect(game.parcel(at: MatchPoint(3, 4)) <= 1)
        // Nothing falls through a parcel: the piece above it stays put unless the parcel opened.
        if game.parcel(at: MatchPoint(3, 4)) > 0 {
            #expect(game.piece(at: MatchPoint(3, 4)) == nil)
        }
    }

    @Test func aTangledPieceCannotBeMovedUntilItIsMatched() throws {
        let level = Self.level(["tooo", "oooo", "oooo"], goals: ["collect:fish:3"])
        var game = Self.game(["f y f f", "m f c e", "b c e y"], level: level)
        #expect(game.isTangled(MatchPoint(0, 0)))
        #expect(!game.canSwap(MatchPoint(0, 0), MatchPoint(1, 0)))
        #expect(!game.canSwap(MatchPoint(0, 0), MatchPoint(0, 1)))
        let first = try #require(game.swap(MatchPoint(1, 0), MatchPoint(1, 1)).first)
        #expect(first.tanglesCleared == [MatchPoint(0, 0)])
        #expect(!game.isTangled(MatchPoint(0, 0)))
    }

    @Test func meetingTheGoalsEndsTheLevelWithTheMovesLeftAddedAndItsStars() {
        var game = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f y c e"],
                             level: Self.level(goals: ["collect:fish:3"], stars: [300, 500]))
        #expect(game.stars == 0)
        game.swap(MatchPoint(2, 3), MatchPoint(2, 4))
        #expect(game.goalsMet && game.isOver)
        // 9 moves left (and the spare ones) at 60 each on top of what the move scored.
        #expect(game.score >= 30 + (9 + Tuning.Arcade.Match.spareMoves) * 60)
        #expect(game.stars == 3)
        // Nothing more can be played.
        #expect(game.swap(MatchPoint(0, 0), MatchPoint(0, 1)).isEmpty)
        // Out of moves with the goals unmet: no stars (a level of one move in all, the spare ones counted).
        var short = Self.game(["y m b c e", "m b c e y", "b c e y m", "c e f m b", "f f y c e"],
                              level: Self.level(moves: 1 - Tuning.Arcade.Match.spareMoves, goals: ["collect:fish:30"]))
        short.swap(MatchPoint(2, 3), MatchPoint(2, 4))
        #expect(short.isOver && !short.goalsMet && short.stars == 0)
    }

    @Test func thereIsAlwaysAMoveWhileTheLevelIsOn() {
        // Small boards with few kinds run out of moves often: the board shuffles.
        var shuffled = 0
        for n in 0 ..< 20 {
            var game = MatchGame(level: Self.level(["oooo", "oooo", "oooo", "oooo"], moves: 40, kinds: 6, goals: ["collect:fish:400"]),
                                 seed: Self.seed("move\(n)"))
            var seed = Self.seed("bot\(n)")
            while !game.isOver {
                let moves = game.moves()
                #expect(!moves.isEmpty)
                guard !moves.isEmpty else { break }
                let move = moves[seed.below(moves.count)]
                game.swap(move.0, move.1)
            }
            shuffled += game.shuffles
        }
        #expect(shuffled > 0)
    }

    @Test func theSameMovesWithTheSameSeedPlayTheSameGame() {
        func play() -> (Int, [MatchKind: Int]) {
            var game = MatchGame(level: Self.level(Array(repeating: "oooooooo", count: 8), moves: 15, goals: ["collect:fish:999"]),
                                 seed: Self.seed("replay"))
            var seed = Self.seed("replaybot")
            MatchBot.play(&game, seed: &seed)
            return (game.score, game.collected)
        }
        let a = play(), b = play()
        #expect(a.0 == b.0 && a.1 == b.1)
    }

    @Test func theBotWinsAnEasyLevelEveryTime() {
        let easy = Self.level(Array(repeating: "ooooooo", count: 7), moves: 20, kinds: 5, goals: ["collect:fish:15"])
        for n in 0 ..< 6 {
            var game = MatchGame(level: easy, seed: Self.seed("easy\(n)"))
            var seed = Self.seed("easybot\(n)")
            MatchBot.play(&game, seed: &seed)
            #expect(game.goalsMet)
        }
    }
}
