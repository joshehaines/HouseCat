import Foundation
@testable import HouseCatCore
import Testing

@Suite("Games menu rewards")
struct ArcadeRulesTests {
    let day = GameDay(year: 2026, month: 11, day: 2)
    let seed: UInt64 = 0x5EED

    func run(_ stars: Int, score: Int = 100, stats: [String: Int] = [:]) -> ArcadeResult {
        ArcadeResult(game: .zoomies, score: score, stars: stars, won: stars > 0, stats: stats)
    }

    @Test func aScoreGamePaysItsStarsForTheFirstThreePlaysADay() {
        var state = ArcadeState()
        let first = state.record(run(1), on: day, seed: seed)
        #expect(first.beans == 2 && first.xp == 5 && first.paidPlay == 1)
        let second = state.record(run(3), on: day, seed: seed)
        #expect(second.beans == 6 && second.paidPlay == 2)
        let third = state.record(run(0), on: day, seed: seed)
        #expect(third.beans == 0 && third.xp == 5 && third.paidPlay == 3)
        #expect(state.paidPlaysLeft(.zoomies, on: day) == 0)
        let fourth = state.record(run(3), on: day, seed: seed)
        #expect(fourth.beans == 0 && fourth.xp == 0 && fourth.paidPlay == nil)
        // Each game has its own three, and a new day brings them back.
        #expect(state.paidPlaysLeft(.row, on: day) == 3)
        #expect(state.paidPlaysLeft(.zoomies, on: day.advanced(by: 1)) == 3)
        let tomorrow = state.record(run(2), on: day.advanced(by: 1), seed: seed)
        #expect(tomorrow.beans == 4 && tomorrow.paidPlay == 1)
    }

    @Test func theBestScoreIsKeptAndANewOneIsNoticed() {
        var state = ArcadeState()
        #expect(state.record(run(1, score: 500), on: day, seed: seed).newBest)
        #expect(!state.record(run(1, score: 300), on: day, seed: seed).newBest)
        #expect(state.record(run(1, score: 501), on: day.advanced(by: 3), seed: seed).newBest)
        #expect(state.best["zoomies"] == 501)
    }

    @Test func aLevelsStarsPayOnceEachAndALockedLevelPaysNothing() {
        var state = ArcadeState()
        func level(_ index: Int, _ stars: Int) -> ArcadeResult {
            ArcadeResult(game: .catapult, level: index, score: 0, stars: stars, won: stars > 0)
        }
        // Level 1 is shut until level 0 has a star.
        #expect(state.record(level(1, 3), on: day, seed: seed).beans == 0)
        #expect(!state.isOpen(.catapult, level: 1))
        let clear = state.record(level(0, 1), on: day, seed: seed)
        #expect(clear.beans == 5 && clear.newStars == 1 && clear.firstClear && clear.xp == 5)
        #expect(state.isOpen(.catapult, level: 1))
        let better = state.record(level(0, 3), on: day, seed: seed)
        #expect(better.beans == 10 && better.newStars == 2 && !better.firstClear && better.xp == 0)
        let again = state.record(level(0, 3), on: day, seed: seed)
        #expect(again.beans == 0 && again.newStars == 0)
        let worse = state.record(level(0, 1), on: day, seed: seed)
        #expect(worse.beans == 0 && state.stars(.catapult, level: 0) == 3)
        // Past the last level, or a level game with no level: nothing.
        #expect(state.record(level(Tuning.Arcade.catapultLevels, 3), on: day, seed: seed).beans == 0)
        #expect(state.record(ArcadeResult(game: .match, score: 0, stars: 3, won: true), on: day, seed: seed).beans == 0)
        #expect(state.totalStars(.catapult) == 3)
        #expect(state.nextLevel(.catapult) == 1)
        // Level games have no daily limit: the stars are the limit.
        #expect(state.paidPlaysLeft(.catapult, on: day) == 0)
    }

    @Test func beatingEachCatTheFirstTimePaysOnce() {
        var state = ArcadeState()
        func game(_ opponent: String?, won: Bool) -> ArcadeResult {
            ArcadeResult(game: .row, score: won ? 1 : 0, stars: won ? 3 : 0, opponent: opponent, won: won)
        }
        #expect(state.record(game("biscuit", won: false), on: day, seed: seed).beans == 0)
        let win = state.record(game("biscuit", won: true), on: day, seed: seed)
        #expect(win.firstWin && win.beans == 6 + 25)
        let again = state.record(game("biscuit", won: true), on: day, seed: seed)
        #expect(!again.firstWin && again.beans == 6)
        // A fourth game today pays nothing, a first win still does.
        let fourth = state.record(game("clover", won: true), on: day, seed: seed)
        #expect(fourth.firstWin && fourth.beans == 25)
        // Two people on one device, or a cat the game does not have: no first-win Beans.
        #expect(!state.record(game(nil, won: true), on: day.advanced(by: 1), seed: seed).firstWin)
        #expect(!state.record(game("garfield", won: true), on: day.advanced(by: 1), seed: seed).firstWin)
        #expect(state.beaten == ["biscuit", "clover"])
    }

    @Test func todaysPuzzlePaysOnceAndOnlyOnItsDay() {
        var state = ArcadeState()
        let number = ArcadePuzzles.number(on: day)
        #expect(ArcadePuzzles.number(on: Tuning.Arcade.Puzzle.firstDay) == 1)
        #expect(number == 15)
        let yesterdays = state.record(PuzzleSolve(number: number - 1, seconds: 90), on: day)
        #expect(yesterdays.beans == 0)
        let solved = state.record(PuzzleSolve(number: number, seconds: 90), on: day)
        #expect(solved.beans == 25 && solved.xp == 15 && solved.puzzleStreak == 1)
        #expect(state.record(PuzzleSolve(number: number, seconds: 60), on: day).beans == 0)
        #expect(state.solvedToday(on: day))
        #expect(!state.solvedToday(on: day.advanced(by: 1)))
    }

    @Test func thePuzzleStreakPaysOnItsThirdAndSeventhDayAndAMissedDayEndsIt() {
        var state = ArcadeState()
        var beans: [Int] = []
        for offset in 0 ..< 10 {
            let d = day.advanced(by: offset)
            beans.append(state.record(PuzzleSolve(number: ArcadePuzzles.number(on: d), seconds: 100), on: d).beans)
        }
        #expect(beans == [25, 25, 40, 25, 25, 25, 75, 25, 25, 40])
        #expect(state.puzzleStreak(on: day.advanced(by: 10)) == 10)
        // A day missed: the streak has gone, and starts again at one.
        #expect(state.puzzleStreak(on: day.advanced(by: 11)) == 0)
        let back = day.advanced(by: 11)
        let solve = state.record(PuzzleSolve(number: ArcadePuzzles.number(on: back), seconds: 100), on: back)
        #expect(solve.puzzleStreak == 1 && solve.beans == 25)
        #expect(state.longestPuzzleStreak == 10)
    }

    @Test func threeChallengesADayFromThreeGamesTheSameOnEveryDevice() {
        for offset in 0 ..< 60 {
            let d = day.advanced(by: offset)
            let challenges = ArcadeChallenges.today(on: d, seed: seed)
            #expect(challenges.count == 3)
            #expect(Set(challenges.map(\.game)).count == 3)
            #expect(challenges == ArcadeChallenges.today(on: d, seed: seed))
        }
        // Different days and households get different ones.
        let days = Set((0 ..< 30).map { ArcadeChallenges.today(on: day.advanced(by: $0), seed: seed).map(\.id).joined() })
        #expect(days.count > 20)
        #expect(ArcadeChallenges.today(on: day, seed: 1) != ArcadeChallenges.today(on: day, seed: 2)
            || ArcadeChallenges.today(on: day.advanced(by: 1), seed: 1) != ArcadeChallenges.today(on: day.advanced(by: 1), seed: 2))
        // Every challenge id is unique.
        #expect(Set(ArcadeChallenges.pool.map(\.id)).count == ArcadeChallenges.pool.count)
    }

    @Test func aChallengeIsPaidOnceWhenItsCountIsReached() throws {
        // Find a day whose challenges include a Zoomies one, then meet it.
        var found: (GameDay, ArcadeChallenge)?
        for offset in 0 ..< 60 {
            let d = day.advanced(by: offset)
            if let zoomies = ArcadeChallenges.today(on: d, seed: seed).first(where: { $0.game == .zoomies }) {
                found = (d, zoomies)
                break
            }
        }
        let (d, challenge) = try #require(found)
        var state = ArcadeState()
        let short = max(0, challenge.target - 1)
        let first = state.record(run(1, stats: [challenge.stat: challenge.mode == .best ? short : 1]), on: d, seed: seed)
        if challenge.target > 1 {
            #expect(first.challenges.isEmpty)
            #expect(state.progress(challenge, on: d) == (challenge.mode == .best ? short : 1))
        }
        var paid = first.challenges
        for _ in 0 ..< challenge.target {
            paid += state.record(run(1, stats: [challenge.stat: challenge.target]), on: d, seed: seed).challenges
        }
        #expect(paid == [challenge.id])
        // Tomorrow's count starts again.
        #expect(state.progress(challenge, on: d.advanced(by: 1)) == 0)
    }

    @Test func aBestOfOnePlayChallengeIsNotMetByAddingPlaysUp() {
        let challenge = ArcadeChallenge(id: "test", game: .zoomies, stat: "biscuits", mode: .best, target: 40)
        var state = ArcadeState()
        _ = state.record(run(1, stats: ["biscuits": 30]), on: day, seed: seed)
        _ = state.record(run(1, stats: ["biscuits": 30]), on: day, seed: seed)
        #expect(state.progress(challenge, on: day) == 30)
        let total = ArcadeChallenge(id: "test2", game: .zoomies, stat: "biscuits", mode: .total, target: 40)
        #expect(state.progress(total, on: day) == 60)
    }
}
