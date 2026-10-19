import AVFoundation
import CoreGraphics
import Foundation
import HouseCatCore
@testable import HouseCatGame
import ImageIO
import Metal
import QuartzCore
import SpriteKit
import Testing
import VideoToolbox

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Renders the logo's films, HEVC with transparency: the launch's telling (light and dark), played on the launch curtain
/// (the app is busy building the home then, and a film plays on whatever the main thread is doing; a SpriteKit scene
/// would stand still), and the intro's (over the night sky). With HOUSECAT_CURL_FRAMES (the curl film's keyed frames,
/// tools/asset-pipeline/logo/curlkey.py) the cat lands and curls up as in that film. Runs only when asked, from
/// tools/app-assets/build_logo_film.sh: HOUSECAT_RENDER_LOGO=<folder> swift test --filter renderTheLogoFilms
@MainActor
@Test func renderTheLogoFilms() async throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_LOGO"] else { return }
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let curl = try ProcessInfo.processInfo.environment["HOUSECAT_CURL_FRAMES"].map(curlFrames)
    let film = Tuning.Logo.self
    let films: [(LogoScene.Act, LogoScene.Ink, String)] = [
        (.launch, .light, "launch_logo_light.mov"),
        (.launch, .dark, "launch_logo_dark.mov"),
        (.intro, .dark, "intro_logo.mov"),
    ]
    for (act, ink, name) in films {
        let scene = LogoScene(size: CGSize(width: 1, height: 1), art: art, rig: rig, ink: ink, act: act)
        if let curl {
            scene.curlFrames = curl.frames
            scene.curlFrameRate = curl.rate
        }
        let box = CGSize(width: film.filmBoxWidth, height: film.filmBoxWidth * film.boxSize[1] / film.boxSize[0])
        let size = CGSize(
            width: (box.width * (film.filmLeft + film.filmRight)).rounded(.up),
            height: (box.height * film.filmHeight).rounded(.up)
        )
        scene.size = size
        scene.scaleMode = .fill
        scene.box = CGRect(x: box.width * film.filmLeft, y: 0, width: box.width, height: box.height)
        let writer = try record(scene, size: size, to: URL(fileURLWithPath: folder).appendingPathComponent(name))
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(writer.error.map(String.init(describing:)) ?? "")")
    }
}

/// The curl film's keyed frames, in order, and their rate (fps.txt beside them).
@MainActor
private func curlFrames(_ folder: String) throws -> (frames: [SKTexture], rate: Double) {
    let url = URL(fileURLWithPath: folder)
    let names = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".png") }.sorted()
    let frames = try names.map { name -> SKTexture in
        let source = try #require(CGImageSourceCreateWithURL(url.appendingPathComponent(name) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }
    let rate = try Double(String(contentsOf: url.appendingPathComponent("fps.txt"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 24
    #expect(!frames.isEmpty)
    return (frames, rate)
}

/// Plays the scene through an offscreen renderer at the film's frame rate and writes each frame; the caller finishes
/// the writing.
@MainActor
private func record(_ scene: LogoScene, size: CGSize, to url: URL) throws -> AVAssetWriter {
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
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoQualityKey: Tuning.Logo.filmQuality,
            kVTCompressionPropertyKey_TargetQualityForAlpha as String: Tuning.Logo.filmQuality,
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha as String,
        ],
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

    let fps = Tuning.Logo.filmFPS
    // The renderer's clock must run on from the system's (it stamps its first update with it, and stops at a time
    // before that).
    let start = CACurrentMediaTime() + 1
    var frame = 0
    // Until the cat is asleep, and a breath after (the film holds its last frame).
    var after = 0
    while after < Int(Tuning.Logo.filmTail * Double(fps)), frame < fps * 10 {
        renderer.update(atTime: start + Double(frame) / Double(fps))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
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
        frame += 1
        if scene.asleep {
            after += 1
        }
    }
    input.markAsFinished()
    return writer
}

/// The first and last frames for the curl's generated film (Higgsfield, Kling 3.0: the cat landed on the letters, and
/// curled up asleep there), from the game's own paintings on flat chroma green with a dark ledge for the letter tops,
/// so the film starts and ends exactly on the art. HOUSECAT_RENDER_CURL_FRAMES=<folder> swift test --filter
/// renderTheCurlKeyframes
@MainActor
@Test func renderTheCurlKeyframes() throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_CURL_FRAMES"] else { return }
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let k = CurlFrames.self
    for (name, curled) in [("curl_start", false), ("curl_end", true)] {
        let scene = SKScene(size: CGSize(width: k.width, height: k.height))
        scene.backgroundColor = SKColor(red: k.green[0], green: k.green[1], blue: k.green[2], alpha: 1)
        let ledge = SKSpriteNode(
            color: SKColor(red: k.ink[0], green: k.ink[1], blue: k.ink[2], alpha: 1),
            size: CGSize(width: k.width, height: k.feetY)
        )
        ledge.anchorPoint = .zero
        scene.addChild(ledge)
        let cat = CatNode(art: art, rig: rig, height: k.catHeight)
        cat.childNode(withName: "shadow")?.isHidden = true
        cat.position = CGPoint(x: k.width / 2, y: k.feetY)
        cat.show(.side, facingRight: true)
        if curled {
            cat.settle(into: .sleepCurl, duration: 0)
            cat.setScale(CGFloat(Tuning.Logo.curlScale))
        }
        scene.addChild(cat)
        try still(scene, to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }
}

/// The curl film's frame: 1920 x 1080, the cat standing as tall as 620 pixels with its feet on the ledge.
private enum CurlFrames {
    static let width: CGFloat = 1920
    static let height: CGFloat = 1080
    static let feetY: CGFloat = 300
    static let catHeight: CGFloat = 620
    static let green: [CGFloat] = [0, 0.69, 0.25]
    static let ink: [CGFloat] = [0.18, 0.16, 0.2]
}

/// One frame of a scene as a PNG (actions run once, so a pose's fade-in has happened).
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
    for frame in 0 ..< 3 {
        renderer.update(atTime: start + Double(frame) / 30)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        // The renderer does not draw the scene's background colour; the pass clears to it.
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
