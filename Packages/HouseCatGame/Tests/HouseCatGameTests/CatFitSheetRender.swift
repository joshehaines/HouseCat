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

/// Contact sheets of the cat in every way the game draws it (Josh, 20 Oct: "show two sets of ears", "most of them are
/// buggy and go through the cat"): standing in each view, the walk and run films, every resting pose, both facings and
/// as a kitten, one row a look (and outfit). HOUSECAT_FIT_SHEET=<folder> writes one PNG a row, `<row>.png`, each cell
/// `HOUSECAT_FIT_CELL` (260,230,150: width, height, the cat's height) with the cell's name in `columns.txt`.
/// HOUSECAT_FIT_ROWS=ears renders each body with each ear shape and the bobtail; =outfits every outfit on
/// HOUSECAT_FIT_BODIES (all eight by default), or HOUSECAT_FIT_OUTFITS=<id,id> only those (HOUSECAT_FIT_VARIANTS: and
/// on each swap ear shape and the bobtail). HOUSECAT_FIT_LOOK=<preset>
/// tints them (a ginger tabby by default, so ears and garments show).
@MainActor
@Test func renderTheFitSheets() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let folder = environment["HOUSECAT_FIT_SHEET"] else { return }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    // HOUSECAT_FIT_ART=<folder>: another art folder (a proposal's repainted outfit beside links to the rest).
    let root = environment["HOUSECAT_FIT_ART"].map { URL(fileURLWithPath: $0) } ?? repo.appendingPathComponent("App/Art")
    let art = try ArtLibrary(root: root)
    let catArt = try CatArt(root: root.appendingPathComponent("cat/custom"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let cell = (environment["HOUSECAT_FIT_CELL"] ?? "260,230,150").split(separator: ",").compactMap { Double($0) }
    let base = catArt.builder.data.presets.first { $0.id == (environment["HOUSECAT_FIT_LOOK"] ?? "ginger_tabby") }?.look ?? .midnight
    let bodies = environment["HOUSECAT_FIT_BODIES"].map { $0.split(separator: ",").map(String.init) }
        ?? catArt.builder.data.bodies.map(\.id)

    enum State {
        case stand(CatNode.View, right: Bool)
        case film(CatNode.View, CatNode.Gait, at: Double, right: Bool)
        case pose(CatPose, right: Bool)
        case kitten(CatPose)
    }
    let allStates: [(String, State)] = [
        ("stand side", .stand(.side, right: false)),
        ("stand 3/4", .stand(.tqfront, right: false)),
        ("stand 3/4 R", .stand(.tqfront, right: true)),
        ("stand front", .stand(.front, right: false)),
        ("walk side", .film(.side, .walk, at: 0.3, right: false)),
        ("walk side .8", .film(.side, .walk, at: 0.8, right: false)),
        ("walk 3/4", .film(.tqfront, .walk, at: 0.3, right: false)),
        ("walk 3/4 R", .film(.tqfront, .walk, at: 0.8, right: true)),
        ("walk front", .film(.front, .walk, at: 0.3, right: false)),
        ("run side", .film(.side, .run, at: 0.3, right: false)),
        ("run 3/4", .film(.tqfront, .run, at: 0.6, right: false)),
        ("sit side", .pose(.sitSide, right: false)),
        ("sit 3/4", .pose(.sitThreeQuarterFront, right: false)),
        ("sit 3/4 R", .pose(.sitThreeQuarterFront, right: true)),
        ("sit front", .pose(.sitFront, right: false)),
        ("sit back", .pose(.sitBack, right: false)),
        ("loaf side", .pose(.loafSide, right: false)),
        ("loaf 3/4", .pose(.loafThreeQuarterFront, right: false)),
        ("sleep", .pose(.sleepCurl, right: false)),
        ("stretch", .pose(.stretchSide, right: false)),
        ("kitten 3/4", .kitten(.sitThreeQuarterFront)),
    ]
    // HOUSECAT_FIT_STATES=<name,name> only those cells; HOUSECAT_FIT_BEFORE draws the outfits as they were before the
    // 20 Oct fit (no hat covering the ears).
    let only = environment["HOUSECAT_FIT_STATES"].map { Set($0.split(separator: ",").map(String.init)) }
    var states = allStates.filter { only?.contains($0.0) ?? true }
    // HOUSECAT_FIT_FRAMES=<view>/<walk|run>: a film's loop instead, HOUSECAT_FIT_FRAMECOUNT (12) moments through it.
    if let film = environment["HOUSECAT_FIT_FRAMES"]?.split(separator: "/"), film.count == 2, let view = CatNode.View(rawValue: String(film[0])) {
        let count = Int(environment["HOUSECAT_FIT_FRAMECOUNT"] ?? "") ?? 12
        states = (0 ..< count).map { i in
            ("\(film[1]) \(film[0]) \(i)", .film(view, film[1] == "run" ? .run : .walk, at: (Double(i) + 0.5) / Double(count), right: false))
        }
    }
    OutfitFit.coversEarsOn = environment["HOUSECAT_FIT_BEFORE"] == nil
    defer { OutfitFit.coversEarsOn = true }
    try states.map(\.0).joined(separator: "\n").write(to: out.appendingPathComponent("columns.txt"), atomically: true, encoding: .utf8)

    var rows: [(String, CatLook, OutfitsFile.Outfit?)] = []
    if environment["HOUSECAT_FIT_ROWS"] == "outfits" {
        let wanted = environment["HOUSECAT_FIT_OUTFITS"].map { Set($0.split(separator: ",").map(String.init)) }
        for body in bodies {
            var look = base
            look.body = body
                look.weight = body.hasSuffix("_chunky") ? Tuning.Cat.chunkyDefaultWeight : Tuning.Cat.slimDefaultWeight
            for outfit in content.outfits.outfits where wanted?.contains(outfit.id) ?? true {
                rows.append(("\(outfit.id)__\(body)", catArt.builder.normalized(look), outfit))
                // HOUSECAT_FIT_VARIANTS: also with each swap ear shape and the bobtail.
                guard environment["HOUSECAT_FIT_VARIANTS"] != nil, let swaps = catArt.builder.body(body) else { continue }
                for ears in swaps.earSwaps ? catArt.builder.data.ears.map(\.id).filter({ $0 != "own" }) : [] {
                    var variant = look
                    variant.ears = ears
                    rows.append(("\(outfit.id)__\(body)__\(ears)", catArt.builder.normalized(variant), outfit))
                }
                if swaps.tailSwaps {
                    var variant = look
                    variant.tail = "bobtail"
                    rows.append(("\(outfit.id)__\(body)__bobtail", catArt.builder.normalized(variant), outfit))
                }
            }
        }
    } else {
        for body in bodies {
            let swaps = catArt.builder.body(body)?.earSwaps == true
            for ears in swaps ? catArt.builder.data.ears.map(\.id) : ["own"] {
                var look = base
                look.body = body
                look.weight = body.hasSuffix("_chunky") ? Tuning.Cat.chunkyDefaultWeight : Tuning.Cat.slimDefaultWeight
                look.ears = ears
                rows.append(("\(body)__\(ears)", catArt.builder.normalized(look), nil))
            }
            if catArt.builder.body(body)?.tailSwaps == true {
                var look = base
                look.body = body
                look.weight = body.hasSuffix("_chunky") ? Tuning.Cat.chunkyDefaultWeight : Tuning.Cat.slimDefaultWeight
                look.tail = "bobtail"
                rows.append(("\(body)__bobtail", catArt.builder.normalized(look), nil))
            }
        }
    }

    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let w = CGFloat(cell[0]), h = CGFloat(cell[1]), catHeight = CGFloat(cell[2])
    let size = CGSize(width: w * CGFloat(states.count), height: h)
    // The films tinted once for each look's cats.
    var films: [CatLook: CatNode] = [:]
    let filming = states.contains { if case .film = $0.1 { true } else { false } }
    for (name, look, outfit) in rows {
        let filmed = films[look] ?? CatNode(art: art, rig: rig, catArt: catArt, look: look, height: catHeight)
        if filming, films[look] == nil {
            filmed.loadFilmsNow()
            films = [look: filmed]
        }
        let scene = SKScene(size: size)
        scene.backgroundColor = SKColor(red: 0.62, green: 0.74, blue: 0.82, alpha: 1)
        for (index, (_, state)) in states.enumerated() {
            var kitten = false
            if case .kitten = state {
                kitten = true
            }
            let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, isKitten: kitten, height: catHeight)
            cat.position = CGPoint(x: w * (CGFloat(index) + 0.5), y: h * 0.12)
            scene.addChild(cat)
            cat.wear(outfit)
            switch state {
            case let .stand(view, right):
                cat.show(view, facingRight: right)
                cat.step(0)
            case let .film(view, gait, at, right):
                cat.shareFilms(from: filmed)
                cat.show(view, facingRight: right)
                cat.move(gait)
                let seconds = catArt.film(body: look.body, view: view.rawValue, gait: gait == .run ? "run" : "walk")?.seconds ?? 1
                cat.step(0.001)
                cat.step(seconds * at)
            case let .pose(pose, right):
                cat.show(pose == .sitBack ? .tqfront : .side, facingRight: right)
                cat.settle(into: pose, duration: 0)
                cat.step(0)
            case let .kitten(pose):
                cat.show(.tqfront, facingRight: false)
                cat.settle(into: pose, duration: 0)
                cat.step(0)
            }
            let label = SKShapeNode(rectOf: CGSize(width: 1, height: h))
            label.strokeColor = SKColor(white: 1, alpha: 0.5)
            label.position = CGPoint(x: w * CGFloat(index + 1), y: h / 2)
            scene.addChild(label)
        }
        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        try renderSheetRow(renderer, size: size, device: device, queue: queue, to: out.appendingPathComponent("\(name).png"))
    }
}

private func renderSheetRow(_ renderer: SKRenderer, size: CGSize, device: MTLDevice, queue: MTLCommandQueue, to url: URL) throws {
    let width = Int(size.width), height = Int(size.height)
    let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    description.usage = [.renderTarget, .shaderRead]
    description.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: description))
    renderer.update(atTime: CACurrentMediaTime())
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.62, green: 0.74, blue: 0.82, alpha: 1)
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

/// The still pictures of the cat in its outfit (the plaque's and profile's portrait, the widget's and the Watch's
/// poses), drawn as `WidgetBridge` and `CatScreens.portrait` draw them. HOUSECAT_STILLS=<folder> writes
/// `<outfit>__<body>.png`, a cell a resting pose (each fitted to its cell), for HOUSECAT_FIT_OUTFITS on
/// HOUSECAT_FIT_BODIES in HOUSECAT_FIT_LOOK; `tools/app-assets/fit_sheet.py` stitches them.
@MainActor
@Test func renderTheStillPictures() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let folder = environment["HOUSECAT_STILLS"] else { return }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let root = repo.appendingPathComponent("App/Art")
    let art = try ArtLibrary(root: root)
    let catArt = try CatArt(root: root.appendingPathComponent("cat/custom"))
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let base = catArt.builder.data.presets.first { $0.id == (environment["HOUSECAT_FIT_LOOK"] ?? "ginger_tabby") }?.look ?? .midnight
    let bodies = environment["HOUSECAT_FIT_BODIES"].map { $0.split(separator: ",").map(String.init) } ?? catArt.builder.data.bodies.map(\.id)
    let wanted = environment["HOUSECAT_FIT_OUTFITS"].map { Set($0.split(separator: ",").map(String.init)) }
    let poses = CatPose.allCases
    try poses.map(\.rawValue).joined(separator: "\n").write(to: out.appendingPathComponent("columns.txt"), atomically: true, encoding: .utf8)
    let cellWidth = 260, cellHeight = 230
    for body in bodies {
        var look = base
        look.body = body
        look.weight = body.hasSuffix("_chunky") ? Tuning.Cat.chunkyDefaultWeight : Tuning.Cat.slimDefaultWeight
        look = catArt.builder.normalized(look)
        for outfit in content.outfits.outfits where wanted?.contains(outfit.id) ?? true {
            let context = try #require(CGContext(
                data: nil, width: cellWidth * poses.count, height: cellHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: 0.62, green: 0.74, blue: 0.82, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: cellWidth * poses.count, height: cellHeight))
            for (index, pose) in poses.enumerated() {
                let sprite = catArt.builder.pose(pose.rawValue, look: look)
                guard var image = catArt.image(sprite, look: look) else { continue }
                if outfit.slot == .body {
                    let painting = "poses/cat_\(body)_\(pose.rawValue).png"
                    if let path = OutfitFit.garment(outfit, body: body, pose: pose), art.has(path), let garment = art.image(path) {
                        let frame = GarmentPlacement.frame(drawn: sprite.path, base: painting, catArt: catArt, art: art)
                        image = OutfitFit.dress(image, garment: garment, frame: frame, clipped: sprite.path != painting) ?? image
                    }
                } else if let kind = OutfitFit.kind(outfit), let view = OutfitFit.view(for: pose), let path = outfit.sprites[view],
                          let picture = art.image(path), let shape = OutfitShapes.shape(path, art: art), let face = OutfitFit.restingFace(pose, look: look, catArt: catArt, art: art, for: kind),
                          let dressed = OutfitFit.compose(
                              image, face: face, outfit: picture, shape: shape, kind: kind, view: view, size: outfit.fit,
                              tallEars: OutfitFit.tallEars(look, wearing: outfit), pose: pose, coversEars: OutfitFit.coversEars(outfit)
                          )
                {
                    image = dressed.image
                }
                let scale = min(Double(cellWidth - 12) / Double(image.width), Double(cellHeight - 12) / Double(image.height))
                let w = Double(image.width) * scale, h = Double(image.height) * scale
                context.draw(image, in: CGRect(x: Double(index * cellWidth) + (Double(cellWidth) - w) / 2, y: 6, width: w, height: h))
            }
            let image = try #require(context.makeImage())
            let url = out.appendingPathComponent("\(outfit.id)__\(body).png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}
