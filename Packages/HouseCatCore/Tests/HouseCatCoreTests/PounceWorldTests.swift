import Foundation
@testable import HouseCatCore
import Testing

@Suite("Catapult physics")
struct PounceWorldTests {
    let dt = Tuning.Arcade.Catapult.step

    func ground(_ world: inout PounceWorld) {
        world.add(.box(Vec2(20, 0.5)), at: Vec2(0, -0.5), density: .infinity, friction: 0.8, role: "ground")
    }

    func run(_ world: inout PounceWorld, seconds: Double) {
        for _ in 0 ..< Int(seconds / dt) {
            world.step(dt)
        }
    }

    @Test func aBoxDroppedOnTheGroundComesToRestOnIt() throws {
        var world = PounceWorld()
        ground(&world)
        let box = world.add(.box(Vec2(0.25, 0.25)), at: Vec2(0, 2), density: 2, role: "box")
        run(&world, seconds: 3)
        let body = try #require(world.body(box))
        #expect(abs(body.position.y - 0.25) < 0.02)
        #expect(abs(body.rotation) < 0.01)
        #expect(world.fastest < 0.02)
    }

    @Test func aTowerOfTenStandsStill() throws {
        var world = PounceWorld()
        ground(&world)
        var ids: [Int] = []
        for level in 0 ..< 10 {
            ids.append(world.add(.box(Vec2(0.3, 0.12)), at: Vec2(0, 0.12 + 0.24 * Double(level)), density: 5, role: "book"))
        }
        run(&world, seconds: 8)
        for (level, id) in ids.enumerated() {
            let body = try #require(world.body(id))
            #expect(abs(body.position.x) < 0.02)
            #expect(abs(body.position.y - (0.12 + 0.24 * Double(level))) < 0.03)
            #expect(abs(body.rotation) < 0.02)
        }
        #expect(world.fastest < 0.05)
    }

    @Test func aPlankAcrossTwoPillarsStays() throws {
        var world = PounceWorld()
        ground(&world)
        world.add(.box(Vec2(0.2, 0.4)), at: Vec2(-0.6, 0.4), density: 3, role: "box")
        world.add(.box(Vec2(0.2, 0.4)), at: Vec2(0.6, 0.4), density: 3, role: "box")
        let plank = world.add(.box(Vec2(0.9, 0.05)), at: Vec2(0, 0.85), density: 4, role: "plank")
        run(&world, seconds: 5)
        let body = try #require(world.body(plank))
        #expect(abs(body.position.y - 0.85) < 0.03)
        #expect(abs(body.rotation) < 0.02)
    }

    @Test func aBallRollsDownASlopeAndAlongTheGround() throws {
        var world = PounceWorld()
        ground(&world)
        world.add(.box(Vec2(2, 0.1)), at: Vec2(-2, 1), rotation: -0.35, density: .infinity, role: "ledge")
        let ball = world.add(.ball(0.2), at: Vec2(-3.5, 2.0), density: 3, role: "tin")
        run(&world, seconds: 2)
        let body = try #require(world.body(ball))
        #expect(body.position.x > -1)
        #expect(body.spin < -0.5)
        #expect(body.bottom > -0.05)
    }

    @Test func aBallThrownAtATowerKnocksItOver() throws {
        var world = PounceWorld()
        ground(&world)
        var tops: [Int] = []
        for level in 0 ..< 6 {
            let id = world.add(.box(Vec2(0.2, 0.2)), at: Vec2(6, 0.2 + 0.4 * Double(level)), density: 2, role: "box")
            tops.append(id)
        }
        let cat = world.add(.ball(0.28), at: Vec2(0, 1), density: 12, friction: 0.5, role: "cat")
        world.setVelocity(cat, Vec2(9, 5))
        run(&world, seconds: 4)
        let top = try #require(world.body(tops.last!))
        #expect(top.position.y < 1.0)
    }

    @Test func theSameStartPlaysOutTheSame() {
        func play() -> [Double] {
            var world = PounceWorld()
            world.add(.box(Vec2(20, 0.5)), at: Vec2(0, -0.5), density: .infinity, role: "ground")
            for level in 0 ..< 5 {
                world.add(.box(Vec2(0.2, 0.2)), at: Vec2(5, 0.2 + 0.4 * Double(level)), density: 2, role: "box")
            }
            let cat = world.add(.ball(0.28), at: Vec2(0, 1), density: 12, role: "cat")
            world.setVelocity(cat, Vec2(8, 4))
            for _ in 0 ..< 500 { world.step(Tuning.Arcade.Catapult.step) }
            return world.bodies.flatMap { [$0.position.x, $0.position.y, $0.rotation] }
        }
        #expect(play() == play())
    }

    @Test func contactsPushFromTheFirstBodyToTheSecond() {
        let a = PounceBody(id: 0, shape: .box(Vec2(1, 1)), position: Vec2(0, 0), density: 1, role: "a")
        let b = PounceBody(id: 1, shape: .box(Vec2(1, 1)), position: Vec2(1.9, 0.3), density: 1, role: "b")
        let contacts = PounceWorld.collide(a, b)
        #expect(!contacts.isEmpty)
        #expect(contacts.allSatisfy { $0.normal.x > 0.99 && $0.separation < 0 })
        let ball = PounceBody(id: 2, shape: .ball(0.5), position: Vec2(0, 1.4), density: 1, role: "c")
        let onTop = PounceWorld.collide(a, ball)
        #expect(onTop.count == 1 && onTop[0].normal.y > 0.99)
        let flipped = PounceWorld.collide(ball, a)
        #expect(flipped.count == 1 && flipped[0].normal.y < -0.99)
        let apart = PounceBody(id: 3, shape: .box(Vec2(1, 1)), position: Vec2(2.1, 0), density: 1, role: "d")
        #expect(PounceWorld.collide(a, apart).isEmpty)
    }
}
