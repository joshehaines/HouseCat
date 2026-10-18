import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

@MainActor
private struct Fixture {
    let art: ArtLibrary
    let content: ContentBundle
    let layout: RoomModel

    init() throws {
        art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
        content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        var layout = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
        // Whole cells with placement ids, as the save gives them.
        layout.items = layout.items.map {
            RoomModel.Placement(id: $0.id, u: $0.u.rounded(), v: $0.v.rounded(), facing: $0.facing, up: $0.up, placementID: UUID())
        }
        self.layout = layout
    }

    /// The London terrace with only the living room open.
    func house() throws -> HouseModel {
        let plans = try art.data("rooms/houses.json", as: HousePlans.self)
        let plan = try #require(plans.houses["london_terrace"])
        let rooms = plan.rooms.map { spot -> HouseModel.Room in
            var model = layout
            if spot.room != .living {
                model.items = []
                model.window = nil
                model.door = nil
            }
            return HouseModel.Room(
                id: spot.room,
                storey: spot.storey,
                u: spot.at[0],
                v: spot.at[1],
                outdoor: spot.outdoor ?? false,
                model: model,
                lockLabel: spot.room == .living ? nil : "Level \(spot.room.requiredLevel)"
            )
        }
        return HouseModel(
            rooms: rooms,
            active: .living,
            sky: .day,
            ground: "rooms/floors/floor_garden_brick_paving.png",
            stairs: plan.stairs
        )
    }

    func scene() throws -> RoomScene {
        try RoomScene(size: CGSize(width: 1366, height: 1024), art: art, content: content, house: house())
    }
}

@MainActor
@Test func everyHomeHasSixRoomsOnTheGrid() throws {
    let plans = try Fixture().art.data("rooms/houses.json", as: HousePlans.self)
    #expect(Set(plans.houses.keys) == Set(HouseStyle.allCases.map(\.rawValue)))
    for (name, plan) in plans.houses {
        #expect(Set(plan.rooms.map(\.room)) == Set(RoomID.allCases), "\(name)")
        #expect(plan.rooms.contains { $0.room == .living && $0.storey == 0 && $0.at == [0, 0] }, "\(name) living room at the back corner")
        let spots = plan.rooms.map { "\($0.storey):\($0.at)" }
        #expect(Set(spots).count == spots.count, "\(name) rooms do not overlap")
    }
}

@MainActor
@Test func everyRoomTypeHasAStyleWhosePreviewIsPaintedAndFits() throws {
    let fixture = try Fixture()
    let plans = try fixture.art.data("rooms/houses.json", as: HousePlans.self)
    let items = Dictionary(uniqueKeysWithValues: fixture.content.catalogue.items.map { ($0.id, $0) })
    for room in RoomID.allCases where room != .living {
        let style = try #require(plans.roomStyles[room.rawValue], "\(room)")
        var pieces: [PlacementRules.Piece] = []
        for placement in style.preview ?? [] {
            let item = try #require(items[placement.id], "\(placement.id) is in the catalogue")
            #expect(fixture.art.has(item.sprites[placement.facing] ?? ""), "\(placement.id) is in the app art")
            let piece = PlacementRules.Piece(
                item,
                x: Int(placement.u),
                y: Int(placement.v),
                facing: placement.facing == "L" ? .left : .right
            )
            #expect(PlacementRules.fits(piece, among: pieces), "\(placement.id) fits in the \(room) preview")
            pieces.append(piece)
        }
        if let window = style.window {
            #expect(fixture.art.has("rooms/windows/\(window.id).png"), "\(window.id)")
        }
    }
}

@MainActor
@Test func partitionsAreCutDownAndTheBackWallsStand() throws {
    let house = try Fixture().house()
    func walls(_ id: RoomID) throws -> (left: RoomNode.Wall, right: RoomNode.Wall) {
        try house.walls(of: #require(house.rooms.first { $0.id == id }))
    }
    #expect(try walls(.living) == (.full, .full))
    // The kitchen sits beside the living room along u: its left wall is the shared partition.
    #expect(try walls(.kitchen) == (.stub, .full))
    #expect(try walls(.garden) == (.full, .stub))
}

@MainActor
@Test func theStoreyIsBuiltAroundTheActiveRoomOnItsGroundWithClosedRoomsVeiled() throws {
    let scene = try Fixture().scene()
    // The ground floor of the terrace: living room, kitchen beside it, garden; upstairs is reached by the stairs.
    #expect(Set(scene.shownRooms) == [.living, .kitchen, .garden])
    #expect(Set(scene.rooms.keys) == Set(RoomID.allCases), "every room is built, for the cat to go to")
    let living = try #require(scene.rooms[.living]), kitchen = try #require(scene.rooms[.kitchen])
    #expect(kitchen.position == scene.grid.floor(10, 0))
    #expect(living.childNode(withName: "veil") == nil)
    #expect(kitchen.childNode(withName: "veil") != nil)
    #expect(scene.furniture["living_sofa"] != nil)
    // The view is centred on the living room, walls and floor.
    let bounds = living.grid.bounds
    let centre = scene.world.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: living)
    let inView = scene.convert(centre, from: scene.world)
    #expect(abs(inView.x - 683) < 1 && abs(inView.y - 512) < 1)
    #expect(scene.world.childNode(withName: "ground") != nil)
}

@MainActor
private func touchPoint(of id: String, in scene: RoomScene) throws -> CGPoint {
    let room = try #require(scene.activeRoom)
    let sprite = try #require(scene.furniture[id])
    return scene.convert(CGPoint(x: sprite.position.x, y: sprite.position.y + sprite.size.height * 0.3), from: room)
}

@MainActor
@Test func dragASnapsToTheGridAndIsRecorded() throws {
    let scene = try Fixture().scene()
    var changes: [RoomScene.DecorateChange] = []
    scene.onDecorate = { changes.append($0) }
    scene.setDecorating(true)
    #expect(scene.activeRoom?.childNode(withName: "decorate.grid") != nil)
    let start = try touchPoint(of: "living_box", in: scene)
    #expect(scene.beginDecorating(start))
    let before = try #require(scene.selection).piece
    // Two cells towards the back along u.
    let room = try #require(scene.activeRoom)
    let target = scene.convert(room.grid.floor(CGFloat(before.x) - 1.5, CGFloat(before.y) + 0.5), from: room)
    scene.dragDecorating(to: target)
    scene.endDecorating(at: target)
    guard case let .moved(_, x, y, _) = try #require(changes.last) else {
        Issue.record("expected a move")
        return
    }
    #expect(x != before.x || y != before.y)
    #expect(scene.activeRoom?.model.items.first { $0.id == "living_box" }?.u == Double(x))
}

@MainActor
@Test func aDropOntoAnotherPieceSpringsBack() throws {
    let scene = try Fixture().scene()
    var changes: [RoomScene.DecorateChange] = []
    scene.onDecorate = { changes.append($0) }
    scene.setDecorating(true)
    #expect(try scene.beginDecorating(touchPoint(of: "living_box", in: scene)))
    let original = try #require(scene.selection).piece
    let sofa = try #require(scene.activeRoom?.model.items.first { $0.id == "living_sofa" })
    let room = try #require(scene.activeRoom)
    let onSofa = scene.convert(room.grid.floor(CGFloat(sofa.u) + 0.5, CGFloat(sofa.v) + 1.5), from: room)
    scene.dragDecorating(to: onSofa)
    scene.endDecorating(at: onSofa)
    #expect(changes.isEmpty)
    #expect(scene.selection?.piece == original)
}

@MainActor
@Test func turnAndStoreActOnThePiecePickedUp() throws {
    let scene = try Fixture().scene()
    var changes: [RoomScene.DecorateChange] = []
    scene.onDecorate = { changes.append($0) }
    scene.setDecorating(true)
    #expect(try scene.beginDecorating(touchPoint(of: "living_box", in: scene)))
    scene.endDecorating(at: .zero)
    let id = try #require(scene.selectedPlacement)
    let facing = try #require(scene.selection).piece.facing
    scene.turnSelection()
    if case let .moved(_, _, _, turned) = try #require(changes.last) {
        #expect(turned != facing)
    } else {
        Issue.record("expected a turn")
    }
    scene.storeSelection()
    #expect(changes.last == .stored(placementID: id))
    #expect(scene.activeRoom?.model.items.contains { $0.placementID == id } == false)
    #expect(scene.selectedPlacement == nil)
}

@MainActor
@Test func upTheStairsShowsTheNextStoreyAndTheCatComesBackWithItsOwn() throws {
    let fixture = try Fixture()
    let scene = try fixture.scene()
    let rig = try fixture.art.data("cat/rig.json", as: PuppetRig.self)
    scene.addCat(rig: rig, at: 4, 4, pose: .sitSide)
    #expect(scene.storeys == [0, 1, 2])
    #expect(scene.rooms[.kitchen]?.childNode(withName: "stairs") != nil)
    scene.showStorey(1)
    #expect(Set(scene.shownRooms) == [.bedroom, .study])
    #expect(scene.director?.cat.parent === scene.rooms[.living], "the cat stays in its room, off screen")
    #expect(scene.isOnCat(.zero) == false)
    #expect(scene.rooms[.bedroom]?.childNode(withName: "veil") != nil)
    scene.setDecorating(true)
    #expect(!scene.decorating, "furniture is moved on the active room's storey only")
    scene.showStorey(0)
    #expect(scene.director?.cat.parent === scene.rooms[.living])
}

@MainActor
@Test func aSettledCatWandersToWhatTheTableChoosesNext() throws {
    let fixture = try Fixture()
    let scene = try fixture.scene()
    let director = try scene.addCat(rig: fixture.art.data("cat/rig.json", as: PuppetRig.self), at: 5, 5, pose: .sitSide)
    var asked = 0
    scene.nextActivity = { _ in
        asked += 1
        return BehaviourChoice(activity: .bowlNag)
    }
    // After the idle time the cat sets off for the bowl.
    var clock: TimeInterval = 0
    for _ in 0 ..< Int((Tuning.Puppet.idleSeconds + 1) * 20) {
        clock += 1.0 / 20
        scene.update(clock)
    }
    #expect(asked == 1)
    #expect(!director.isIdle)
    for _ in 0 ..< 20 * 20 {
        clock += 1.0 / 20
        scene.update(clock)
        if director.isIdle {
            break
        }
    }
    #expect(director.cat.pose == .sitFront)
    #expect(director.floorPoint == scene.spot(for: BehaviourChoice(activity: .bowlNag)).point)
}

@MainActor
@Test func feedingSendsTheCatToItsBowlAndPettingShowsAHeart() throws {
    let fixture = try Fixture()
    let scene = try fixture.scene()
    let director = try scene.addCat(rig: fixture.art.data("cat/rig.json", as: PuppetRig.self), at: 5, 5, pose: .sitSide)
    let room = try #require(scene.activeRoom)
    let onCat = scene.convert(CGPoint(x: director.cat.position.x, y: director.cat.position.y + 40), from: room)
    #expect(scene.isOnCat(onCat))
    #expect(!scene.isOnCat(scene.convert(room.grid.floor(9, 1), from: room)))
    let before = room.children.count
    scene.react("heart")
    #expect(room.children.count == before + 1)
    scene.send(BehaviourChoice(activity: .bowlNag))
    #expect(!director.isIdle)
}

@MainActor
@Test func aPieceFromTheInventoryLandsWhereItFitsPickedUp() throws {
    let fixture = try Fixture()
    let scene = try fixture.scene()
    scene.setDecorating(true)
    let armchair = try #require(fixture.content.catalogue.items.first { $0.id == "living_armchair" })
    let spot = try #require(PlacementRules.firstFit(PlacementRules.Piece(armchair, x: 0, y: 0, facing: .right), among: scene.pieces()))
    let id = UUID()
    scene.place(RoomModel.Placement(id: armchair.id, u: Double(spot.x), v: Double(spot.y), facing: spot.facing.rawValue, placementID: id))
    #expect(scene.activeRoom?.model.items.contains { $0.placementID == id } == true)
    #expect(scene.selectedPlacement == id)
}
