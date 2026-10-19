import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

/// The repo, from this file: Packages/HouseCatGame/Tests/HouseCatGameTests/RoomSceneTests.swift.
private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

@MainActor
private struct World {
    let art: ArtLibrary
    let content: ContentBundle
    let model: RoomModel
    let rig: PuppetRig

    init() throws {
        art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
        content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        model = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
        rig = try art.data("cat/rig.json", as: PuppetRig.self)
    }

    func room() -> RoomScene {
        RoomScene(size: CGSize(width: 1024, height: 768), art: art, content: content, model: model)
    }
}

@MainActor
private func run(_ director: CatDirector, seconds: Double, step: Double = 1.0 / 60) {
    for _ in 0 ..< Int(seconds / step) {
        director.update(step)
    }
}

// MARK: The grid

@Test func floorCornersSitOnTheTwoToOneGrid() {
    let grid = IsoGrid()
    #expect(grid.floor(0, 0) == .zero)
    #expect(grid.floor(10, 0) == CGPoint(x: 720, y: -360))
    #expect(grid.floor(0, 10) == CGPoint(x: -720, y: -360))
    #expect(grid.floor(10, 10) == CGPoint(x: 0, y: -720))
    #expect(grid.rightWall(10, up: 5) == CGPoint(x: 720, y: 0))
}

@Test func cellUnderAPointInvertsTheFloor() {
    let grid = IsoGrid()
    for (u, v) in [(0.0, 0.0), (3.5, 7.25), (10, 2), (6.4, 6.4)] {
        let cell = grid.cell(at: grid.floor(u, v))
        #expect(abs(cell.u - u) < 1e-9 && abs(cell.v - v) < 1e-9)
    }
}

@Test func roomBoundsCoverBothWallsAndTheFloor() {
    let bounds = IsoGrid().bounds
    #expect(bounds == CGRect(x: -720, y: -720, width: 1440, height: 1080))
}

// MARK: The puppet rig

@MainActor
@Test func rigJoinsEveryPartToAPaintedParent() throws {
    let world = try World()
    let views = try #require(world.rig.sets["short_slim"])
    #expect(Set(views.keys) == Set(CatNode.View.allCases.map(\.rawValue)))
    for (name, view) in views {
        let roots = view.parts.values.filter { $0.parent == nil }
        #expect(roots.count == 1, "\(name) has one root part")
        for (partName, part) in view.parts {
            if let parent = part.parent {
                #expect(view.parts[parent] != nil, "\(name).\(partName) joins \(parent)")
            }
            #expect(world.art.has("cat/base/short_slim/cat_short_slim_\(name)_\(partName).png"), "\(name).\(partName) is painted")
            #expect(part.pivot.count == 2 && part.at.count == 2)
        }
        #expect(view.assembled.count == 2 && view.whole.count == 2)
    }
}

@MainActor
@Test func puppetStandsOnItsFeetAtTheGivenHeight() throws {
    let world = try World()
    let cat = CatNode(art: world.art, rig: world.rig, height: 150)
    for view in CatNode.View.allCases {
        cat.show(view, facingRight: false)
        let scene = SKScene(size: CGSize(width: 10, height: 10))
        scene.addChild(cat)
        let frame = cat.bodyFrame
        cat.removeFromParent()
        #expect(abs(frame.minY) < 1, "\(view) stands on the floor")
        #expect(abs(frame.height - 150) < 150 * 0.25, "\(view) is about the cat's height, got \(frame.height)")
    }
}

@MainActor
@Test func settlingHandsOverToThePaintedPoseAndRisingHandsBack() throws {
    let world = try World()
    let cat = CatNode(art: world.art, rig: world.rig, height: 150)
    cat.settle(into: .sitFront, duration: 0)
    #expect(cat.pose == .sitFront)
    cat.rise(to: .side, facingRight: true, duration: 0)
    #expect(cat.pose == nil)
    #expect(cat.view == .side && cat.facingRight)
}

@MainActor
@Test func walkingMovesTheLegsAndStoppingRestoresThem() throws {
    let world = try World()
    let cat = CatNode(art: world.art, rig: world.rig, height: 150)
    cat.show(.side, facingRight: false)
    let leg = try #require(cat.childNode(withName: "//leg_front_near"))
    let rest = leg.zRotation
    cat.walk()
    cat.step(0.15)
    #expect(leg.zRotation != rest)
    cat.stopCycle()
    #expect(leg.zRotation == rest)
}

// MARK: The room

@MainActor
@Test func roomPlacesEveryItemOfTheLayout() throws {
    let world = try World()
    let room = world.room()
    #expect(Set(room.furniture.keys) == Set(world.model.items.map(\.id)))
    #expect(room.world.childNode(withName: "//window") != nil)
    #expect(room.world.childNode(withName: "//door") != nil)
    #expect(room.furniture["living_fireplace"]?.children.contains { $0.name == "fx.fire" } == true)
}

@MainActor
@Test func furnitureFurtherForwardDrawsLaterAndRugsDrawFirst() throws {
    let room = try World().room()
    let sofa = try #require(room.furniture["living_sofa"]), bowl = try #require(room.furniture["kitchen_bowl"])
    let rug = try #require(room.furniture["living_rug"]), picture = try #require(room.furniture["living_picture"])
    #expect(bowl.zPosition > sofa.zPosition)
    #expect(rug.zPosition < sofa.zPosition)
    #expect(picture.zPosition < rug.zPosition)
}

@MainActor
@Test func catSitsOnFurnitureThatAffordsItAndUsesTheRoomsSpotsOtherwise() throws {
    let world = try World()
    let room = world.room()
    let sit = room.spot(for: BehaviourChoice(activity: .sit))
    #expect(sit.itemID == "living_sofa")
    #expect(sit.lift > 0)
    #expect(sit.perchDepth != nil)
    let eat = room.spot(for: BehaviourChoice(activity: .bowlNag))
    #expect(eat.itemID == "kitchen_bowl")
    #expect(eat.lift == 0)
    let near = room.spot(for: BehaviourChoice(activity: .nearPlayer))
    let cell = try #require(world.model.spots["nearPlayer"])
    #expect(near.point == room.grid.floor(CGFloat(cell[0]), CGFloat(cell[1])))
    #expect(near.pose == .sitFront)
}

// MARK: The cat moving

@MainActor
@Test func directorGetsUpToSpeedWalksAndSlowsToAStopAtThePoint() throws {
    let world = try World()
    let room = world.room()
    let director = room.addCat(rig: world.rig, at: 2, 2, pose: .sitSide)
    let target = room.grid.floor(6, 2)
    let distance = hypot(target.x - director.floorPoint.x, target.y - director.floorPoint.y)
    let profile = CatDirector.Profile(distance: distance, top: CatDirector.Pace.walk.speed, start: 0, end: 0)
    // Longer than at a steady walk: it starts and stops gently.
    #expect(profile.duration > Double(distance / CatDirector.Pace.walk.speed))
    #expect(profile.at(0).1 == 0)
    #expect(abs(profile.at(profile.duration).0 - distance) < 0.5 && abs(profile.at(profile.duration).1) < 0.5)
    #expect(abs(profile.at(profile.duration / 2).1 - CatDirector.Pace.walk.speed) < 0.5)
    director.run([.rise(.side), .move(to: target, pace: .walk)])
    run(director, seconds: Tuning.Puppet.riseSeconds + 0.1)
    // Just off: still slow, the legs taking short steps.
    #expect(director.cat.moveSpeed > 0 && director.cat.moveSpeed < CatDirector.Pace.walk.speed * 0.6)
    run(director, seconds: profile.duration * 0.5)
    #expect(!director.isIdle)
    run(director, seconds: profile.duration)
    #expect(director.isIdle)
    #expect(hypot(director.floorPoint.x - target.x, director.floorPoint.y - target.y) < 0.01)
    #expect(director.cat.moveSpeed == 0)
}

@MainActor
@Test func aCatTurnsThroughThreeQuartersToGoTheOtherWayAndJumpsInAnArc() throws {
    let world = try World()
    let room = world.room()
    let director = room.addCat(rig: world.rig, at: 5, 5, pose: .sitSide)
    director.run([.rise(.side), .move(to: room.grid.floor(7, 3), pace: .walk)])
    run(director, seconds: 3)
    #expect(director.isIdle && director.cat.facingRight)
    var views: [CatNode.View] = []
    director.run([.move(to: room.grid.floor(3, 7), pace: .walk)])
    for _ in 0 ..< 60 {
        director.update(1.0 / 60)
        views.append(director.cat.view)
    }
    #expect(views.contains(.tqfront), "it turned through three-quarters")
    run(director, seconds: 4)
    #expect(!director.cat.facingRight)
    // A jump up: it rises above both ends on the way, and lands at the height.
    let start = director.floorPoint
    var highest: CGFloat = 0
    director.run([.hop(to: start, lift: 40)])
    for _ in 0 ..< 60 {
        director.update(1.0 / 60)
        highest = max(highest, director.lift)
    }
    #expect(highest > 40 + director.cat.height * 0.2)
    #expect(director.isIdle && director.lift == 40)
}

@MainActor
@Test func arrivalTrotsToYouRubsAndSettlesWhereTheTableSentAtItsOwnSize() throws {
    let world = try World()
    let room = world.room()
    let director = room.addCat(rig: world.rig, at: CGFloat(world.model.cat[0]), CGFloat(world.model.cat[1]), pose: .loafThreeQuarterFront)
    var rubs = 0, done = false
    var biggest: CGFloat = 0, leaned = false
    let choice = BehaviourChoice(activity: .bowlNag)
    room.playArrival(then: choice, onRub: { rubs += 1 }, onDone: { done = true })
    for _ in 0 ..< 60 * 40 where !done {
        director.update(1.0 / 60)
        biggest = max(biggest, director.cat.xScale.magnitude)
        leaned = leaned || room.isCloseUp
    }
    #expect(done)
    #expect(rubs == 1)
    // The cat stays its size; the camera leans in instead.
    #expect(biggest == 1)
    #expect(leaned)
    #expect(director.cat.pose == .sitFront)
    #expect(director.floorPoint == room.spot(for: choice).point)
}

// MARK: Coming home

/// Each greeting plays out and settles: the ones that come to you rub (the gift comes with them), the others
/// look up, or lift a sleepy head, or turn their back, and stay or go where the table sent them.
@MainActor
@Test(arguments: GreetingStyle.allCases)
func eachGreetingComesToYouOrNotAndSettles(style: GreetingStyle) throws {
    let world = try World()
    let room = world.room()
    let director = room.addCat(rig: world.rig, at: 5, 5, pose: .sitSide)
    let start: Activity = switch style {
    case .dozes: .sleep
    case .ambush: .hide
    default: .sit
    }
    room.placeCat(for: BehaviourChoice(activity: start))
    let startPose = director.cat.pose
    let then = BehaviourChoice(activity: style == .ignores ? .sulk : .perch)
    var rubs = 0, done = false
    room.playArrival(style, then: then, onRub: { rubs += 1 }, onDone: { done = true })
    for _ in 0 ..< 60 * 40 where !done {
        director.update(1.0 / 60)
    }
    director.update(1.0 / 60)
    #expect(done)
    #expect(rubs == (style.comesToYou ? 1 : 0))
    #expect(director.isIdle)
    switch style {
    case .runs, .walks, .ambush, .ignores:
        // Off to what the table chose.
        #expect(director.cat.pose == room.spot(for: then).pose)
        #expect(director.floorPoint == room.spot(for: then).point)
    case .glances, .dozes:
        // Not hungry: it stays where it was, as it was.
        #expect(director.cat.pose == startPose)
    }
}

// MARK: The camera

@MainActor
@Test func theCameraStartsCloseLeansInOnTheCatEasesBackAndShowsTheWholeRoomToDecorate() throws {
    let world = try World()
    let room = world.room()
    _ = room.addCat(rig: world.rig, at: 5, 5, pose: .sitSide)
    var clock = 0.0
    func tick(_ seconds: Double) {
        for _ in 0 ..< Int(seconds * 30) {
            clock += 1.0 / 30
            room.update(clock)
        }
    }
    tick(2)
    let home = room.world.xScale
    room.lookCloser(for: 2)
    tick(1.8)
    #expect(room.world.xScale > home * 1.3, "leaning in on the cat")
    tick(4)
    #expect(abs(room.world.xScale - home) < home * 0.03, "back where it was")
    room.setDecorating(true)
    tick(4)
    #expect(room.world.xScale < home * 0.9, "the whole room to decorate")
    room.setDecorating(false)
    room.zoom = 10
    #expect(room.zoom == CGFloat(Tuning.Camera.maxZoom))
    room.zoom = 0.01
    #expect(room.zoom == CGFloat(Tuning.Camera.minZoom))
}
