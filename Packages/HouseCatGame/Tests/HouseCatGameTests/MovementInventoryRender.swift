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

/// Every way the cat moves, each rendered offscreen as a short clip (Josh, 21 Oct: "can we do animations for all
/// movement of the cat"): the room's walks, runs and trot in each view, turning round, sitting down and getting up,
/// lying down and stretching up, jumping up and down, scratching, zoomies, a body garment walking, swapped ears and a
/// bobtail walking, the logo's run-in, the dressing room's standing turn, the window's sitting cat, the games' pounce
/// and peek, and the two puppet art faults. HOUSECAT_RENDER_INVENTORY=<folder> writes <n>_<name>/<frame>.png for each
/// (3.5 s at 30 a second) and `tiles.json` saying which are films and which the puppet; `tools/app-assets/
/// movement_sheet.py` stitches them into a contact sheet. HOUSECAT_INVENTORY_ONLY=<name,…> renders only those.
@MainActor
@Test func renderTheMovementInventory() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let folder = environment["HOUSECAT_RENDER_INVENTORY"] else { return }
    let only = environment["HOUSECAT_INVENTORY_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let size = CGSize(width: 480, height: 360)
    let height: CGFloat = 170
    let seconds = Double(environment["HOUSECAT_INVENTORY_SECONDS"] ?? "") ?? 3.5
    let midnight = catArt.builder.data.presets.first { $0.id == "midnight" }?.look ?? .midnight
    let mainecoon = catArt.builder.data.presets.first { $0.id == "maine_coon" }?.look ?? .midnight
    let chunky = catArt.builder.data.presets.first { $0.id == "bombay" }?.look ?? .midnight
    let swapped = catArt.builder.normalized(CatLook(ears: "folded", tail: "bobtail"))
    let garment = content.outfits.outfits.first { $0.id == "hoodie" } ?? content.outfits.outfits.first { $0.slot == .body }
    // Speeds in Tuning are for a cat Tuning.Builder.catHeight tall.
    let k = height / CGFloat(Tuning.Builder.catHeight)

    /// One clip: its name, whether the cat is a film or the puppet in it, and how it is set up and driven.
    struct Tile {
        var name: String
        var how: String
        var look: CatLook
        var outfit: OutfitsFile.Outfit?
        var setUp: @MainActor (CatNode, CatDirector, IsoGrid) -> Void
        /// Called every frame with the time, for clips driven by hand (nil: the director alone).
        var drive: (@MainActor (CatNode, TimeInterval) -> Void)?
        var follow = false
    }
    func walking(_ view: CatNode.View, _ gait: CatNode.Gait, right: Bool = false, speed: CGFloat) -> @MainActor (CatNode, CatDirector, IsoGrid) -> Void {
        { cat, _, _ in
            cat.show(view, facingRight: right)
            cat.move(gait)
            cat.moveSpeed = speed * k
            cat.moveDirection = view == .front ? CGVector(dx: 0, dy: -1) : view == .side ? CGVector(dx: right ? 1 : -1, dy: 0) : CGVector(dx: right ? 1 : -1, dy: -0.6)
        }
    }
    let p = Tuning.Puppet.self
    // The labels say what each movement was before the films beyond the walk and run (the inventory of 21 Oct), or
    // what it is with them (HOUSECAT_INVENTORY_AFTER): the front films, the sit-down and scratch films, standing and
    // jumping on held film pictures, the garment in the film.
    let after = environment["HOUSECAT_INVENTORY_AFTER"] != nil
    func was(_ before: String, _ now: String) -> String {
        after ? now : before
    }
    var tiles: [Tile] = [
        Tile(name: "walk side-on", how: "film", look: midnight, setUp: walking(.side, .walk, speed: CGFloat(p.walkSpeed))),
        Tile(name: "run side-on", how: "film", look: midnight, setUp: walking(.side, .run, speed: CGFloat(p.runSpeed))),
        Tile(name: "trot side-on", how: "film (walk, quicker)", look: midnight, setUp: walking(.side, .trot, speed: CGFloat(p.trotSpeed))),
        Tile(name: "walk three-quarters", how: "film", look: midnight, setUp: walking(.tqfront, .walk, speed: CGFloat(p.walkSpeed))),
        Tile(name: "run three-quarters", how: "film", look: midnight, setUp: walking(.tqfront, .run, speed: CGFloat(p.runSpeed))),
        Tile(name: "walk coming at you", how: was("PUPPET", "film"), look: midnight, setUp: walking(.front, .walk, speed: CGFloat(p.walkSpeed))),
        Tile(name: "run coming at you", how: was("PUPPET", "film"), look: midnight, setUp: walking(.front, .run, speed: CGFloat(p.runSpeed))),
        Tile(name: "walk away", how: "film (side view)", look: midnight, setUp: walking(.side, .walk, right: true, speed: CGFloat(p.walkSpeed))),
        Tile(name: "walk away from behind", how: was("no view from behind", "film"), look: midnight, setUp: walking(.tqback, .walk, right: true, speed: CGFloat(p.walkSpeed))),
        Tile(name: "turning round", how: was("film, puppet in the turn", "film, held picture in the turn"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.rise(to: .side, facingRight: false, duration: 0)
            director.run([.move(to: grid.floor(4.2, 5), pace: .walk), .wait(0.1), .move(to: grid.floor(6.5, 5), pace: .walk)])
        }, follow: true),
        Tile(name: "sitting down", how: was("film, then painting", "sit-down film, then painting"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.rise(to: .side, facingRight: false, duration: 0)
            director.run([.move(to: grid.floor(3.6, 5), pace: .walk), .settle(.sitSide), .wait(1)])
        }, follow: true),
        Tile(name: "getting up", how: was("painting, puppet, film", "sit-down film backwards, film"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.settle(into: .sitSide, duration: 0)
            director.run([.wait(0.6), .rise(.side), .move(to: grid.floor(3.2, 5), pace: .walk)])
        }, follow: true),
        Tile(name: "waking, stretch", how: "paintings", look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.settle(into: .sleepCurl, duration: 0)
            director.run([.wait(0.4), .glance(.stretchSide), .wait(Tuning.Puppet.stretchSeconds), .rise(.side), .move(to: grid.floor(3.5, 5), pace: .walk)])
        }, follow: true),
        Tile(name: "lying down (loaf)", how: was("film, then painting", "sit-down film, then painting"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.rise(to: .side, facingRight: false, duration: 0)
            director.run([.move(to: grid.floor(3.8, 5), pace: .stroll), .settle(.loafSide), .wait(1)])
        }, follow: true),
        Tile(name: "jump up", how: was("PUPPET (still, squashed)", "film pictures held (stand, stretch)"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.rise(to: .tqfront, facingRight: false, duration: 0)
            director.run([.wait(0.4), .move(to: grid.floor(4.4, 4.4), pace: .walk), .hop(to: grid.floor(3.8, 3.8), lift: 70), .wait(0.5), .settle(.sitThreeQuarterFront)])
        }, follow: true),
        Tile(name: "jump down", how: was("PUPPET (still, squashed)", "film pictures held (stand, stretch)"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(4, 4), lift: 70)
            cat.settle(into: .sitThreeQuarterFront, duration: 0)
            director.run([.wait(0.5), .rise(.tqfront), .hop(to: grid.floor(4.75, 4.75), lift: 0), .move(to: grid.floor(5.6, 5.6), pace: .walk)])
        }, follow: true),
        Tile(name: "scratching", how: was("PUPPET (legs swing)", "scratch film (rise, rake loop, down)"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.rise(to: .side, facingRight: false, duration: 0)
            director.run([.face(.side, right: true), .scratch(2.6), .settle(.sitSide)])
        }, follow: true),
        Tile(name: "zoomies", how: was("film, puppet at the stop", "film, held picture at the stop"), look: midnight, setUp: { cat, director, grid in
            director.place(at: grid.floor(5, 5))
            cat.rise(to: .side, facingRight: false, duration: 0)
            director.run([.move(to: grid.floor(2, 5), pace: .dash), .wait(0.35), .move(to: grid.floor(6, 2.5), pace: .dash), .move(to: grid.floor(3, 7), pace: .dash), .settle(.loafSide)])
        }, follow: true),
        Tile(name: "garment walk side-on", how: was("PUPPET", "film, garment on the torso map"), look: midnight, outfit: garment, setUp: walking(.side, .walk, speed: CGFloat(p.walkSpeed))),
        Tile(name: "garment run three-quarters", how: was("PUPPET", "film, garment on the torso map"), look: midnight, outfit: garment, setUp: walking(.tqfront, .run, speed: CGFloat(p.runSpeed))),
        Tile(name: "swapped ears, bobtail", how: "film + pieces", look: swapped, setUp: walking(.side, .walk, speed: CGFloat(p.walkSpeed))),
        Tile(name: "dressing room stand, turn", how: was("PUPPET standing", "film pictures held, turn"), look: midnight, setUp: { cat, _, _ in
            cat.show(.side, facingRight: false)
        }, drive: { cat, t in
            if abs(t - 1.2) < 0.02 { cat.turn(to: .tqfront, facingRight: false) }
            if abs(t - 2.4) < 0.02 { cat.turn(to: .front, facingRight: false) }
        }),
        Tile(name: "window, widget, Watch", how: "painting (still)", look: midnight, setUp: { cat, _, _ in
            cat.show(.tqfront, facingRight: false)
            cat.settle(into: .sitFront, duration: 0)
        }),
        Tile(name: "game: laser pounce", how: was("film, PUPPET in the air", "film, held picture in the air"), look: midnight, setUp: walking(.side, .run, right: true, speed: CGFloat(p.runSpeed)), drive: { cat, t in
            // As MiniGameScene: a crouch, a leap with the standing puppet leaning, a landing.
            if t > 1.0, t < 1.0 + 1.0 / 30 { cat.stopCycle(); cat.squash(0.12) }
            if t >= 1.25, t < 1.85 {
                let u = CGFloat((t - 1.25) / 0.6)
                let lift = 120 * 4 * u * (1 - u)
                cat.position = CGPoint(x: 240 + 60 * u, y: 110 + lift)
                cat.shadowDrop = lift
                cat.zRotation = (0.5 - u) * 0.5
            }
            if t >= 1.85, t < 1.85 + 1.0 / 30 { cat.zRotation = 0; cat.shadowDrop = 0; cat.squash(0.1) }
            if t > 2.4, t < 2.4 + 1.0 / 30 { cat.settle(into: .sitThreeQuarterFront) }
        }),
        Tile(name: "game: hide and seek peek", how: "painting slides", look: midnight, setUp: { cat, _, _ in
            cat.show(.tqfront, facingRight: false)
            cat.settle(into: .sitThreeQuarterFront, duration: 0)
        }, drive: { cat, t in
            let peek = (t.truncatingRemainder(dividingBy: 1.4)) < 0.7
            cat.position.y = 110 + (peek ? 40 : 0)
        }),
        Tile(name: "Maine Coon three-quarters stand", how: was("PUPPET (no ears?)", "film standing picture (puppet until tinted)"), look: mainecoon, setUp: { cat, _, _ in
            cat.show(.tqfront, facingRight: false)
        }),
        Tile(name: "short chunky side stand", how: was("PUPPET (rabbit ears?)", "film standing picture (puppet until tinted, ears scaled)"), look: chunky, setUp: { cat, _, _ in
            cat.show(.side, facingRight: false)
        }),
    ]
    if let only {
        tiles = tiles.filter { only.contains($0.name) }
    }
    var index: [[String: String]] = []
    var cats: [String: CatNode] = [:]
    for (n, tile) in tiles.enumerated() {
        let name = String(format: "%02d_%@", n, tile.name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ":", with: ""))
        let tileOut = out.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: tileOut, withIntermediateDirectories: true)
        index.append(["folder": name, "name": tile.name, "how": tile.how])
        let scene = SKScene(size: size)
        scene.backgroundColor = SKColor(red: 0.93, green: 0.88, blue: 0.78, alpha: 1)
        let world = SKNode()
        scene.addChild(world)
        let cat = CatNode(art: art, rig: rig, catArt: catArt, look: tile.look, height: height)
        let key = "\(tile.look.body)/\(tile.look.ears)/\(tile.look.tail)"
        if let made = cats[key] {
            cat.shareFilms(from: made)
        } else {
            cat.loadFilmsNow()
            cats[key] = cat
        }
        if let outfit = tile.outfit {
            cat.wear(outfit)
        }
        world.addChild(cat)
        let grid = IsoGrid()
        let director = CatDirector(cat: cat, grid: grid)
        cat.position = CGPoint(x: size.width / 2, y: 110)
        tile.setUp(cat, director, grid)
        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        let start = CACurrentMediaTime() + 1
        let frames = Int(seconds * 30)
        for frame in 0 ..< frames {
            let t = Double(frame) / 30
            if tile.follow {
                director.update(1.0 / 30)
                // The camera follows the cat's feet on the floor.
                world.position = CGPoint(x: size.width / 2 - director.floorPoint.x, y: 110 - director.floorPoint.y)
            } else {
                cat.step(1.0 / 30)
            }
            tile.drive?(cat, t)
            let url = tileOut.appendingPathComponent(String(format: "%03d.png", frame))
            try renderInventory(renderer, size: size, time: start + t, device: device, queue: queue, to: url)
        }
    }
    // The logo's run-in: the plain puppet runs and leaps, then sits and curls (no curl film here).
    if only?.contains("logo") ?? true {
        let name = String(format: "%02d_logo_run_in", tiles.count)
        let tileOut = out.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: tileOut, withIntermediateDirectories: true)
        index.append(["folder": name, "name": "logo run-in", "how": was("PUPPET (plain set)", "films (Midnight, tinted black)")])
        let logo = Tuning.Logo.self
        let scene = LogoScene(size: CGSize(width: 1, height: 1), art: art, rig: rig, ink: .light, act: .intro)
        let box = CGSize(width: 480, height: 480 * logo.boxSize[1] / logo.boxSize[0])
        scene.size = CGSize(width: 480, height: 360)
        scene.scaleMode = .fill
        scene.box = CGRect(x: 0, y: 60, width: box.width, height: box.height)
        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        let start = CACurrentMediaTime() + 1
        for frame in 0 ..< Int(seconds * 30 * 2) {
            let url = tileOut.appendingPathComponent(String(format: "%03d.png", frame))
            try renderInventory(renderer, size: CGSize(width: 480, height: 360), time: start + Double(frame) / 30, device: device, queue: queue, to: url, backdrop: [0.98, 0.95, 0.9])
        }
    }
    let data = try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted])
    try data.write(to: out.appendingPathComponent("tiles.json"))
}

private func renderInventory(
    _ renderer: SKRenderer, size: CGSize, time: TimeInterval, device: MTLDevice, queue: MTLCommandQueue, to url: URL, backdrop: [Double] = [0.93, 0.88, 0.78]
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

/// A body garment on a film's frames (21 Oct): every frame of each film that carries the torso's map, tinted into a
/// look with the garment drawn in, as `CatNode` shows them. HOUSECAT_RENDER_FILM_GARMENT=<folder> writes
/// <body>_<view>_<gait>_<frame>.png; HOUSECAT_PUPPET_LOOK=<preset> (Midnight), HOUSECAT_FILM_GARMENT=<outfit id>
/// (the hoodie), HOUSECAT_FILM_KEYS=<view>/<gait>,… (every film with a map).
@MainActor
@Test func renderTheGarmentOnTheFilms() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let folder = environment["HOUSECAT_RENDER_FILM_GARMENT"] else { return }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let look = catArt.builder.data.presets.first { $0.id == environment["HOUSECAT_PUPPET_LOOK"] }?.look ?? .midnight
    let id = environment["HOUSECAT_FILM_GARMENT"] ?? "hoodie"
    let garment = try #require(content.outfits.outfits.first { $0.id == id })
    let keys = environment["HOUSECAT_FILM_KEYS"].map { $0.split(separator: ",").map(String.init) }
    var written = 0
    for view in CatNode.View.allCases {
        for gait in ["walk", "run"] {
            guard keys?.contains("\(view.rawValue)/\(gait)") ?? true,
                  let film = catArt.film(body: look.body, view: view.rawValue, gait: gait), catArt.filmTakesGarments(film),
                  let path = OutfitFit.garment(garment, body: look.body, view: view.rawValue), let picture = art.image(path) else { continue }
            for (i, frame) in film.frames.enumerated() {
                guard let image = catArt.filmFrame(frame, look: look, garment: picture) else { continue }
                let url = out.appendingPathComponent(String(format: "%@_%@_%@_%02d.png", look.body, view.rawValue, gait, i))
                let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                #expect(CGImageDestinationFinalize(destination))
                written += 1
            }
        }
    }
    #expect(written > 0, "no film carries the torso's map for \(look.body)")
}
