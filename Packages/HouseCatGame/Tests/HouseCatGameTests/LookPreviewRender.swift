import CoreGraphics
import Foundation
import HouseCatCore
@testable import HouseCatGame
import ImageIO
import Metal
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// The shop's room look previews (Josh, 19 Oct: "room looks as large previews"), drawn by the game itself: each look's
/// wallpaper and floor on the room's corner in midday light, its pieces against the walls biggest first and its rug
/// in the middle, framed on the pieces, with the window and nothing else. HOUSECAT_RENDER_LOOKS=<folder> writes
/// shop_look_<bundle id>.png (1800 x 1460, see-through above the walls) for assets/ui/shop; run it again when the
/// furniture's art or scale changes.
@MainActor
@Test func renderTheRoomLookPreviews() throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_LOOKS"] else { return }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let base = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
    let items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
    let surfaces = Dictionary(uniqueKeysWithValues: content.catalogue.surfaces.map { ($0.id, $0) })
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let size = CGSize(width: 1800, height: 1460)
    for bundle in content.bundles.bundles {
        var model = base
        model.wall = bundle.wallpaper ?? base.wall
        model.floor = bundle.floor ?? base.floor
        model.door = nil
        model.items = LookLayout.arrange(bundle.items.compactMap { items[$0] })
        let outdoor = bundle.room == .garden
        let room = RoomNode(
            id: bundle.room, model: model, art: art, items: items, surfaces: surfaces,
            walls: (left: .full, right: .full), outdoor: outdoor
        )
        // Framed on the floor pieces (a wall piece can be as big as the wall: the starlit attic's cobweb) and the top
        // of the back corner, at the picture's shape, with a margin.
        var frame = CGRect.null
        for child in room.children {
            guard let item = items[child.name ?? ""], item.layer != .wall else { continue }
            frame = frame.union(child.calculateAccumulatedFrame())
        }
        let top = IsoGrid().unit * (outdoor ? CGFloat(Tuning.House.gardenWallHeight) : IsoGrid().wallCells)
        frame = frame.union(CGRect(x: frame.midX, y: top * 0.7, width: 1, height: 1)).insetBy(dx: -50, dy: -40)
        let aspect = size.width / size.height
        if frame.width / frame.height < aspect {
            frame = frame.insetBy(dx: -(frame.height * aspect - frame.width) / 2, dy: 0)
        } else {
            frame = frame.insetBy(dx: 0, dy: -(frame.width / aspect - frame.height) / 2)
        }
        let scene = SKScene(size: size)
        scene.backgroundColor = .clear
        let k = size.width / frame.width
        room.setScale(k)
        room.position = CGPoint(x: -frame.minX * k, y: -frame.minY * k)
        scene.addChild(room)
        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        let url = out.appendingPathComponent("shop_look_\(bundle.id).png")
        try renderPicture(renderer, size: size, device: device, queue: queue, to: url)
    }
}

/// Where a look's pieces stand in its preview: the floor pieces against the back walls, right then left, biggest
/// first and from the corner out; wall pieces on the walls; rugs in the middle; whatever is left where it first fits.
enum LookLayout {
    static func arrange(_ pieces: [CatalogueFile.Item]) -> [RoomModel.Placement] {
        var placed: [PlacementRules.Piece] = []
        var out: [RoomModel.Placement] = []
        let order = pieces.sorted { $0.footprint.w * $0.footprint.d > $1.footprint.w * $1.footprint.d }
        var wall = 0
        for item in order {
            var spot: PlacementRules.Piece?
            let fresh = PlacementRules.Piece(item, x: 0, y: 0, facing: .right)
            if fresh.decal {
                spot = [(3, 3), (2, 3), (3, 2), (4, 4)].lazy.map { cell -> PlacementRules.Piece in
                    var rug = fresh
                    rug.x = cell.0
                    rug.y = cell.1
                    return rug
                }.first { PlacementRules.fits($0, among: placed) }
            } else {
                // Alternate walls: the right wall (v = 0) facing R, the left (u = 0) facing L.
                for attempt in 0 ..< 2 {
                    let right = (wall + attempt).isMultiple(of: 2)
                    var piece = right ? fresh : fresh.turned()
                    for along in 1 ..< Tuning.Room.gridWidth {
                        if right {
                            piece.x = along
                            piece.y = 0
                        } else {
                            piece.x = 0
                            piece.y = along
                        }
                        if PlacementRules.fits(piece, among: placed) {
                            spot = piece
                            break
                        }
                    }
                    if spot != nil {
                        break
                    }
                }
                wall += 1
            }
            guard let found = spot ?? PlacementRules.firstFit(fresh, among: placed) else { continue }
            placed.append(found)
            out.append(RoomModel.Placement(id: item.id, u: Double(found.x), v: Double(found.y), facing: found.facing.rawValue))
        }
        return out
    }
}

private func renderPicture(_ renderer: SKRenderer, size: CGSize, device: MTLDevice, queue: MTLCommandQueue, to url: URL) throws {
    let width = Int(size.width), height = Int(size.height)
    let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    description.usage = [.renderTarget, .shaderRead]
    description.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: description))
    renderer.update(atTime: 0)
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    let commands = try #require(queue.makeCommandBuffer())
    renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands, renderPassDescriptor: pass)
    commands.commit()
    commands.waitUntilCompleted()
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
