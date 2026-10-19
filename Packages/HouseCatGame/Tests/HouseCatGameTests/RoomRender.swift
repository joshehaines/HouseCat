import HouseCatCore
@testable import HouseCatGame
import Metal
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Stills of the terrace's living room for judging sizes and the door by eye, without a simulator: the demo layout
/// (or only the bowl and the box, as a new home starts) with the cat on the rug, close on the cat as a visit starts
/// and the whole room as decorating shows it.
/// HOUSECAT_RENDER_ROOM=<folder> [HOUSECAT_RENDER_FURNITURE=0.8,1] [HOUSECAT_RENDER_ITEMS=empty[,<id>…]] [HOUSECAT_RENDER_CAT=u,v]
/// [HOUSECAT_RENDER_DOOR=<id>|none] [HOUSECAT_RENDER_PACK=<folder>] [HOUSECAT_RENDER_SCALE=2]
/// swift test --filter renderTheLivingRoom
@MainActor
@Test func renderTheLivingRoom() throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_ROOM"] else { return }
    let environment = ProcessInfo.processInfo.environment
    let factors = (environment["HOUSECAT_RENDER_FURNITURE"] ?? "\(Tuning.Room.furnitureScale)")
        .split(separator: ",").compactMap { Double($0) }
    // HOUSECAT_RENDER_ITEMS=empty[,<id>…]: the living room as a new home starts (and any pieces named, where the demo
    // layout has them).
    let only = (environment["HOUSECAT_RENDER_ITEMS"] ?? "").split(separator: ",").map(String.init)
    let empty = only.first == "empty"
    let kept = Tuning.Room.firstHome.union(only.dropFirst())
    // HOUSECAT_RENDER_SCALE=2: twice the pixels, the same framing.
    let pixels = CGFloat(environment["HOUSECAT_RENDER_SCALE"].flatMap(Double.init) ?? 1)
    // HOUSECAT_RENDER_CAT=u,v: where the cat sits (on the rug unless said).
    let cat = (environment["HOUSECAT_RENDER_CAT"] ?? "4.6,4.8").split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    // HOUSECAT_RENDER_PACK=<folder>: art not built into App/Art yet (its own art.json), such as doors to try.
    if let pack = environment["HOUSECAT_RENDER_PACK"] {
        try art.add(packAt: URL(fileURLWithPath: pack))
    }
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let layout = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
    let plans = try art.data("rooms/houses.json", as: HousePlans.self)
    let plan = try #require(plans.houses["london_terrace"])
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    for factor in factors {
        let rooms = plan.rooms.map { spot -> HouseModel.Room in
            var model = layout
            model.furnitureScale = factor
            var pieces = spot.room == .living ? layout.items : plans.roomStyles[spot.room.rawValue]?.preview ?? []
            if empty, spot.room == .living {
                pieces = pieces.filter { kept.contains($0.id) }
            }
            model.items = pieces.map {
                RoomModel.Placement(id: $0.id, u: $0.u.rounded(), v: $0.v.rounded(), facing: $0.facing, up: $0.up, placementID: UUID())
            }
            if spot.room != .living {
                model.window = plans.roomStyles[spot.room.rawValue]?.window
                model.door = nil
            } else if let door = environment["HOUSECAT_RENDER_DOOR"] {
                // HOUSECAT_RENDER_DOOR=<id> hangs another door in the living room (none: no door).
                model.door?.id = door
                if door == "none" {
                    model.door = nil
                }
            }
            // A new home's other rooms are closed: bare, with their price (as HouseBuilder has them).
            let closed = empty && spot.room != .living
            if closed {
                model.items = []
                if spot.outdoor != true {
                    model.wall = Tuning.House.bareWall
                    model.floor = Tuning.House.bareFloor
                }
            }
            return HouseModel.Room(
                id: spot.room, storey: spot.storey, u: spot.at[0], v: spot.at[1], outdoor: spot.outdoor ?? false, model: model,
                lockLabel: closed ? "Level \(spot.room.requiredLevel) · \(RoomRules.cost(of: spot.room, clubActive: false)) Beans" : nil
            )
        }
        let house = HouseModel(rooms: rooms, active: .living, sky: .day, ground: nil, stairs: plan.stairs)
        let door = environment["HOUSECAT_RENDER_DOOR"].map { "_\($0)" } ?? ""
        let name = String(format: "%@living_%03d%@", empty ? "\(only.joined(separator: "_"))_" : "", Int((factor * 100).rounded()), door)
        for (shot, zoom) in [("close", Optional<CGFloat>.none), ("room", 1), ("house", CGFloat(Tuning.Camera.minZoom))] {
            let scene = RoomScene(size: CGSize(width: 1376 * pixels, height: 1032 * pixels), art: art, content: content, house: house)
            scene.addCat(rig: rig, at: cat[0], cat[1], pose: .sitThreeQuarterFront)
            scene.zoom = zoom
            scene.fit()
            try still(scene, to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)_\(shot).png"))
        }
    }
}

/// The cat using the demo room's pieces at the furniture's size: on the sofa, in the box, at the post, at the bowl,
/// asleep on the rug and in a cat bed, up the cat tree, each settled and framed close.
/// HOUSECAT_RENDER_USE=<folder> [HOUSECAT_RENDER_FURNITURE=0.8,1] swift test --filter renderTheCatUsingTheFurniture
@MainActor
@Test func renderTheCatUsingTheFurniture() throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_USE"] else { return }
    let environment = ProcessInfo.processInfo.environment
    let factors = (environment["HOUSECAT_RENDER_FURNITURE"] ?? "\(Tuning.Room.furnitureScale)")
        .split(separator: ",").compactMap { Double($0) }
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    var layout = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
    layout.items = layout.items.map {
        RoomModel.Placement(id: $0.id, u: $0.u.rounded(), v: $0.v.rounded(), facing: $0.facing, up: $0.up, placementID: UUID())
    }
    // And two of the cat's own pieces from the shop, out in the room.
    layout.items += [
        RoomModel.Placement(id: "bedroom_catbed", u: 6, v: 7, facing: "R", placementID: UUID()),
        RoomModel.Placement(id: "living_cattree", u: 8, v: 6, facing: "R", placementID: UUID()),
    ]
    let uses: [(String, Activity, String)] = [
        ("sofa", .sit, "living_sofa"), ("box", .hide, "living_box"), ("post", .scratch, "living_scratch"),
        ("bowl", .bowlNag, "kitchen_bowl"), ("rug", .sleep, "living_rug"), ("catbed", .sleep, "bedroom_catbed"),
        ("cattree", .perch, "living_cattree"),
    ]
    for factor in factors {
        var model = layout
        model.furnitureScale = factor
        for (name, activity, item) in uses {
            let scene = RoomScene(size: CGSize(width: 1376, height: 1032), art: art, content: content, model: model)
            let director = scene.addCat(rig: rig, at: 5, 5, pose: .sitSide)
            scene.send(BehaviourChoice(activity: activity, item: item))
            var t = 0.0
            while !director.isIdle, t < 120 {
                director.update(1.0 / 30)
                t += 1.0 / 30
            }
            scene.fit()
            try still(scene, to: URL(fileURLWithPath: folder).appendingPathComponent(
                String(format: "use_%03d_%@.png", Int((factor * 100).rounded()), name)
            ))
        }
    }
}

/// One frame of a scene as a PNG, after a few seconds of updates so the camera has settled.
@MainActor
private func still(_ scene: SKScene, to url: URL) throws {
    let width = Int(scene.size.width), height = Int(scene.size.height)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let renderer = SKRenderer(device: device)
    renderer.scene = scene
    let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    description.usage = [.renderTarget, .shaderRead]
    description.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: description))
    let start = CACurrentMediaTime() + 1
    for frame in 0 ..< 90 {
        renderer.update(atTime: start + Double(frame) / 30)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        scene.backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: alpha)
        pass.colorAttachments[0].storeAction = .store
        let commands = try #require(queue.makeCommandBuffer())
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands, renderPassDescriptor: pass)
        commands.commit()
        commands.waitUntilCompleted()
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    let context = try #require(CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}
