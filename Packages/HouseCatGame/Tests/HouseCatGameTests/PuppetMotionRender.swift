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

/// Renders the moving puppet frame by frame, offscreen, to look at its movement closely (Josh, 19 Oct: the back legs
/// and ears looked strange going sideways). HOUSECAT_RENDER_PUPPET=<folder> writes <view>_<gait>_<frame>.png for each
/// view and gait over one and a half strides; HOUSECAT_PUPPET_LOOK=<preset id> picks the look (Midnight by default),
/// and HOUSECAT_TINT_PIECES colours each leg's pieces. HOUSECAT_PUPPET_VIEWS and HOUSECAT_PUPPET_GAITS (comma
/// separated) render only those; HOUSECAT_PUPPET_STRIDES how many strides (1.5); HOUSECAT_PUPPET_FRAME=<w>,<h>,<cat
/// height> the picture (720,560,420); HOUSECAT_PUPPET_BACKDROP=<r>,<g>,<b> its colour (0-1); HOUSECAT_PUPPET_NO_SHADOW
/// leaves the shadow out; HOUSECAT_PUPPET_STAND renders the cat standing still (one frame per view);
/// HOUSECAT_PUPPET_PASSES=white,features,tabby_classic,… renders the same frames again drawn from the white painting
/// and from each mask (<view>_<gait>_<pass>_<frame>.png), for a film started from the white frame to be tinted; a pass
/// "part:<name>" is white on the parts whose picture's name holds <name> (the ears, the tail) and black elsewhere.
/// HOUSECAT_PUPPET_ONLY_FRAME=<n> writes only that frame. HOUSECAT_PUPPET_FILMS renders the films the cat walks and runs
/// in, in the look.
@MainActor
@Test func renderThePuppetsMovement() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let folder = environment["HOUSECAT_RENDER_PUPPET"] else { return }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(root: repo.appendingPathComponent("App/Art/cat/custom"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let presetID = environment["HOUSECAT_PUPPET_LOOK"]
    CatNode.profileEars = environment["HOUSECAT_OLD_EARS"] == nil
    defer { CatNode.profileEars = true }
    let look = catArt.builder.data.presets.first { $0.id == presetID }?.look ?? .midnight
    func numbers(_ key: String) -> [Double]? {
        environment[key].map { $0.split(separator: ",").compactMap { Double($0) } }
    }
    let frame = numbers("HOUSECAT_PUPPET_FRAME") ?? [720, 560, 420]
    let size = CGSize(width: frame[0], height: frame[1])
    let backdrop = numbers("HOUSECAT_PUPPET_BACKDROP") ?? [0.93, 0.88, 0.78]
    let strides = numbers("HOUSECAT_PUPPET_STRIDES")?.first ?? 1.5
    let views = environment["HOUSECAT_PUPPET_VIEWS"].map { $0.split(separator: ",").map(String.init) }
    let gaitNames = environment["HOUSECAT_PUPPET_GAITS"].map { $0.split(separator: ",").map(String.init) }
    let standing = environment["HOUSECAT_PUPPET_STAND"] != nil
    // The puppet's own movement, unless HOUSECAT_PUPPET_FILMS asks for the films (walking and running, as in the game).
    let films = environment["HOUSECAT_PUPPET_FILMS"] != nil
    CatNode.films = films
    defer { CatNode.films = true }
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let gaits: [(String, CatNode.Gait)] = [("walk", .walk), ("trot", .trot), ("run", .run)]
        .filter { gaitNames?.contains($0.0) ?? true }
    let passes: [String?] = environment["HOUSECAT_PUPPET_PASSES"].map { $0.split(separator: ",").map { String($0) } } ?? [nil]
    defer { CatNode.paintOver = nil }
    for pass in passes {
    CatNode.paintOver = pass.map { paintOver(catArt, pass: $0) }
    for view in CatNode.View.allCases where views?.contains(view.rawValue) ?? true {
        for (gaitName, gait) in standing ? [("stand", CatNode.Gait.walk)] : gaits {
            let scene = SKScene(size: size)
            scene.backgroundColor = SKColor(red: backdrop[0], green: backdrop[1], blue: backdrop[2], alpha: 1)
            let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: CGFloat(frame[2]))
            cat.position = CGPoint(x: size.width / 2, y: CGFloat(frame[2]) / 7)
            scene.addChild(cat)
            if films {
                cat.loadFilmsNow()
            }
            cat.show(view, facingRight: false)
            cat.childNode(withName: "shadow")?.isHidden = environment["HOUSECAT_PUPPET_NO_SHADOW"] != nil || (pass != nil && pass != "white")
            if let pass, pass != "white" {
                // A mask is the same on the far legs: not shaded.
                cat.enumerateChildNodes(withName: "//leg_*") { node, _ in
                    (node as? SKSpriteNode)?.colorBlendFactor = 0
                }
            }
            if !standing {
                cat.move(gait)
                // At the room's pace for the gait, for a cat this size (the room's cat is `Tuning.Room.catHeight`).
                let pace: CatDirector.Pace = switch gait {
                case .walk: .walk
                case .trot: .trot
                case .run: .run
                }
                cat.moveSpeed = pace.speed * CGFloat(frame[2] / Tuning.Builder.catHeight)
            }
            if ProcessInfo.processInfo.environment["HOUSECAT_TINT_PIECES"] != nil {
                // Each leg's pieces in their own colour, to see where it bends.
                cat.enumerateChildNodes(withName: "//leg_*") { node, _ in
                    guard let sprite = node as? SKSpriteNode, let name = sprite.name else { return }
                    sprite.color = name.hasSuffix(".paw") ? .blue : name.hasSuffix(".middle") ? .green : .red
                    sprite.colorBlendFactor = name.contains("_far") ? 0.35 : 0.6
                }
            }
            let renderer = SKRenderer(device: device)
            renderer.scene = scene
            let p = Tuning.Puppet.self
            let hz = switch gait {
            case .walk: p.walkHz
            case .trot: (p.walkHz + p.runHz) / 2
            case .run: p.runHz
            }
            let stride = switch gait {
            case .walk: p.walkStride
            case .trot: p.trotStride
            case .run: p.runStride
            }
            // A stride keeps pace with the floor (CatNode.step).
            let paced = Double(cat.moveSpeed) / (stride * frame[2])
            let frames = standing ? 1 : Int((strides / (paced > 0 ? paced : hz)) * 30)
            let start = CACurrentMediaTime() + 1
            for frame in 0 ..< frames {
                cat.step(1.0 / 30)
                if let only = environment["HOUSECAT_PUPPET_ONLY_FRAME"].flatMap(Int.init), frame != only {
                    if frame > only {
                        break
                    }
                    continue
                }
                let name = [view.rawValue, gaitName, pass?.replacingOccurrences(of: ":", with: "-")].compactMap(\.self).joined(separator: "_")
                if pass == "points" {
                    // Where the ears join the head and end, where the tail joins the body and the torso's middle, in the
                    // picture's pixels from the top left (the film tracks them, to put swapped ears and tails on).
                    var points: [String: [Double]] = [:]
                    func pixel(_ point: CGPoint, in node: SKNode) -> [Double] {
                        let at = node.convert(point, to: scene)
                        return [Double(at.x), Double(size.height - at.y)]
                    }
                    for (key, node) in cat.parts[view] ?? [:] {
                        let top = CGPoint(x: (0.5 - node.anchorPoint.x) * node.size.width, y: (1 - node.anchorPoint.y) * node.size.height)
                        if key.hasPrefix("ear_") {
                            points["\(key)_base"] = pixel(.zero, in: node)
                            points["\(key)_tip"] = pixel(top, in: node)
                        } else if key.hasPrefix("tail") {
                            points["tail_root"] = pixel(.zero, in: node)
                        } else if key == "torso" {
                            points["torso_middle"] = pixel(.zero, in: node)
                        }
                    }
                    let data = try JSONSerialization.data(withJSONObject: points, options: [.sortedKeys])
                    try data.write(to: out.appendingPathComponent(String(format: "%@_%03d.json", name, frame)))
                    continue
                }
                let url = out.appendingPathComponent(String(format: "%@_%03d.png", name, frame))
                let ground = pass == nil || pass == "white" ? backdrop : [0, 0, 0]
                scene.backgroundColor = SKColor(red: ground[0], green: ground[1], blue: ground[2], alpha: 1)
                try render(renderer, scene: scene, size: size, time: start + Double(frame) / 30, backdrop: ground, device: device, queue: queue, to: url)
            }
        }
    }
    }
}

/// Each part drawn from its white painting ("white") or a mask of it (grey, or the features' red and green irises and
/// blue nose), with the painting's own alpha; a part without that mask is black.
private func paintOver(_ catArt: CatArt, pass: String) -> (CatBuilder.Sprite) -> CGImage? {
    { sprite in
        guard let painting = catArt.painting(sprite.path) else { return nil }
        let width = painting.width, height = painting.height
        var r = [UInt8](repeating: 0, count: width * height), g = r, b = r
        func plane(_ values: [UInt8], from raster: Raster) -> [UInt8] {
            raster.width == width && raster.height == height
                ? values : Raster.scaled(values, from: (raster.width, raster.height), to: (width, height))
        }
        if pass == "ids" {
            // Each part its own grey: the torso, head, ears and tail, and each leg.
            let shades: [(String, UInt8)] = [
                ("leg_front_near", 160), ("leg_front_far", 190), ("leg_back_near", 220), ("leg_back_far", 250),
                ("_ear_", 100), ("ear_", 100), ("_tail", 120), ("_head", 80), ("_torso", 40),
            ]
            let shade = shades.first { sprite.path.contains($0.0) }?.1 ?? 20
            r = [UInt8](repeating: shade, count: width * height)
            g = r
            b = r
        } else if pass.hasPrefix("part:") {
            let lit: UInt8 = sprite.path.contains(pass.dropFirst(5)) ? 255 : 0
            r = [UInt8](repeating: lit, count: width * height)
            g = r
            b = r
        } else if pass == "white" {
            r = painting.r.map { UInt8(max(0, min(255, $0))) }
            g = painting.g.map { UInt8(max(0, min(255, $0))) }
            b = painting.b.map { UInt8(max(0, min(255, $0))) }
        } else if let raster = Raster.read(catArt.root.appendingPathComponent("masks/\(pass)/\(sprite.path)")) {
            if pass == "features", raster.planes.count >= 3 {
                r = plane(raster.planes[0], from: raster)
                g = plane(raster.planes[1], from: raster)
                b = plane(raster.planes[2], from: raster)
            } else {
                r = plane(raster.planes[0], from: raster)
                g = r
                b = r
            }
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0 ..< width * height {
            let a = Int(painting.alpha[index])
            pixels[index * 4] = UInt8(Int(r[index]) * a / 255)
            pixels[index * 4 + 1] = UInt8(Int(g[index]) * a / 255)
            pixels[index * 4 + 2] = UInt8(Int(b[index]) * a / 255)
            pixels[index * 4 + 3] = UInt8(a)
        }
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }
}

private func render(
    _ renderer: SKRenderer,
    scene _: SKScene,
    size: CGSize,
    time: TimeInterval,
    backdrop: [Double],
    device: MTLDevice,
    queue: MTLCommandQueue,
    to url: URL
) throws {
    let width = Int(size.width), height = Int(size.height)
    let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    description.usage = [.renderTarget, .shaderRead]
    description.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: description))
    renderer.update(atTime: time)
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: backdrop[0], green: backdrop[1], blue: backdrop[2], alpha: 1)
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

/// The cat walking, trotting and running about the living room as in the game (RoomScene, its director, the films),
/// rendered offscreen at an iPhone's landscape size: HOUSECAT_RENDER_ROOM=<folder> writes room_<frame>.png;
/// HOUSECAT_PUPPET_LOOK=<preset id> picks the look.
@MainActor
@Test func renderTheCatWalkingInTheRoom() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let folder = environment["HOUSECAT_RENDER_ROOM"] else { return }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let model = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
    let look = catArt.builder.data.presets.first { $0.id == environment["HOUSECAT_PUPPET_LOOK"] }?.look ?? .midnight
    let size = CGSize(width: 956, height: 440)
    let scene = RoomScene(size: size, art: art, content: content, model: model)
    scene.fit()
    let director = scene.addCat(rig: rig, catArt: catArt, look: look, at: 6, 6, pose: .sitSide)
    director.cat.loadFilmsNow()
    let grid = scene.grid
    director.run([
        .wait(0.5),
        .rise(.side),
        .move(to: grid.floor(3, 9), pace: .walk),
        .move(to: grid.floor(5, 9), pace: .walk),
        .move(to: grid.floor(8, 6), pace: .trot),
        .move(to: grid.floor(4, 3), pace: .run),
        .move(to: grid.floor(4, 6), pace: .walk),
        .settle(.sitThreeQuarterFront),
    ])
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let renderer = SKRenderer(device: device)
    renderer.scene = scene
    let scale = 1.5
    let pixels = CGSize(width: size.width * scale, height: size.height * scale)
    let start = CACurrentMediaTime() + 1
    for frame in 0 ..< Int((environment["HOUSECAT_ROOM_SECONDS"].flatMap(Double.init) ?? 12) * 30) {
        let url = out.appendingPathComponent(String(format: "room_%04d.png", frame))
        try render(renderer, scene: scene, size: pixels, time: start + Double(frame) / 30, backdrop: [0, 0, 0], device: device, queue: queue, to: url)
    }
}
