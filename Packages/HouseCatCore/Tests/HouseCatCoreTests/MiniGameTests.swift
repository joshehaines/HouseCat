import Foundation
@testable import HouseCatCore
import Testing

@Suite("Mini-games")
struct MiniGameTests {
    let dt = 1.0 / 60

    @Test func starsComeFromTheGamesThresholds() {
        #expect(MiniGameRules.stars(score: 9.9, thresholds: [10, 18, 25]) == 0)
        #expect(MiniGameRules.stars(score: 10, thresholds: [10, 18, 25]) == 1)
        #expect(MiniGameRules.stars(score: 24, thresholds: [10, 18, 25]) == 2)
        #expect(MiniGameRules.stars(score: 5, thresholds: [3, 4, 5]) == 3)
        #expect(MiniGameRules.endLine(stars: 0) == "play.lose")
        #expect(MiniGameRules.endLine(stars: 2) == "play.win")
    }

    @Test func aDotLedRoundTheRoomIsChasedAndScores() {
        var game = LaserChase(duration: 30, personality: .velcro)
        var t = 0.0
        while !game.isOver {
            t += dt
            // A slow loop round the middle of the floor.
            let dot = GamePoint(x: 6 + 2.5 * cos(t * 0.6), y: 3 + 1.5 * sin(t * 0.6))
            game.step(dt, dot: dot)
        }
        #expect(game.score > 18)
        #expect(MiniGameRules.stars(score: game.score, thresholds: [10, 18, 25]) >= 2)
    }

    @Test func aStillDotBoresTheCat() {
        var game = LaserChase(duration: 30, personality: .velcro)
        let dot = GamePoint(x: 4, y: 3)
        while !game.isOver {
            game.step(dt, dot: dot)
        }
        #expect(!game.interested)
        #expect(game.score < 3)
    }

    @Test func aDotFlickedFromCornerToCornerIsTooFast() {
        var game = LaserChase(duration: 30, personality: .loaf)
        let corners = [GamePoint(x: 0, y: 0), GamePoint(x: 12, y: 6), GamePoint(x: 0, y: 6), GamePoint(x: 12, y: 0)]
        var t = 0.0
        while !game.isOver {
            t += dt
            game.step(dt, dot: corners[Int(t / 0.4) % corners.count])
        }
        #expect(game.score < 10)
    }

    @Test func tappingAsThePawCrossesEachObjectClearsTheShelf() {
        var game = KnockItOff(duration: 20, personality: .aloof)
        let reach = Tuning.MiniGames.pawReach
        while !game.isOver {
            game.step(dt)
            if game.objects.contains(where: { $0.there && abs($0.at - game.paw) < reach / 2 }) {
                #expect(game.tap() != nil)
            }
        }
        #expect(game.knocked == 5)
        #expect(game.bestChain == 5)
        #expect(game.elapsed < 20)
    }

    @Test func aMissBreaksTheChainAndRestsThePaw() {
        var game = KnockItOff(duration: 20, personality: .gremlin)
        // Exactly between the first two objects.
        while abs(game.paw - 0.2) > 0.002 {
            game.step(0.001)
        }
        #expect(game.tap() == nil)
        #expect(game.chain == 0)
        let paw = game.paw
        game.step(0.3)
        #expect(game.paw == paw)
        #expect(game.tap() == nil) // still resting
        game.step(Tuning.MiniGames.missRestSeconds)
        #expect(game.paw != paw || game.isOver)
    }

    @Test func stringsLeadTheCatToTheSparkles() throws {
        var seed = DaySeed(household: 7, day: GameDay(index: 100), purpose: "minigame", salt: "string_chase.1")
        var game = StringChase(duration: 30, personality: .velcro, seed: &seed)
        var again = DaySeed(household: 7, day: GameDay(index: 100), purpose: "minigame", salt: "string_chase.1")
        #expect(StringChase(duration: 30, personality: .velcro, seed: &again).sparkles == game.sparkles)
        #expect(game.sparkles.count == 5)
        // One string through every sparkle, nearest first.
        var path: [GamePoint] = []
        var from = game.cat
        var left = game.sparkles
        while !left.isEmpty {
            let next = try #require(left.min { $0.distance(to: from) < $1.distance(to: from) })
            left.removeAll { $0 == next }
            path.append(next)
            from = next
        }
        game.draw(path)
        while !game.isOver {
            game.step(dt)
        }
        #expect(game.gathered == 5)
        #expect(game.elapsed < 30)
    }

    @Test func withNoStringTheCatStaysPut() {
        var seed = DaySeed(household: 7, day: GameDay(index: 100), purpose: "minigame")
        var game = StringChase(duration: 30, personality: .loaf, seed: &seed)
        let start = game.cat
        while !game.isOver {
            game.step(dt)
        }
        #expect(game.cat == start)
        #expect(game.gathered == 0)
    }

    @Test func fivePlaysADayPayAndThenStop() {
        var f = Fixture()
        f.visit(days: [0])
        let before = f.state.beans
        for i in 0 ..< 6 {
            f.add(.miniGamePlayed(game: "laser_pointer", stars: 3), day: 0, hour: 10, minute: i)
        }
        #expect(f.state.today?.plays == 5)
        #expect(MiniGameRules.playsLeft(f.state) == 0)
        #expect(f.state.beans - before >= 5 * Tuning.MiniGames.starBeans[2])
        #expect(MiniGameRules.playsLeft(f.state(through: 1)) == Tuning.MiniGames.playsPerDay)
    }

    @Test func aNapPaysOnceADayWhenItRunsItsCourse() {
        var f = Fixture()
        f.visit(days: [0])
        let start = f.at(0, 21)
        #expect(NapRules.end(of: start) == start.addingTimeInterval(20 * 60))
        #expect(!NapRules.isComplete(startedAt: start, at: start.addingTimeInterval(19 * 60)))
        #expect(NapRules.isComplete(startedAt: start, at: start.addingTimeInterval(20 * 60)))
        #expect(NapRules.pays(f.state))
        let xp = f.state.xp
        f.add(.napCompleted, day: 0, hour: 21, minute: 20)
        #expect(f.state.xp == xp + Tuning.XP.nap)
        #expect(!NapRules.pays(f.state))
        f.add(.napCompleted, day: 0, hour: 22)
        #expect(f.state.xp == xp + Tuning.XP.nap)
    }
}
