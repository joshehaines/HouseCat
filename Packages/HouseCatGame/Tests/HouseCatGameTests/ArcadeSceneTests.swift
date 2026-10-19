import CoreGraphics
import Foundation
import HouseCatCore
@testable import HouseCatGame
import ImageIO
import Metal
import SpriteKit
import Testing
import UniformTypeIdentifiers

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

@MainActor
private func kit() throws -> (ArtLibrary, CatArt, PuppetRig) {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    return try (art, CatArt(art: art), art.data("cat/rig.json", as: PuppetRig.self))
}

private func content() throws -> ArcadeContent {
    try ArcadeContent.load(from: repo.appendingPathComponent("Content"))
}

/// Draws `scene` off screen to PNGs at the given seconds (no simulator), for judging the games by eye:
/// HOUSECAT_RENDER_ARCADE=<folder> swift test --filter renderTheArcade
@MainActor
private func stills(_ scene: SKScene, size: CGSize, at seconds: [Double], name: String, folder: URL, start: () -> Void) throws {
    let scale = 2.0
    let width = Int(size.width * scale), height = Int(size.height * scale)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let renderer = SKRenderer(device: device)
    renderer.scene = scene
    let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    description.usage = [.renderTarget, .shaderRead]
    description.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: description))
    let fps = 60.0
    let t0 = CACurrentMediaTime() + 1
    start()
    var frame = 0
    for (n, second) in seconds.enumerated() {
        while Double(frame) / fps < second {
            renderer.update(atTime: t0 + Double(frame) / fps)
            frame += 1
        }
        renderer.update(atTime: t0 + Double(frame) / fps)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.95, green: 0.9, blue: 0.82, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        let commands = try #require(queue.makeCommandBuffer())
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands, renderPassDescriptor: pass)
        commands.commit()
        commands.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let context = try #require(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        let image = try #require(context.makeImage())
        let url = folder.appendingPathComponent("\(name)_\(n).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

@MainActor
@Test func renderTheArcade() throws {
    guard let path = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_ARCADE"] else { return }
    let folder = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let only = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_ONLY"]
    let (art, catArt, rig) = try kit()
    let phone = CGSize(width: 956, height: 440)
    let look = CatLook.midnight
    if only == nil || only == "zoomies" {
        let scene = ZoomiesScene(size: phone, seed: DaySeed(household: 3, day: GameDay(index: 20380), purpose: "zoomies"), art: art,
                                 catArt: catArt, rig: rig, look: look)
        scene.autoplay = true
        try stills(scene, size: phone, at: [0.5, 3, 8, 20, 45], name: "zoomies", folder: folder) { scene.start() }
    }
    let arcade = try content()
    if only == nil || only == "catapult" {
        for id in [0, 7, 19, 33, 45, 59, 66, 79] {
            let scene = CatapultScene(size: phone, level: arcade.catapult.levels[id], art: art, catArt: catArt, rig: rig, look: look)
            scene.autoplay = true
            try stills(scene, size: phone, at: [0.2, 1.4, 4], name: "catapult\(id)", folder: folder) {}
        }
    }
    if only == nil || only == "match" {
        let board = CGSize(width: 520, height: 440)
        for id in [0, 14, 26, 31, 59] {
            let scene = MatchScene(size: board, level: arcade.match.levels[id], seed: DaySeed(household: 3, day: GameDay(index: id), purpose: "m"),
                                   art: art)
            scene.autoplay = true
            try stills(scene, size: board, at: [0.1, 2.0, 5.0], name: "match\(id)", folder: folder) {}
        }
    }
}

/// Frames for GIFs of the games playing themselves: HOUSECAT_FILM_ARCADE=<folder> swift test --filter filmTheArcade
/// (then tools/content/gif.py or Pillow joins them).
@MainActor
@Test func filmTheArcade() throws {
    guard let path = ProcessInfo.processInfo.environment["HOUSECAT_FILM_ARCADE"] else { return }
    let folder = URL(fileURLWithPath: path)
    let only = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_ONLY"]
    let (art, catArt, rig) = try kit()
    let phone = CGSize(width: 956, height: 440)
    let fps = 12.0
    func film(_ scene: SKScene, size: CGSize, name: String, from: Double, seconds: Double, start: () -> Void) throws {
        let sub = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let times = stride(from: from, to: from + seconds, by: 1 / fps).map { $0 }
        try stills(scene, size: size, at: times, name: "f", folder: sub, start: start)
    }
    if only == nil || only == "zoomies" {
        let scene = ZoomiesScene(size: phone, seed: DaySeed(household: 4, day: GameDay(index: 20380), purpose: "zoomies"), art: art,
                                 catArt: catArt, rig: rig, look: .midnight)
        scene.autoplay = true
        try film(scene, size: phone, name: "zoomies", from: 6, seconds: 6) { scene.start() }
    }
    let arcade = try content()
    if only == nil || only == "catapult" {
        let scene = CatapultScene(size: phone, level: arcade.catapult.levels[5], art: art, catArt: catArt, rig: rig, look: .midnight)
        scene.autoplay = true
        try film(scene, size: phone, name: "catapult", from: 0.5, seconds: 5) {}
    }
    if only == nil || only == "match" {
        let board = CGSize(width: 520, height: 440)
        let scene = MatchScene(size: board, level: arcade.match.levels[12], seed: DaySeed(household: 3, day: GameDay(index: 12), purpose: "m"),
                               art: art)
        scene.autoplay = true
        try film(scene, size: board, name: "match", from: 0.5, seconds: 6) {}
    }
}

@MainActor
@Test func aZoomiesRunPlaysItselfWithoutABump() throws {
    let (art, catArt, rig) = try kit()
    let scene = ZoomiesScene(size: CGSize(width: 956, height: 440), seed: DaySeed(household: 3, day: GameDay(index: 20380), purpose: "zoomies"),
                             art: art, catArt: catArt, rig: rig, look: .midnight)
    scene.autoplay = true
    scene.start()
    var finished = false
    scene.onFinish = { _ in finished = true }
    let t0 = 1000.0
    for frame in 0 ..< 60 * 30 {
        scene.update(t0 + Double(frame) / 60)
    }
    #expect(!finished)
    #expect(scene.run.distance > 180)
    #expect(scene.run.biscuits > 10)
}

@MainActor
@Test func aCatapultLevelPlaysItsSolutionToAWin() throws {
    let (art, catArt, rig) = try kit()
    let arcade = try content()
    for id in [0, 13, 47] {
        let level = arcade.catapult.levels[id]
        let scene = CatapultScene(size: CGSize(width: 956, height: 440), level: level, art: art, catArt: catArt, rig: rig, look: .midnight)
        scene.autoplay = true
        // The beats come straight from the game (the finish card waits on an action, which needs a view to run).
        var over = false
        scene.onBeat = { beat in
            switch beat {
            case .won, .lost: over = true
            default: break
            }
        }
        let t0 = 1000.0
        for frame in 0 ..< 60 * 40 where !over {
            scene.update(t0 + Double(frame) / 60)
        }
        #expect(scene.game.won, "level \(id)")
        #expect(scene.game.stars == 3, "level \(id)")
    }
}
