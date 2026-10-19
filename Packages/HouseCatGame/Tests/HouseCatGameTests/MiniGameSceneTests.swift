import AVFoundation
import HouseCatCore
@testable import HouseCatGame
import Metal
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

@MainActor
private func miniGame(_ id: String, size: CGSize = CGSize(width: 956, height: 440), personality: Personality = .velcro) throws -> MiniGameScene {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    var seed = DaySeed(household: 11, day: GameDay(index: 40), purpose: "minigame", salt: "\(id).0")
    let duration = Tuning.MiniGames.roundSeconds
    let game: MiniGameScene.Game = switch id {
    case "knock_it_off": .knock(KnockItOff(duration: duration, personality: personality, seed: &seed))
    case "string_chase": .string(StringChase(duration: duration, personality: personality, seed: &seed))
    case "hide_and_seek": .hide(HideAndSeek(duration: duration, personality: personality, seed: &seed))
    default: .laser(LaserChase(duration: duration, personality: personality, seed: &seed))
    }
    let scene = MiniGameScene(
        size: size,
        game: game,
        art: art,
        catArt: catArt,
        rig: rig,
        look: .midnight,
        floor: "rooms/floors/floor_living_herringbone.png",
        wall: "rooms/walls/wall_living_cream_wash.png",
        objects: Tuning.MiniGames.shelfThings.map { "gifts/\($0).png" },
        catnip: "gifts/\(Tuning.MiniGames.catnip).png"
    )
    scene.autoplay = true
    return scene
}

/// Every game, playing itself as the steady player does, runs its 20 seconds to the end, with hits, a combo at its
/// top and the catnip on the way, and the score the scene reports is the game's.
@MainActor
@Test(arguments: ["laser_pointer", "knock_it_off", "string_chase", "hide_and_seek"])
func theGamesPlayThemselvesToTheEnd(_ id: String) throws {
    let scene = try miniGame(id)
    var beats: [PlayBeat] = []
    var finished: Double?
    scene.onBeat = { beats.append($0) }
    scene.onFinish = { finished = $0 }
    scene.start()
    var t = 100.0
    while finished == nil, t < 130 {
        scene.update(t)
        t += 1.0 / 60
    }
    let score = try #require(finished)
    #expect(score == scene.game.score)
    #expect(t - 100 < Tuning.MiniGames.roundSeconds + 0.5)
    #expect(beats.contains { if case let .scored(hit) = $0 { Combo.worth(hit.combo) == Tuning.MiniGames.comboCap } else { false } })
    #expect(beats.contains { if case .zoomies = $0 { true } else { false } })
}

/// Films of the games playing themselves, drawn off screen (no simulator), for judging the feel by eye.
/// HOUSECAT_RENDER_GAMES=<folder> [HOUSECAT_RENDER_GAME=<id>] swift test --filter renderTheMiniGames
@MainActor
@Test func renderTheMiniGames() throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_GAMES"] else { return }
    let only = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_GAME"]
    for id in ["laser_pointer", "knock_it_off", "string_chase", "hide_and_seek"] where only == nil || only == id {
        let size = CGSize(width: 1280, height: 590)
        let scene = try miniGame(id, size: size)
        try film(scene, size: size, seconds: Tuning.MiniGames.roundSeconds + 1.5, to: URL(fileURLWithPath: folder).appendingPathComponent("\(id).mp4"))
    }
}

@MainActor
private func film(_ scene: MiniGameScene, size: CGSize, seconds: Double, to url: URL) throws {
    let width = Int(size.width), height = Int(size.height)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let renderer = SKRenderer(device: device)
    renderer.scene = scene
    let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    description.usage = [.renderTarget, .shaderRead]
    description.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: description))
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    let fps = 30
    let start = CACurrentMediaTime() + 1
    scene.start()
    for frame in 0 ..< Int(seconds * Double(fps)) {
        renderer.update(atTime: start + Double(frame) / Double(fps))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        let commands = try #require(queue.makeCommandBuffer())
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands, renderPassDescriptor: pass)
        commands.commit()
        commands.waitUntilCompleted()
        var buffer: CVPixelBuffer?
        try CVPixelBufferPoolCreatePixelBuffer(nil, #require(adaptor.pixelBufferPool), &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        try target.getBytes(
            #require(CVPixelBufferGetBaseAddress(pixels)),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        CVPixelBufferUnlockBaseAddress(pixels, [])
        while !input.isReadyForMoreMediaData {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) let finishing = writer
    finishing.finishWriting { done.signal() }
    while done.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    #expect(writer.status == .completed)
}
