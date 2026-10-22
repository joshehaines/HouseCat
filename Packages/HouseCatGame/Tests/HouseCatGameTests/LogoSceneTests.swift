import CoreGraphics
import Foundation
import HouseCatCore
@testable import HouseCatGame
import ImageIO
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// The scene with the wordmark's box at a known place, as the app lays it out.
@MainActor
private func logo(_ act: LogoScene.Act) throws -> LogoScene {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let scene = LogoScene(size: CGSize(width: 1200, height: 500), art: art, rig: rig, ink: .dark, act: act)
    scene.box = CGRect(x: 400, y: 20, width: 400, height: 400 * Tuning.Logo.boxSize[1] / Tuning.Logo.boxSize[0])
    return scene
}

/// Where the cat's feet are, in the box's pixels.
@MainActor
private func feet(_ scene: LogoScene) -> CGPoint {
    let point = scene.convert(CGPoint.zero, from: scene.cat)
    let scale = scene.box.width / Tuning.Logo.boxSize[0]
    return CGPoint(x: (point.x - scene.box.minX) / scale, y: (point.y - scene.box.minY) / scale)
}

/// The logo's whole story plays out (Josh, 22 Oct: the cat walks in and sits beside the wordmark, like the horizontal
/// logo): it comes in from the left and ends sitting facing you on its spot.
@MainActor
@Test(arguments: [LogoScene.Act.launch, .intro])
func theCatWalksInAndSitsBesideTheWordmark(act: LogoScene.Act) throws {
    let scene = try logo(act)
    #expect(!scene.asleep)
    #expect(feet(scene).x < 0, "it starts off to the left")
    var time = 0.0
    while time < 20, !scene.asleep {
        scene.update(time)
        time += 1.0 / 30
    }
    #expect(scene.asleep, "settled")
    #expect(scene.cat.pose == .sitFront)
    #expect(time < 9, "sitting in good time (\(time) s)")
    let end = feet(scene)
    #expect(abs(end.x - Tuning.Logo.beside) < 1 && abs(end.y - Tuning.Logo.baseline) < 1, "on its spot: \(end)")
}

/// Reduce Motion: sitting on its spot from the first frame.
@MainActor
@Test func reduceMotionStartsSitting() throws {
    let scene = try logo(.still)
    scene.update(0)
    #expect(scene.asleep)
    #expect(scene.cat.pose == .sitFront)
    let end = feet(scene)
    #expect(abs(end.x - Tuning.Logo.beside) < 1 && abs(end.y - Tuning.Logo.baseline) < 1)
}

/// The letters' tops the cat lands on and casts its shadow on are where the wordmark's ink is: a re-cut wordmark
/// must bring its measurements with it.
@Test func theLetterTopsMatchTheWordmark() throws {
    let url = repo.appendingPathComponent("assets/brand/logo/wordmark_on_light.png")
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(Double(image.width) == Tuning.Logo.boxSize[0] && Double(image.height) == Tuning.Logo.boxSize[1])
    let width = image.width, height = image.height
    var alpha = [UInt8](repeating: 0, count: width * height)
    let context = try #require(CGContext(
        data: &alpha, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    // The highest ink in a column, in pixels up from the bottom (rows run top down in the buffer).
    func top(_ x: Int) -> Int? {
        (0 ..< height).first { alpha[$0 * width + x] > 128 }.map { height - $0 }
    }
    for span in Tuning.Logo.tops {
        let highest = (Int(span[0]) ... Int(span[1])).compactMap(top).max() ?? 0
        #expect(abs(Double(highest) - span[2]) < 12, "letter top at \(span[0])-\(span[1]): ink to \(highest), said \(span[2])")
    }
    let lowest = (0 ..< width).compactMap { x in (0 ..< height).last { alpha[$0 * width + x] > 128 }.map { height - $0 } }
    let baseline = lowest.sorted()[lowest.count / 2]
    #expect(abs(Double(baseline) - Tuning.Logo.baseline) < 6, "baseline at \(baseline)")
}
