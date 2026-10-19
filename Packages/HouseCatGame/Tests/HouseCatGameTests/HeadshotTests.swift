import CoreGraphics
import Foundation
@testable import HouseCatCore
@testable import HouseCatGame
import ImageIO
import Testing
import UniformTypeIdentifiers

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// The picture's alpha, a byte a pixel, rows from the top.
private func alpha(_ image: CGImage) throws -> [UInt8] {
    var alpha = [UInt8](repeating: 0, count: image.width * image.height)
    let context = try #require(CGContext(
        data: &alpha, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return alpha
}

/// The badge's headshot shows the whole head for every preset: the ear tips a little below the top and inside the
/// ring, and the face filling the middle. HOUSECAT_HEADSHOTS=<folder> writes them out to look at.
@Test func theHeadshotKeepsTheEarsInsideTheRing() throws {
    let art = try CatArt(root: repo.appendingPathComponent("App/Art/cat/custom"))
    let size = 128
    let folder = ProcessInfo.processInfo.environment["HOUSECAT_HEADSHOTS"].map { URL(fileURLWithPath: $0) }
    for preset in art.builder.data.presets {
        let sprite = art.builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: preset.look)
        let image = try #require(art.image(sprite, look: preset.look))
        let shot = try #require(Headshot.cut(image, face: art.face(sprite.path), size: size))
        let ink = try alpha(shot)
        let top = (0 ..< size).first { row in (0 ..< size).contains { ink[row * size + $0] > 40 } } ?? 0
        #expect(top >= size / 20 && top <= size / 5, "\(preset.id): the ears start \(top) px down")
        // In the top half, nothing of the cat outside the ring (a circle filling the square).
        let radius = Double(size) / 2
        var outside = 0
        for row in 0 ..< size / 2 {
            for column in 0 ..< size where ink[row * size + column] > 40 {
                let dx = Double(column) + 0.5 - radius
                let dy = Double(row) + 0.5 - radius
                if (dx * dx + dy * dy).squareRoot() > radius {
                    outside += 1
                }
            }
        }
        #expect(outside < size / 8, "\(preset.id): \(outside) px of the head outside the ring")
        #expect(ink[size / 2 * size + size / 2] > 200, "\(preset.id): the face is in the middle")
        if let folder, let out = CGImageDestinationCreateWithURL(
            folder.appendingPathComponent("headshot_\(preset.id).png") as CFURL, UTType.png.identifier as CFString, 1, nil
        ) {
            CGImageDestinationAddImage(out, shot, nil)
            CGImageDestinationFinalize(out)
        }
    }
}
