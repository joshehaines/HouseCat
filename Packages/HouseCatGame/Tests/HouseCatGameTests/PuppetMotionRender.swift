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
/// and HOUSECAT_TINT_PIECES colours each leg's pieces.
@MainActor
@Test func renderThePuppetsMovement() throws {
    guard let folder = ProcessInfo.processInfo.environment["HOUSECAT_RENDER_PUPPET"] else { return }
    let out = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(root: repo.appendingPathComponent("App/Art/cat/custom"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let presetID = ProcessInfo.processInfo.environment["HOUSECAT_PUPPET_LOOK"]
    CatNode.profileEars = ProcessInfo.processInfo.environment["HOUSECAT_OLD_EARS"] == nil
    defer { CatNode.profileEars = true }
    let look = catArt.builder.data.presets.first { $0.id == presetID }?.look ?? .midnight
    let size = CGSize(width: 720, height: 560)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let gaits: [(String, CatNode.Gait)] = [("walk", .walk), ("trot", .trot), ("run", .run)]
    for view in CatNode.View.allCases {
        for (gaitName, gait) in gaits {
            let scene = SKScene(size: size)
            scene.backgroundColor = SKColor(red: 0.93, green: 0.88, blue: 0.78, alpha: 1)
            let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 420)
            cat.position = CGPoint(x: size.width / 2, y: 60)
            scene.addChild(cat)
            cat.show(view, facingRight: false)
            cat.move(gait)
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
            let frames = Int((1.5 / hz) * 30)
            let start = CACurrentMediaTime() + 1
            for frame in 0 ..< frames {
                cat.step(1.0 / 30)
                let url = out.appendingPathComponent(String(format: "%@_%@_%03d.png", view.rawValue, gaitName, frame))
                try render(renderer, scene: scene, size: size, time: start + Double(frame) / 30, device: device, queue: queue, to: url)
            }
        }
    }
}

private func render(
    _ renderer: SKRenderer,
    scene _: SKScene,
    size: CGSize,
    time: TimeInterval,
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
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.93, green: 0.88, blue: 0.78, alpha: 1)
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
