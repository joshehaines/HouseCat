import Foundation
@testable import HouseCatCore
import Testing

/// Games-menu games count for the goals as quick games do, through the real rules and content (the review of 20 Oct:
/// they ticked today's goals but never the path, the milestones or a streak's mending), and only when they paid.
@Suite("Games menu goals")
struct ArcadeGoalsTests {
    let context: RulesContext

    init() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    func level(_ game: ArcadeGame, _ index: Int, stars: Int) -> GameEvent.Kind {
        .arcadePlayed(ArcadeResult(game: game, level: index, score: 0, stars: stars, won: stars > 0, stats: ["clears": 1]))
    }

    func row(_ opponent: String?, won: Bool, stars: Int) -> GameEvent.Kind {
        .arcadePlayed(ArcadeResult(game: .row, score: won ? 1 : 0, stars: stars, opponent: opponent, won: won))
    }

    func run(stars: Int) -> GameEvent.Kind {
        .arcadePlayed(ArcadeResult(game: .zoomies, score: 500, stars: stars, won: false, stats: ["runs": 1]))
    }

    @Test func aPaidGameMeetsThePathAndTheMilestonesAndAnUnpaidOneDoesNot() throws {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        #expect(!f.state.pathDone.contains("path_play"))

        // A level's three new stars: a game played, won and three-starred; the path's Playtime step is met, and the
        // day has its play for the cat and a streak's mending, without touching the quick games' five a day.
        f.add(level(.catapult, 0, stars: 3), day: 0, hour: 9)
        var state = f.state
        #expect(state.lifetime.minigamesPlayed == 1 && state.lifetime.minigameWins == 1 && state.lifetime.threeStarGames == 1)
        #expect(state.pathDone.contains("path_play"))
        #expect(state.today?.playedAnyGame == true && state.today?.plays == 0)
        #expect(MiniGameRules.playsLeft(state) == Tuning.MiniGames.playsPerDay)

        // Played again for nothing (no new stars), or two people on one device: not counted.
        f.add(level(.catapult, 0, stars: 3), day: 0, hour: 9, minute: 5)
        f.add(row(nil, won: true, stars: 3), day: 0, hour: 9, minute: 6)
        f.add(row("garfield", won: true, stars: 3), day: 0, hour: 9, minute: 7)
        state = f.state
        #expect(state.lifetime.minigamesPlayed == 1 && state.lifetime.threeStarGames == 1)

        // A draw against a cat is a game, not a win (the board gives it a star).
        f.add(row("biscuit", won: false, stars: 1), day: 0, hour: 9, minute: 8)
        state = f.state
        #expect(state.lifetime.minigamesPlayed == 2 && state.lifetime.minigameWins == 1)

        // Four more levels at three stars: the "Sharp claws" milestone (three stars in five games).
        #expect(!state.completedAchievements.contains("play_stars_1"))
        for index in 1 ... 4 {
            f.add(level(.match, index - 1, stars: 3), day: 0, hour: 10, minute: index)
        }
        state = f.state
        #expect(state.lifetime.threeStarGames == 5)
        #expect(state.completedAchievements.contains("play_stars_1"))
    }

    @Test func aScoreGameCountsItsPaidPlaysOnly() {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        for minute in 0 ... Tuning.Arcade.paidPlaysPerDay {
            f.add(run(stars: 1), day: 0, hour: 9, minute: minute)
        }
        let state = f.state
        #expect(state.lifetime.minigamesPlayed == Tuning.Arcade.paidPlaysPerDay)
        #expect(state.lifetime.minigameWins == Tuning.Arcade.paidPlaysPerDay)
        #expect(state.today?.arcadePlays == Tuning.Arcade.paidPlaysPerDay)
        // Tomorrow brings them back.
        f.add(.arrived, day: 1, hour: 8)
        f.add(run(stars: 0), day: 1, hour: 9)
        #expect(f.state.lifetime.minigamesPlayed == Tuning.Arcade.paidPlaysPerDay + 1)
        #expect(f.state.lifetime.minigameWins == Tuning.Arcade.paidPlaysPerDay)
    }

    @Test func aGamesMenuGameMendsABrokenStreakAsAQuickGameDoes() {
        var f = Fixture(context: context)
        for day in 0 ..< 5 {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8, minute: 1)
        }
        // Two days missed: the streak breaks. Back, fed and a game from the Games menu: it can be mended.
        f.add(.arrived, day: 7, hour: 8)
        f.add(.fed(catID: f.cat), day: 7, hour: 8, minute: 1)
        let before = f.state
        guard before.streak.brokenOn != nil else {
            Issue.record("the streak did not break")
            return
        }
        #expect(StreakRepair.remaining(before) == ["play"])
        #expect(!StreakRepair.canRepair(before, on: f.day(7)))
        f.add(level(.catapult, 0, stars: 1), day: 7, hour: 9)
        #expect(StreakRepair.canRepair(f.state, on: f.day(7)))
    }
}
