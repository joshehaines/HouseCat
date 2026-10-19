import Foundation
@testable import HouseCatCore
import Testing

/// The Games menu's content (Content/arcade.json, match_levels.json, catapult_levels.json): words in British English
/// within their lengths, the cats in order, every level well formed, every match goal possible, and every Catapult
/// level cleared by its recorded solution from where it stands.
@Suite("Games menu content")
struct ArcadeContentTests {
    let content: ArcadeContent

    init() throws {
        content = try ArcadeContent.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
    }

    func problems(_ text: String, limit: Int) -> [String] {
        ContentValidationTests.problems(in: text, limit: limit)
    }

    @Test func theGamesHaveTheirWords() {
        for game in ArcadeGame.allCases {
            let words = content.file.game(game)
            #expect(words != nil, "\(game)")
            guard let words else { continue }
            #expect(problems(words.name, limit: 24).isEmpty, "\(words.name)")
            #expect(problems(words.tagline, limit: 60).isEmpty, "\(words.tagline): \(problems(words.tagline, limit: 60))")
            for line in words.howTo {
                #expect(problems(line, limit: 90).isEmpty, "\(line): \(problems(line, limit: 90))")
            }
        }
        for biome in Biome.allCases {
            #expect(content.file.places[biome.rawValue] != nil, "\(biome)")
        }
    }

    @Test func theCatsComeEasiestFirstWithTheirLines() throws {
        let opponents = content.file.opponents
        #expect(opponents.map(\.id) == ArcadeOpponents.ids)
        #expect(zip(opponents, opponents.dropFirst()).allSatisfy { $0.skill.depth <= $1.skill.depth && $0.skill.whim >= $1.skill.whim })
        let builder = try CatBuilder.load(from: ContentValidationTests.repo.appendingPathComponent("App/Art/cat/custom/builder.json"))
        for opponent in opponents {
            #expect(builder.preset(opponent.preset) != nil, "\(opponent.id) preset \(opponent.preset)")
            #expect((1 ... Tuning.Arcade.Row.deepest).contains(opponent.skill.depth))
            #expect((0 ... 1).contains(opponent.skill.whim))
            for line in [opponent.meet, opponent.wins, opponent.loses] {
                #expect(problems(line, limit: 70).isEmpty, "\(opponent.id): \(line) \(problems(line, limit: 70))")
            }
            #expect(problems(opponent.style, limit: 24).isEmpty)
            #expect(problems(opponent.home, limit: 24).isEmpty)
        }
        // No two cats look the same.
        #expect(Set(opponents.map(\.preset)).count == opponents.count)
    }

    @Test func everyChallengeHasItsWords() {
        for challenge in ArcadeChallenges.pool {
            let words = content.file.challenges[challenge.id]
            #expect(words != nil, "\(challenge.id)")
            if let words {
                #expect(problems(words, limit: 48).isEmpty, "\(words): \(problems(words, limit: 48))")
                #expect(words.contains("\(challenge.target)") || challenge.target == 1, "\(challenge.id) says its count")
            }
        }
        #expect(Set(content.file.challenges.keys) == Set(ArcadeChallenges.pool.map(\.id)))
    }

    // MARK: Purrfect Match

    @Test func everyMatchLevelIsWellMadeAndItsGoalsArePossible() {
        let levels = content.match.levels
        #expect(levels.count == Tuning.Arcade.matchLevels)
        #expect(levels.map(\.id) == Array(0 ..< levels.count))
        #expect(Set(levels.map(\.title)).count == levels.count)
        for level in levels {
            let name = "\(level.id) \(level.title)"
            #expect(problems(level.title, limit: 24).isEmpty, "\(name)")
            #expect(level.layout.count >= 5 && level.layout.count <= 8, "\(name) rows")
            #expect(Set(level.layout.map(\.count)).count == 1, "\(name) square")
            #expect(level.width >= 5 && level.width <= 9, "\(name) width")
            #expect(level.layout.joined().allSatisfy { ".odDpPt".contains($0) }, "\(name) marks")
            #expect((4 ... 6).contains(level.kinds), "\(name) kinds")
            #expect((10 ... 40).contains(level.moves), "\(name) moves")
            #expect(level.stars.count == 2 && level.stars[0] > 0 && level.stars[1] > level.stars[0], "\(name) stars")
            #expect(level.parsedGoals.count == level.goals.count && !level.goals.isEmpty, "\(name) goals")
            let joined = level.layout.joined()
            for goal in level.parsedGoals {
                switch goal {
                case let .collect(kind, count):
                    #expect(kind.rawValue < level.kinds, "\(name) asks for \(kind) with \(level.kinds) kinds")
                    #expect(count > 0 && count % 5 == 0, "\(name) count")
                case .dust: #expect(joined.contains { $0 == "d" || $0 == "D" }, "\(name) has dust")
                case .parcels: #expect(joined.contains { $0 == "p" || $0 == "P" }, "\(name) has parcels")
                }
            }
            // No parcel in the top row: new pieces drop in there.
            #expect(!level.layout[0].contains { $0 == "p" || $0 == "P" }, "\(name) top row")
        }
    }

    @Test(arguments: 0 ..< Tuning.Arcade.matchLevels)
    func everyMatchLevelCanBeWon(_ id: Int) throws {
        let level = try #require(content.match.levels.first { $0.id == id })
        var won = false
        for n in 0 ..< 6 where !won {
            var game = MatchGame(level: level, seed: DaySeed(household: 99, day: GameDay(index: id), purpose: "check", salt: "\(n)"))
            var bot = DaySeed(household: 98, day: GameDay(index: id), purpose: "bot", salt: "\(n)")
            MatchBot.play(&game, seed: &bot)
            won = game.goalsMet
        }
        #expect(won, "level \(id) \(level.title): the plain bot never won it")
    }

    // MARK: Catapult

    @Test func everyCatapultLevelIsWellMade() {
        let levels = content.catapult.levels
        #expect(levels.count == Tuning.Arcade.catapultLevels)
        #expect(levels.map(\.id) == Array(0 ..< levels.count))
        let per = Tuning.Arcade.Catapult.levelsPerPlace
        for (index, biome) in Biome.allCases.enumerated() {
            let place = content.catapultLevels(in: biome)
            #expect(place.map(\.id) == Array(index * per ..< (index + 1) * per), "\(biome)")
            #expect(Set(place.map(\.title)).count == per, "\(biome) titles")
        }
        for level in levels {
            let name = "\(level.id) \(level.title)"
            #expect(problems(level.title, limit: 22).isEmpty, "\(name): \(problems(level.title, limit: 22))")
            #expect(level.par >= 1 && level.pounces >= level.par && level.pounces <= 6, "\(name) pounces")
            #expect(!level.mice.isEmpty, "\(name) mice")
            #expect(!level.solution.isEmpty && level.solution.count <= level.par, "\(name) solution")
            // Everything is to the right of the cat and on the ground or something.
            #expect(level.pieces.allSatisfy { $0.x - $0.half.x > Tuning.Arcade.Catapult.launch.x + 1 }, "\(name) clear of the cat")
            #expect(level.mice.allSatisfy { $0.y > 0.05 }, "\(name) mice up off the ground")
        }
    }

    @Test(arguments: 0 ..< Tuning.Arcade.catapultLevels)
    func everyCatapultLevelStandsAndItsSolutionClearsIt(_ id: Int) throws {
        let level = try #require(content.catapult.levels.first { $0.id == id })
        // Left alone it does not fall over.
        var standing = CatapultGame(level: level)
        let beats = standing.stand(4)
        #expect(!beats.contains { if case .knocked = $0 { true } else { false } }, "\(id) \(level.title) fell over")
        // Its solution clears it within par, for three stars.
        var game = CatapultGame(level: level)
        for shot in level.solution {
            game.playOut(angle: shot.angle, power: shot.power)
        }
        #expect(game.won, "\(id) \(level.title): the solution leaves \(level.mice.count - game.knocked.count) mice")
        #expect(game.stars == 3, "\(id) \(level.title)")
    }
}
