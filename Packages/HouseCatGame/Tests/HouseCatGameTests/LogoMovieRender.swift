import AVFoundation
import CoreGraphics
import Foundation
import HouseCatCore
@testable import HouseCatGame
import Metal
import QuartzCore
import SpriteKit
import Testing
import VideoToolbox

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Renders the launch's telling of the logo to a short HEVC film with transparency, played on the launch curtain
/// (the app is busy building the home then, and a film plays on whatever the main thread is doing; a SpriteKit scene
/// would stand still). Runs only when asked, from tools/app-assets/build_logo_movie.sh:
/// HOUSECAT_RENDER_LOGO=<folder> swift test --filter renderTheLaunchLogo
@MainActor
@Test func renderTheLaunchLogo() async throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_LOGO"] else { return }
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let film = Tuning.Logo.self
    for ink in [LogoScene.Ink.light, .dark] {
        let scene = LogoScene(size: CGSize(width: 1, height: 1), art: art, rig: rig, ink: ink, act: .launch)
        let box = CGSize(width: film.filmBoxWidth, height: film.filmBoxWidth * film.boxSize[1] / film.boxSize[0])
        let size = CGSize(
            width: (box.width * (film.filmLeft + film.filmRight)).rounded(.up),
            height: (box.height * film.filmHeight).rounded(.up)
        )
        scene.size = size
        scene.scaleMode = .fill
        scene.box = CGRect(x: box.width * film.filmLeft, y: 0, width: box.width, height: box.height)
        let name = ink == .light ? "launch_logo_light.mov" : "launch_logo_dark.mov"
        let writer = try record(scene, size: size, to: URL(fileURLWithPath: folder).appendingPathComponent(name))
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(writer.error.map(String.init(describing:)) ?? "")")
    }
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
