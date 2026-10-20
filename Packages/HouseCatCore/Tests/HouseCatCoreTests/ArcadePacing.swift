import Foundation
@testable import HouseCatCore

/// What a player does at the Games menu each day, for the pacing simulations (PacingTests, PathPacingTests,
/// PassPacingTests; the goals session asked, 20 Oct, as the games pay outside the quick games' five a day). A light
/// player plays nothing; a regular one solves Pat's puzzle; a keen one solves the puzzle and takes every paid play of
/// the score games (three Zoomies runs, the last the best; three games of Cats in a Row, beating a new cat every other
/// day until all eight are beaten, then one win a day against Pat) and clears two new levels each of Catapult and
/// Purrfect Match while any are left, one at three stars and one at two. The results carry the stats the daily
/// challenges count, so the challenges pay as they would for that player.
enum ArcadeHabit {
    case none, puzzle, keen

    init(player: String) {
        self = player == "keen" ? .keen : player == "regular" ? .puzzle : .none
    }
}

extension Fixture {
    /// One day of `habit` at 17:00, from the Games menu as it stood that morning (`arcade`).
    mutating func playArcade(_ habit: ArcadeHabit, day: Int, arcade: ArcadeState) {
        guard habit != .none else { return }
        var minute = 0
        func play(_ kind: GameEvent.Kind) {
            add(kind, day: day, hour: 17, minute: minute)
            minute += 1
        }
        let today = clock.day(of: at(day, 17))
        play(.puzzleSolved(PuzzleSolve(number: ArcadePuzzles.number(on: today), seconds: 300)))
        guard habit == .keen else { return }

        for (stars, biscuits, mice, distance) in [(2, 45, 1, 700), (2, 60, 2, 900), (3, 85, 3, 1600)] {
            play(.arcadePlayed(ArcadeResult(
                game: .zoomies, score: distance + biscuits * Tuning.Arcade.Zoomies.biscuitPoints + mice * Tuning.Arcade.Zoomies.mousePoints,
                stars: stars, won: false, stats: ["biscuits": biscuits, "mice": mice, "distance": distance, "runs": 1]
            )))
        }

        let cats = ArcadeOpponents.ids
        let opponent = cats[min(arcade.beaten.count, cats.count - 1)]
        let winsToday = arcade.beaten.count < cats.count ? day % 2 : 1
        for game in 0 ..< 3 {
            let won = game == 2 && winsToday == 1
            play(.arcadePlayed(ArcadeResult(game: .row, score: won ? 1 : 0, stars: won ? 3 : 0, opponent: opponent, won: won,
                                            stats: ["games": 1, "wins": won ? 1 : 0])))
        }

        for game in [ArcadeGame.catapult, .match] {
            var level = arcade.nextLevel(game)
            guard arcade.stars(game, level: level) == 0 else { continue }
            for stars in [3, 2] where level < game.levelCount {
                var stats = ["clears": 1, "threeStars": stars == 3 ? 1 : 0]
                if game == .catapult {
                    stats["mice"] = 3
                } else {
                    stats["dust"] = 15
                    stats["boxes"] = 1
                    stats["lasers"] = stars == 3 ? 1 : 0
                }
                play(.arcadePlayed(ArcadeResult(game: game, level: level, score: 0, stars: stars, won: true, stats: stats)))
                level += 1
            }
        }
    }
}
