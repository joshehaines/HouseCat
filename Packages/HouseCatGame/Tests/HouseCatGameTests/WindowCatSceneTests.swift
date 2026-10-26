import HouseCatCore
@testable import HouseCatGame
import Metal
import SpriteKit
import Testing

/// The cat at a window of the painted exterior (Josh, 20 Oct: "have your cat in the window").
private let art: ArtLibrary? = MainActor.assumeIsolated {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try? ArtLibrary(root: repo.appendingPathComponent("App/Art"))
}

private struct Index: Decodable {
    var doors: [String: [Double]]
    var windows: [String: [[Double]]]
}

@MainActor
private func terrace(_ name: String, size: CGSize, sky: SkyPhase = .day) throws -> ExteriorScene {
    let art = try #require(art)
    let index = try art.data("world/scenes/scenes.json", as: Index.self)
    let door = try #require(index.doors[name])
    let model = ExteriorScene.Model(
        scene: "world/scenes/\(name)",
        sky: sky,
        door: CGPoint(x: door[0], y: door[1]),
        windows: (index.windows[name] ?? []).compactMap(SceneWindow.init)
    )
    return ExteriorScene(size: size, art: art, model: model)
}

@MainActor
private func cat() throws -> CatNode {
    let art = try #require(art)
    return try CatNode(art: art, rig: art.data("cat/rig.json", as: PuppetRig.self), catArt: CatArt(art: art), look: .midnight, height: 100)
}

/// Sitting on the inside sill in the middle of the glass, as tall as `heightShare` of it when it sits up and never
/// wider than `widthShare`, whatever it is doing, on a phone and an iPad.
@MainActor
@Test(arguments: [CGSize(width: 874, height: 402), CGSize(width: 1376, height: 1032)])
func theCatSitsOnTheSillInsideItsWindow(size: CGSize) throws {
    let scene = try terrace("london_terrace_city_autumn", size: size)
    let painting = try #require(scene.childNode(withName: "exterior") as? SKSpriteNode)
    #expect(scene.model.windows.count >= 2)
    for (index, window) in scene.model.windows.enumerated() {
        for pose in WindowPose.allCases {
            let cat = try cat()
            scene.seat(cat, at: WindowSighting(window: index, pose: pose, facingRight: index % 2 == 0), fade: false)
            let crop = try #require(painting.childNode(withName: "windowCat") as? SKCropNode)
            #expect(crop.maskNode != nil)
            let glass = CGSize(width: window.width * painting.size.width, height: window.height * painting.size.height)
            #expect(abs(crop.position.x - (window.middleX - 0.5) * painting.size.width) < 0.5)
            let body = cat.bodyFrame
            #expect(body.width <= glass.width * Tuning.WindowCat.widthShare + 0.5, "\(index) \(pose)")
            #expect(body.height <= glass.height * (Tuning.WindowCat.heightShare + 0.15), "\(index) \(pose)")
            #expect(body.minX >= -glass.width / 2 - 0.5 && body.maxX <= glass.width / 2 + 0.5, "\(index) \(pose): inside the window")
            #expect(abs(cat.position.y + glass.height * (0.5 + Tuning.WindowCat.sillDrop)) < 0.5, "on the sill")
            #expect(scene.windowCat === cat && scene.sighting?.window == index)
        }
    }
    // Gone again.
    scene.seat(nil, at: nil, fade: false)
    #expect(scene.windowCat == nil)
}

/// The crop is the window's own glass: mostly see-through where the panes are, the bars and frame cut out.
@MainActor
@Test func everyTerraceWindowIsCutToItsGlass() throws {
    let art = try #require(art)
    let index = try art.data("world/scenes/scenes.json", as: Index.self)
    // The terrace is bundled in its own town's biome only (the city, every season; 26 Oct).
    let names = index.windows.keys.filter { $0.hasPrefix("london_terrace_city_") && art.has("world/scenes/\($0)_glass.png") }
    #expect(names.count == 4)
    for name in names {
        for numbers in index.windows[name] ?? [] {
            let window = try #require(SceneWindow(numbers))
            let (mask, seat) = try #require(ExteriorScene.windowMask(art.texture("world/scenes/\(name)_glass.png"), window: window), "\(name)")
            #expect(seat > 0.1 && seat < 0.9, "\(name) \(numbers): sits at \(seat)")
            let image = mask.cgImage()
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let clear = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 128 }.count
            let share = Double(clear) / Double(width * height)
            #expect(share > 0.45 && share < 0.98, "\(name) \(numbers): \(share) of it is glass")
        }
    }
}

/// The decorate tray's pictures are small copies decoded when made (21 Oct: a list of HEIC pictures decoded together hung
/// the app on the tray's Shop tab): a HEIC furniture piece and a HEIC wallpaper come back at most the card's size, and
/// the same picture is kept, not made again.
@MainActor
@Test func cardPicturesAreSmallAndKept() throws {
    let art = try #require(art)
    for path in ["furniture/living/furn_living_armchair_R.png", "rooms/walls/wall_attic_pine_planks.png"] {
        #expect(art.has(path), "\(path)")
        let small = try #require(art.thumbnail(path, pixels: Tuning.Stage.cardPicturePixels), "\(path)")
        #expect(max(small.width, small.height) <= Tuning.Stage.cardPicturePixels, "\(path)")
        #expect(max(small.width, small.height) >= Tuning.Stage.cardPicturePixels / 2, "\(path)")
        #expect(art.thumbnail(path, pixels: Tuning.Stage.cardPicturePixels) === small)
        // Plain pixels, redrawn (not ImageIO's picture, which goes back to its HEIC file each time it is drawn).
        #expect(small.alphaInfo == .premultipliedLast && small.bitsPerComponent == 8, "\(path)")
    }
}

/// The tray's pictures are made off the main thread and arrive in batches: none is there before it is asked for, each
/// is there once `ready` has run for the last batch, and asking again while they are on their way makes none twice.
@MainActor
@Test func cardPicturesArriveFromOffTheMainThread() async throws {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let fresh = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let paths = ["furniture/living/furn_living_armchair_R.png", "furniture/living/furn_living_bookcase_R.png",
                 "furniture/living/furn_living_coffee_R.png", "rooms/walls/wall_attic_pine_planks.png"]
    let pixels = Tuning.Stage.cardPicturePixels
    #expect(paths.allSatisfy { fresh.cachedThumbnail($0, pixels: pixels) == nil })
    final class Calls {
        var count = 0
    }
    let calls = Calls()
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        fresh.makeThumbnails(paths, pixels: pixels, batch: 3) {
            calls.count += 1
            if calls.count == 2 {
                done.resume()
            }
        }
        // Asked again on the way: nothing more is made.
        fresh.makeThumbnails(paths, pixels: pixels, batch: 3) {
            calls.count += 100
        }
    }
    #expect(calls.count == 2)
    for path in paths {
        let small = try #require(fresh.cachedThumbnail(path, pixels: pixels), "\(path)")
        #expect(max(small.width, small.height) <= pixels)
    }
}

/// Stills of the cat at a window for judging by eye without a simulator: each scene in each sky, framed as a phone on
/// its side (at twice its points) and a 13-inch iPad frame it, the cat at the window the rules pick for the ground
/// floor (or `HOUSECAT_RENDER_STOREY`), in the pose they pick or `HOUSECAT_RENDER_POSE`.
/// HOUSECAT_RENDER_WINDOW=<folder> [HOUSECAT_RENDER_SCENES=london_terrace_city_autumn,…] [HOUSECAT_RENDER_SKIES=day,night]
/// [HOUSECAT_RENDER_PACK=<home pack>,…] [HOUSECAT_RENDER_LOOK=<preset id>] swift test --filter renderTheCatAtTheWindow
@MainActor
@Test func renderTheCatAtTheWindow() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let folder = environment["HOUSECAT_RENDER_WINDOW"] else { return }
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    for pack in (environment["HOUSECAT_RENDER_PACK"] ?? "").split(separator: ",") {
        try art.add(packAt: URL(fileURLWithPath: String(pack)))
    }
    struct Scenes: Decodable {
        var doors: [String: [Double]]
        var houses: [String: [Double]]
        var windows: [String: [[Double]]]
    }
    let index = try JSONDecoder().decode(Scenes.self, from: Data(contentsOf: repo.appendingPathComponent("assets/world/scenes/scenes.json")))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let look = catArt.builder.data.presets.first { $0.id == environment["HOUSECAT_RENDER_LOOK"] }?.look ?? .midnight
    let names = (environment["HOUSECAT_RENDER_SCENES"] ?? "london_terrace_city_autumn").split(separator: ",").map(String.init)
    let skies = (environment["HOUSECAT_RENDER_SKIES"] ?? "day,night").split(separator: ",").compactMap { SkyPhase(rawValue: String($0)) }
    let storey = environment["HOUSECAT_RENDER_STOREY"].flatMap(Int.init) ?? 0
    let pose = environment["HOUSECAT_RENDER_POSE"].flatMap { WindowPose(rawValue: $0) }
    for name in names {
        let door = index.doors[name] ?? [0.39, 0.62]
        let house = index.houses[name].map { CGRect(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) }
        let windows = (index.windows[name] ?? []).compactMap(SceneWindow.init)
        for sky in skies {
            let context = WindowCatRules.Context(storey: storey, storeys: 3, activity: nil, sky: sky)
            guard var sighting = WindowCatRules.sighting(windows: windows, context: context, household: 3, day: GameDay(index: 0), minutes: 600)
            else { continue }
            sighting.pose = pose ?? sighting.pose
            for (device, size) in [("phone", CGSize(width: 1748, height: 804)), ("pad", CGSize(width: 1376, height: 1032))] {
                let model = ExteriorScene.Model(
                    scene: "world/scenes/\(name)", sky: sky, door: CGPoint(x: door[0], y: door[1]), house: house, windows: windows
                )
                let scene = ExteriorScene(size: size, art: art, model: model)
                scene.seat(CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 100), at: sighting, fade: false)
                try windowStill(scene, to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)_\(sky.rawValue)_\(device).png"))
            }
        }
    }
}

/// One frame of the scene as a PNG, after a second of updates (the cat breathing, the weather falling).
@MainActor
private func windowStill(_ scene: SKScene, to url: URL) throws {
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
    for frame in 0 ..< 30 {
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
