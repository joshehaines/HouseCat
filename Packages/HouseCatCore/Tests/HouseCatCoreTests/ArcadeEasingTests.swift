import Foundation
@testable import HouseCatCore
import Testing

/// The games a notch easier (Josh, 20 Oct, after playing them on his iPad: "Lets make the levels slightly easier on
/// the games"). The quick games' lower stars are checked by `MiniGameTests.starsRewardPlayingWell` (a steady player
/// still gets three, a careless one one or two), Cats in a Row's cats by `ArcadeContentTests`, Pawcross's smaller
/// grids by `PawcrossTests`.
@Suite("The games, a little easier")
struct ArcadeEasingTests {
    let content: ArcadeContent

    init() throws {
        content = try ArcadeContent.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
    }

    /// Every Catapult level gives a pounce more than its own; the stars still count from its par, so the spare is
    /// room to miss, never a free star.
    @Test func catapultGivesASparePounceAndStarsStillCountFromPar() throws {
        #expect(Tuning.Arcade.Catapult.sparePounces == 1)
        // A level a gentle pounce straight off the cushion does not reach.
        let level = try #require(content.catapult.levels.first { level in
            var game = CatapultGame(level: level)
            game.playOut(angle: Tuning.Arcade.Catapult.lowestAngle, power: 0)
            return game.knocked.isEmpty
        })
        var game = CatapultGame(level: level)
        #expect(game.pouncesLeft == level.pounces + 1)
        for _ in 0 ..< level.pounces {
            game.playOut(angle: Tuning.Arcade.Catapult.lowestAngle, power: 0)
        }
        #expect(game.knocked.isEmpty)
        #expect(!game.over, "the level's own pounces used, the spare is still there")
        #expect(game.pouncesLeft == 1)
        game.playOut(angle: Tuning.Arcade.Catapult.lowestAngle, power: 0)
        #expect(game.over && !game.won && game.stars == 0)
        // Its recorded solution, played after a miss, wins one pounce over par: two stars, not three.
        var late = CatapultGame(level: level)
        late.playOut(angle: Tuning.Arcade.Catapult.lowestAngle, power: 0)
        for shot in level.solution {
            late.playOut(angle: shot.angle, power: shot.power)
        }
        if late.won, late.used == level.par + 1 {
            #expect(late.stars == 2)
        }
    }

    /// Every Purrfect Match level gives two moves more than its own.
    @Test func matchGivesTwoSpareMoves() throws {
        #expect(Tuning.Arcade.Match.spareMoves == 2)
        for level in content.match.levels {
            let game = MatchGame(level: level, seed: DaySeed(household: 1, day: GameDay(index: level.id), purpose: "easing"))
            #expect(game.movesLeft == level.moves + 2, "\(level.title)")
        }
    }

    /// Zoomies: the cat gathers speed more slowly, the harder stretches come later, and the stars are lower than on
    /// 19 Oct (0.1 m/s a second; 300 and 900 metres; 500, 1,500 and 3,000).
    @Test func zoomiesIsGentler() {
        let z = Tuning.Arcade.Zoomies.self
        #expect(z.speedGain < 0.1)
        #expect(z.tierTwoFrom > 300 && z.tierThreeFrom > 900)
        #expect(zip(z.stars, [500, 1500, 3000]).allSatisfy { $0 < $1 })
        // Up to `tierTwoFrom` only the one-thing-at-a-time stretches are laid.
        var seed = DaySeed(household: 9, day: GameDay(index: 20000), purpose: "zoomies")
        for metres in stride(from: 0.0, to: z.tierTwoFrom, by: 25) {
            #expect(ZoomiesCourse.pick(at: metres, seed: &seed).tier == 1, "\(metres) m")
        }
    }

    /// Cats in a Row: every cat plays on a whim a little more often, and Pat looks one move less far ahead.
    @Test func theCatsInARowAreKinder() {
        let cats = content.file.opponents
        #expect(cats.allSatisfy { $0.skill.whim >= 0.05 }, "every cat, Pat too, plays on a whim now and then")
        #expect(cats.last?.skill.depth == 8)
    }
}
