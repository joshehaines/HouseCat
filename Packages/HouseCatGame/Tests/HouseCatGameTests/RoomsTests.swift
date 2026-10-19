import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// A home with every room open and furnished: the living room's demo layout, each other room the pieces its
/// closed silhouette shows (assets/rooms/houses.json roomStyles).
@MainActor
private struct FullHouse {
    let art: ArtLibrary
    let content: ContentBundle
    let house: HouseModel

    init(home: String = "london_terrace") throws {
        art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
        content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        let layout = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
        let plans = try art.data("rooms/houses.json", as: HousePlans.self)
        let plan = try #require(plans.houses[home])
        let rooms = plan.rooms.map { spot -> HouseModel.Room in
            var model = layout
            let pieces = spot.room == .living ? layout.items : plans.roomStyles[spot.room.rawValue]?.preview ?? []
            model.items = pieces.map {
                RoomModel.Placement(id: $0.id, u: $0.u.rounded(), v: $0.v.rounded(), facing: $0.facing, up: $0.up, placementID: UUID())
            }
            if spot.room != .living {
                model.window = plans.roomStyles[spot.room.rawValue]?.window
                model.door = nil
            }
            return HouseModel.Room(
                id: spot.room, storey: spot.storey, u: spot.at[0], v: spot.at[1],
                outdoor: spot.outdoor ?? false, model: model, lockLabel: nil
            )
        }
        house = HouseModel(rooms: rooms, active: .living, sky: .day, ground: nil, stairs: plan.stairs)
    }

    func scene() -> RoomScene {
        RoomScene(size: CGSize(width: 1366, height: 1024), art: art, content: content, house: house)
    }

    /// Something to do in a room, on a piece of its furniture.
    func activity(in room: RoomID) -> (Activity, String)? {
        let items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        let usable: [Affordance: Activity] = [
            .sit: .sit,
            .sleep: .sleep,
            .perch: .perch,
            .hide: .hide,
            .watch: .windowWatch,
            .eat: .bowlNag,
        ]
        for placement in house.room(room)?.model.items ?? [] {
            for affordance in items[placement.id]?.affordances ?? [] {
                if let activity = usable[affordance] {
                    return (activity, placement.id)
                }
            }
        }
        return nil
    }
}

@MainActor
private func settle(_ director: CatDirector, within seconds: Double = 120) {
    var t = 0.0
    while !director.isIdle, t < seconds {
        director.update(1.0 / 30)
        t += 1.0 / 30
    }
}

/// Step 3's exit test: the cat uses furniture in all six rooms, walking through the doorways on a storey and
/// up and down the stairs between them.
@MainActor
@Test func theCatUsesFurnitureInAllSixRooms() throws {
    let home = try FullHouse()
    let scene = home.scene()
    let rig = try home.art.data("cat/rig.json", as: PuppetRig.self)
    let director = scene.addCat(rig: rig, at: 5, 5, pose: .sitSide)
    var used: Set<RoomID> = []
    // Round the house and back to the start, so every hop is walked: across a storey, up and down.
    for room in [RoomID.kitchen, .garden, .living, .bedroom, .study, .attic, .living] {
        let (activity, itemID) = try #require(home.activity(in: room), "\(room) has furniture to use")
        let choice = BehaviourChoice(activity: activity, room: room)
        scene.send(choice)
        // Where it was sent: the piece it went for this time (the next along, coming back to a room).
        let spot = scene.spot(for: choice)
        #expect(spot.itemID != nil, "\(room): the spot is on a piece of furniture")
        settle(director)
        #expect(director.isIdle, "\(room): the cat got there")
        #expect(scene.catRoom == room)
        #expect(director.cat.parent === scene.rooms[room], "\(room): the cat is in the room's node")
        #expect(hypot(director.floorPoint.x - spot.point.x, director.floorPoint.y - spot.point.y) < 1)
        #expect(director.cat.pose == spot.pose, "the piece's own pose")
        #expect(director.cat.alpha == 1)
        if spot.itemID != nil {
            used.insert(room)
        }
        _ = itemID
    }
    #expect(used == Set(RoomID.allCases))
}

@MainActor
@Test func roomsSideBySideJoinThroughDoorwaysInTheirPartitions() throws {
    let home = try FullHouse()
    // The terrace: living [0,0], kitchen [10,0] and garden [0,10] downstairs; bedroom [0,0] and study [10,0] up.
    let links = home.house.links(from: .living).map(\.to)
    #expect(Set(links) == [.kitchen, .garden])
    #expect(home.house.links(from: .bedroom).map(\.to) == [.study])
    #expect(home.house.links(from: .attic).isEmpty)
    #expect(home.house.route(from: .kitchen, to: .garden)?.map(\.to) == [.living, .garden])
    #expect(home.house.route(from: .living, to: .bedroom) == nil, "another storey: by the stairs")
    // The kitchen's left wall is the partition with the living room, cut by a doorway.
    let kitchen = try #require(home.house.room(.kitchen))
    #expect(home.house.doorways(of: kitchen) == ["L": CGFloat(Tuning.House.doorwayAlong)])
    // A closed room is never walked through.
    var closed = home.house
    closed.rooms = closed.rooms.map { room in
        var room = room
        if room.id == .living {
            room.lockLabel = "Level 1"
        }
        return room
    }
    #expect(closed.route(from: .kitchen, to: .garden) == nil)
}

@MainActor
@Test func goingToARoomShowsItsStoreyAndTheViewFollowsTheCatLater() throws {
    let home = try FullHouse()
    let scene = home.scene()
    let rig = try home.art.data("cat/rig.json", as: PuppetRig.self)
    let director = scene.addCat(rig: rig, at: 5, 5, pose: .sitSide)
    scene.show(room: .study)
    #expect(scene.house.active == .study)
    #expect(scene.storey == 1)
    #expect(Set(scene.shownRooms) == [.bedroom, .study])
    // You picked the study a moment ago: the view stays there while the cat walks to the kitchen.
    var followed: [RoomID] = []
    scene.onActiveRoomChanged = { followed.append($0) }
    scene.send(BehaviourChoice(activity: .bowlNag, room: .kitchen))
    settle(director)
    #expect(scene.catRoom == .kitchen)
    #expect(scene.house.active == .study)
    #expect(followed.isEmpty)
    // Back to the living room, and long after: the view goes with the cat.
    scene.show(room: .living)
    scene.roomChosenAt = -1000
    scene.send(BehaviourChoice(activity: .sit, room: .garden))
    settle(director)
    #expect(scene.house.active == .garden)
    #expect(followed == [.garden])
}

/// Coming home, the cat is where its day put it, in whichever room: the view starts on that room, the cat up on
/// its furniture in the pose for it.
@MainActor
@Test func youFindTheCatWhereverItWasAndTheViewStartsThere() throws {
    let home = try FullHouse()
    let scene = home.scene()
    let rig = try home.art.data("cat/rig.json", as: PuppetRig.self)
    let director = scene.addCat(rig: rig, at: 5, 5, pose: .sitSide)
    let (activity, itemID) = try #require(home.activity(in: .bedroom))
    let choice = BehaviourChoice(activity: activity, room: .bedroom)
    scene.placeCat(for: choice)
    #expect(scene.catRoom == .bedroom)
    #expect(scene.house.active == .bedroom)
    #expect(scene.storey == home.house.room(.bedroom)?.storey)
    #expect(director.cat.parent === scene.rooms[.bedroom])
    let spot = scene.spot(for: choice)
    #expect(spot.itemID == itemID)
    #expect(director.floorPoint == spot.point && director.lift == spot.lift)
    #expect(director.cat.pose != nil)
    #expect(scene.catActivity == activity)
}

/// A wander goes to a few spots and sits at the last, in the room it was sent to.
@MainActor
@Test func aWanderStopsAtAFewSpotsAndSitsAtTheLast() throws {
    let home = try FullHouse()
    let scene = home.scene()
    let rig = try home.art.data("cat/rig.json", as: PuppetRig.self)
    let director = scene.addCat(rig: rig, at: 5, 5, pose: .sitSide)
    scene.send(BehaviourChoice(activity: .explore, room: .kitchen))
    var moves = 0
    var t = 0.0
    var last: CatDirector.Step?
    while !director.isIdle, t < 120 {
        director.update(1.0 / 30)
        t += 1.0 / 30
        if case .move = director.currentStep, !{ if case .move = last { true } else { false } }() {
            moves += 1
        }
        last = director.currentStep
    }
    #expect(director.isIdle)
    #expect(scene.catRoom == .kitchen)
    #expect(moves >= 2)
    #expect([.sitSide, .sitThreeQuarterFront, .loafSide].contains(director.cat.pose))
}
