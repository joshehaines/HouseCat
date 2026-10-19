import Foundation
@testable import HouseCatCore
import Testing

@Suite("Zoomies")
struct ZoomiesTests {
    let dt = 1.0 / 60
    let z = Tuning.Arcade.Zoomies.self

    static func seed(_ salt: String) -> DaySeed {
        DaySeed(household: 5, day: GameDay(index: 20000), purpose: "zoomies", salt: salt)
    }

    /// Runs `run` to the end of its course (or a bump) with the reflex player; returns whether it got through.
    func playThrough(_ run: inout ZoomiesRun, limit: Double = .infinity) -> ZoomiesItem? {
        while !run.over, run.distance < min(run.courseEnd, limit) {
            for input in ZoomiesBot.act(on: run) {
                run.input(input)
            }
            for beat in run.step(dt) {
                if case let .bumped(item) = beat { return item }
            }
        }
        return nil
    }

    func stretch(_ items: [(ZoomiesThing, Double, Int)], length: Double = 40) -> ZoomiesStretch {
        ZoomiesStretch(name: "test", length: length, tier: 1, items: items)
    }

    @Test func everyStretchCanBeRunAtAnySpeedFromAnyLane() {
        for stretch in ZoomiesCourse.stretches {
            for speed in [z.startSpeed, (z.startSpeed + z.topSpeed) / 2, z.topSpeed] {
                for lane in 0 ..< z.lanes {
                    var run = ZoomiesRun(course: [stretch], speed: speed, lane: lane)
                    let bump = playThrough(&run)
                    #expect(bump == nil, "\(stretch.name) at \(speed) m/s from lane \(lane): bumped \(String(describing: bump))")
                }
            }
        }
    }

    @Test func longRunsAtFullSpeedNeverTrapTheCat() {
        for n in 0 ..< 12 {
            var seed = Self.seed("long\(n)")
            let course = (0 ..< 40).map { _ in ZoomiesCourse.stretches[seed.below(ZoomiesCourse.stretches.count)] }
            var run = ZoomiesRun(course: course, speed: z.topSpeed)
            let bump = playThrough(&run)
            #expect(bump == nil, "run \(n): \(String(describing: bump))")
        }
        // And real runs, laid by the game and speeding up, for three kilometres.
        for n in 0 ..< 4 {
            var run = ZoomiesRun(seed: Self.seed("real\(n)"))
            let bump = playThrough(&run, limit: 3000)
            #expect(bump == nil)
            #expect(run.distance >= 3000)
            #expect(run.biscuits > 200)
        }
    }

    @Test func aLowThingIsJumpedAndAHighOneSlidUnder() {
        var standing = ZoomiesRun(course: [stretch([(.low, 6, 1)])], speed: 10)
        var bumped = false
        while standing.distance < 32, !bumped {
            bumped = standing.step(dt).contains { if case .bumped = $0 { true } else { false } }
        }
        #expect(bumped && standing.over)

        var jumping = ZoomiesRun(course: [stretch([(.low, 6, 1)])], speed: 10)
        while jumping.distance < 32, !jumping.over {
            // Jump half a jump before the middle of the thing.
            if jumping.jumpTime == nil, 26 + 0.4 - jumping.distance <= 10 * z.jumpSeconds / 2 { jumping.input(.jump) }
            _ = jumping.step(dt)
        }
        #expect(!jumping.over)

        var ducking = ZoomiesRun(course: [stretch([(.high, 6, 1)])], speed: 10)
        while ducking.distance < 32, !ducking.over {
            if ducking.distance > 24, !ducking.isSliding { ducking.input(.slideStart) }
            _ = ducking.step(dt)
        }
        #expect(!ducking.over)
        // A jump does not get under a high thing, nor a slide over a block.
        var hopping = ZoomiesRun(course: [stretch([(.high, 6, 1)])], speed: 10)
        while hopping.distance < 32, !hopping.over {
            if hopping.distance > 24, hopping.jumpTime == nil { hopping.input(.jump) }
            _ = hopping.step(dt)
        }
        #expect(hopping.over)
    }

    @Test func aBlockShutsItsLaneAndOnlyItsLane() {
        var stay = ZoomiesRun(course: [stretch([(.block, 6, 1)])], speed: 10)
        while stay.distance < 30, !stay.over { _ = stay.step(dt) }
        #expect(stay.over)
        var move = ZoomiesRun(course: [stretch([(.block, 6, 1)])], speed: 10)
        move.input(.down)
        while move.distance < 30, !move.over { _ = move.step(dt) }
        #expect(!move.over && move.lane == 2)
        // There is no lane past the edge.
        move.input(.down)
        #expect(move.lane == 2)
    }

    @Test func aLaneChangeCountsHalfwayThrough() {
        var run = ZoomiesRun(course: [], speed: 10)
        run.input(.up)
        #expect(run.lane == 0 && run.effectiveLane == 1)
        _ = run.step(z.laneSeconds * 0.6)
        #expect(run.effectiveLane == 0)
    }

    @Test func biscuitsMiceCatnipAndTheBox() {
        var run = ZoomiesRun(course: [stretch([(.biscuit, 2, 1), (.biscuit, 4, 1), (.biscuit, 6, 0), (.mouse, 8, 1),
                                              (.box, 10, 1), (.block, 14, 1), (.catnip, 18, 1), (.biscuit, 22, 0),
                                              (.biscuit, 24, 2)])], speed: 10)
        var shieldUsed = false
        while run.distance < 50, !run.over {
            for beat in run.step(dt) {
                if case .shieldUsed = beat { shieldUsed = true }
            }
        }
        #expect(!run.over)
        #expect(shieldUsed)
        // Two in its lane, then the catnip draws in both lanes' biscuits.
        #expect(run.biscuits == 4)
        #expect(run.mice == 1)
        #expect(run.score == Int(run.distance) + 4 * z.biscuitPoints + z.mousePoints)
        #expect(run.stats["biscuits"] == 4 && run.stats["mice"] == 1 && run.stats["runs"] == 1)
    }

    @Test func aMouseIsCaughtOnTheGroundNotInTheAir() {
        // The mouse is at 26 m; a jump from 23 m is in the air from 23 to 29 at 10 m/s.
        var hopping = ZoomiesRun(course: [stretch([(.mouse, 6, 1)])], speed: 10)
        while hopping.distance < 40 {
            if hopping.distance >= 23, hopping.distance < 23.5, hopping.jumpTime == nil { hopping.input(.jump) }
            _ = hopping.step(dt)
        }
        #expect(hopping.mice == 0)
        var running = ZoomiesRun(course: [stretch([(.mouse, 6, 1)])], speed: 10)
        while running.distance < 40 { _ = running.step(dt) }
        #expect(running.mice == 1)
    }

    @Test func theRunSpeedsUpToItsTopSpeedAndMovesThroughTheHome() {
        var run = ZoomiesRun(seed: Self.seed("speed"))
        var zones: [Int] = []
        // A cat that cannot be bumped: lift every obstacle by jumping is not enough, so step the clock directly.
        for _ in 0 ..< 60 * 90 {
            for beat in run.step(dt) {
                if case let .zone(zone) = beat { zones.append(zone) }
            }
            if run.over { break }
        }
        #expect(run.speed > z.startSpeed)
        #expect(run.speed <= z.topSpeed)
        var bot = ZoomiesRun(seed: Self.seed("speed"))
        _ = playThrough(&bot, limit: 1300)
        #expect(bot.zone == 3)
        #expect(bot.speed == z.topSpeed || bot.elapsed < (z.topSpeed - z.startSpeed) / z.speedGain)
    }

    @Test func theSameSeedLaysTheSameCourse() {
        let a = ZoomiesRun(seed: Self.seed("same")), b = ZoomiesRun(seed: Self.seed("same"))
        #expect(a.items == b.items)
        let c = ZoomiesRun(seed: Self.seed("other"))
        #expect(a.items != c.items)
    }

    @Test func starsComeFromTheScore() {
        #expect(z.stars.count == 3)
        #expect(z.stars == z.stars.sorted())
        var run = ZoomiesRun(course: [stretch(ZoomiesCourse.biscuits(2, 38, lane: 1))], speed: 10)
        while run.distance < 70 { _ = run.step(dt) }
        #expect(run.stars == 0)
        #expect(run.biscuits == 19)
    }
}
