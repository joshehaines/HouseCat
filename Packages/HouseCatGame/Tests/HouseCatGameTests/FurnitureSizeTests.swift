import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// The demo living room with its pieces on whole cells, as a save places them.
@MainActor
private func livingRoom(furnitureScale: Double = Tuning.Room.furnitureScale, door: RoomModel.Opening? = nil) throws -> RoomScene {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    var model = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
    model.items = model.items.map {
        RoomModel.Placement(id: $0.id, u: $0.u.rounded(), v: $0.v.rounded(), facing: $0.facing, up: $0.up, placementID: UUID())
    }
    model.furnitureScale = furnitureScale
    if let door {
        model.door = door
    }
    return RoomScene(size: CGSize(width: 1024, height: 768), art: art, content: content, model: model)
}

/// Josh, 19 Oct: "the couches look huge as well as the scratching post": every piece is drawn smaller than it was
/// painted, on the same whole cells.
@MainActor
@Test func furnitureIsDrawnSmallerThanPaintedOnTheSameCells() throws {
    let small = try livingRoom(), painted = try livingRoom(furnitureScale: 1)
    let k = CGFloat(Tuning.Room.furnitureScale)
    #expect(k < 1)
    for id in ["living_sofa", "living_scratch", "living_box", "living_picture"] {
        let a = try #require(small.activeRoom?.furniture[id]), b = try #require(painted.activeRoom?.furniture[id])
        #expect(abs(a.size.width - b.size.width * k) < 0.01, "\(id)")
        #expect(abs(a.size.height - b.size.height * k) < 0.01, "\(id)")
        // The same draw order: it still sorts by its whole footprint.
        #expect(a.zPosition == b.zPosition, "\(id)")
    }
}

/// A piece stands in the middle of its cells, or with its back to the wall its cells touch (the sofa against the left
/// wall stays against it), and the cat sits in the middle of the piece as it is drawn.
@MainActor
@Test func aSmallerPieceKeepsToItsWallAndTheCatSitsInItsMiddle() throws {
    let scene = try livingRoom()
    let room = try #require(scene.activeRoom)
    let k = CGFloat(Tuning.Room.furnitureScale)
    let items = Dictionary(uniqueKeysWithValues: try ContentBundle.load(from: repo.appendingPathComponent("Content")).catalogue.items.map { ($0.id, $0) })
    // The sofa faces L at u 0: back to the left wall, its 3 cells along v drawn k as long, in their middle.
    let sofa = try #require(room.model.items.first { $0.id == "living_sofa" })
    #expect(sofa.u == 0)
    let at = room.stand(try #require(items["living_sofa"]), sofa)
    #expect(at.u == 0)
    #expect(abs(at.w - k) < 0.001 && abs(at.d - 3 * k) < 0.001)
    #expect(abs(at.v - (sofa.v + 3 * (1 - k) / 2)) < 0.001)
    // The rug lies away from the walls: in the middle of its cells both ways.
    let rug = try #require(room.model.items.first { $0.id == "living_rug" })
    let lies = room.stand(try #require(items["living_rug"]), rug)
    #expect(abs(lies.u - (rug.u + 3 * (1 - k) / 2)) < 0.001 && abs(lies.v - (rug.v + 2 * (1 - k) / 2)) < 0.001)
    // On the sofa: the middle of the sofa as drawn, raised to its seat.
    let sit = scene.spot(for: BehaviourChoice(activity: .sit, item: "living_sofa"))
    let middle = scene.grid.floor(at.u + at.w / 2, at.v + at.d / 2)
    #expect(hypot(sit.point.x - middle.x, sit.point.y - middle.y) < 0.01)
    #expect(sit.lift > 0)
}

/// Josh, 19 Oct: "make the doors 3d". A door painted at the wall's angle stands upright on its wall, not warped onto
/// it: its front foot where the layout's door ends along the wall, as wide as the wall it spans; on the right wall it
/// is mirrored.
@MainActor
@Test func aDoorPaintedIn3DStandsUprightOnItsWall() throws {
    for wall in ["L", "R"] {
        let opening = RoomModel.Opening(id: "door_iso_cream", wall: wall, start: 6.6, along: 1.5, height: 3.5, up: nil)
        let scene = try livingRoom(door: opening)
        let room = try #require(scene.activeRoom)
        let door = try #require(room.childNode(withName: "door") as? SKSpriteNode)
        #expect(door.warpGeometry == nil)
        #expect(door.anchorPoint == .zero)
        let foot = room.wallPoint(wall, along: 8.1, up: 0)
        #expect(hypot(door.position.x - foot.x, door.position.y - foot.y) < 0.001)
        #expect(abs(door.size.width - 1.5 * scene.grid.cellHalfWidth) < 0.01)
        #expect(door.xScale == (wall == "R" ? -1 : 1))
        // The hallway is painted in it: nothing drawn behind.
        #expect(room.childNode(withName: "door.beyond") == nil)
    }
}
