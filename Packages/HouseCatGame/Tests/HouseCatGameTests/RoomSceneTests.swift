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
        let frame = cat.calculateAccumulatedFrame()
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
@Test func directorWalksToAPointInTheTimeItsPaceGives() throws {
    let world = try World()
    let room = world.room()
    let director = room.addCat(rig: world.rig, at: 2, 2, pose: .sitSide)
    let target = room.grid.floor(4, 2)
    let distance = hypot(target.x - director.floorPoint.x, target.y - director.floorPoint.y)
    director.run([.rise(.side), .move(to: target, run: false, view: .side, scale: 1, lift: 0, speed: 170)])
    run(director, seconds: Tuning.Puppet.riseSeconds + Double(distance / 170) * 0.5)
    #expect(!director.isIdle)
    run(director, seconds: Double(distance / 170))
    #expect(director.isIdle)
    #expect(hypot(director.floorPoint.x - target.x, director.floorPoint.y - target.y) < 0.01)
}

@MainActor
@Test func arrivalRunsToTheCameraRubsAndSettlesWhereTheTableSent() throws {
    let world = try World()
    let room = world.room()
    let director = room.addCat(rig: world.rig, at: CGFloat(world.model.cat[0]), CGFloat(world.model.cat[1]), pose: .loafThreeQuarterFront)
    var rubs = 0, done = false
    var biggest: CGFloat = 0
    let choice = BehaviourChoice(activity: .bowlNag)
    room.playArrival(then: choice, onRub: { rubs += 1 }, onDone: { done = true })
    for _ in 0 ..< 60 * 30 where !done {
        director.update(1.0 / 60)
        biggest = max(biggest, director.cat.xScale.magnitude)
    }
    #expect(done)
    #expect(rubs == 1)
    #expect(abs(biggest - CGFloat(Tuning.Arrival.nearScale)) < 0.01)
    #expect(director.cat.pose == .sitFront)
    #expect(director.cat.xScale.magnitude == 1)
    #expect(director.floorPoint == room.spot(for: choice).point)
}
