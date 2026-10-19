import CoreGraphics
import Foundation
import HouseCatCore
import SpriteKit

/// A blink without new art: each eye in a sprite's features mask is painted shut with the fur just above and below
/// it and a dark lid line curving across, on the tinted sprite. The cat blinks by showing this picture for a moment.
public extension CatArt {
    /// The sprite with its eyes shut, or nil when it shows no eyes (asleep, from behind). Cached per look.
    func blinkTexture(_ sprite: CatBuilder.Sprite, look: CatLook) -> SKTexture? {
        blinkEntry(sprite, look: look) {
            guard let base = image(sprite, look: look), let irises = irisPlanes(sprite.path, width: base.width, height: base.height),
                  let shut = Blink.close(base, irises: irises) else { return BlinkEntry(texture: nil) }
            let texture = SKTexture(cgImage: shut)
            texture.filteringMode = .linear
            return BlinkEntry(texture: texture)
        }.texture
    }

    /// The two irises' planes (R and G of the features mask) at the sprite's size, top row first.
    private func irisPlanes(_ path: String, width: Int, height: Int) -> [[UInt8]]? {
        guard let raster = Raster.read(root.appendingPathComponent("masks/features/\(path)")), raster.planes.count >= 2 else {
            return nil
        }
        return raster.planes.prefix(2).map { plane in
            raster.width == width && raster.height == height
                ? plane
                : Raster.scaled(plane, from: (raster.width, raster.height), to: (width, height))
        }
    }
}

/// A cached blink picture (or the knowledge that a sprite has none).
struct BlinkEntry {
    var texture: SKTexture?
}

enum Blink {
    /// The image with each iris in `irises` (planes the image's size, top row first) painted shut.
    static func close(_ image: CGImage, irises: [[UInt8]]) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 2, h > 2, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let made: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            let p = buffer.bindMemory(to: UInt8.self)
            var shutAny = false
            for plane in irises where plane.count == w * h {
                if shut(eye: plane, pixels: p, width: w, height: h) {
                    shutAny = true
                }
            }
            return shutAny ? context.makeImage() : nil
        }
        return made
    }

    /// Paints one eye shut in place (premultiplied RGBA, top row first); false when the plane has no eye in it.
    private static func shut(eye plane: [UInt8], pixels p: UnsafeMutableBufferPointer<UInt8>, width w: Int, height h: Int) -> Bool {
        var minX = w, maxX = -1, minY = h, maxY = -1, count = 0
        var sx = 0.0, sy = 0.0
        for y in 0 ..< h {
            let row = y * w
            for x in 0 ..< w where plane[row + x] > 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                sx += Double(x)
                sy += Double(y)
                count += 1
            }
        }
        guard count >= 12 else { return false }
        let cx = sx / Double(count), cy = sy / Double(count)
        // The iris with its dark rim and a little of the eye's corners.
        let rx = Double(maxX - minX + 1) / 2 * 1.32 + 1, ry = Double(maxY - minY + 1) / 2 * 1.4 + 1

        /// The average colour (straight, 0–1) of the opaque pixels in a band of rows.
        func average(rows: ClosedRange<Double>) -> SIMD3<Double>? {
            var sum = SIMD3<Double>(repeating: 0), n = 0.0
            let y0 = max(0, Int(rows.lowerBound)), y1 = min(h - 1, Int(rows.upperBound))
            let x0 = max(0, Int(cx - rx)), x1 = min(w - 1, Int(cx + rx))
            guard y0 <= y1, x0 <= x1 else { return nil }
            for y in y0 ... y1 {
                for x in x0 ... x1 {
                    let i = (y * w + x) * 4
                    let a = Double(p[i + 3])
                    guard a > 240, plane[y * w + x] < 40 else { continue }
                    sum += SIMD3(Double(p[i]), Double(p[i + 1]), Double(p[i + 2])) / a
                    n += 1
                }
            }
            return n > 4 ? sum / n : nil
        }
        let above = average(rows: (cy - ry * 2.1) ... (cy - ry * 1.3))
        let below = average(rows: (cy + ry * 1.3) ... (cy + ry * 1.9))
        guard let fur = above.map({ a in below.map { a * 0.65 + $0 * 0.35 } ?? a }) ?? below else { return false }
        let lum = 0.299 * fur.x + 0.587 * fur.y + 0.114 * fur.z
        // The lid line: darker than the fur; on a very dark coat a touch lighter, so it still reads.
        let seam = lum < 0.18 ? fur * 0.55 + SIMD3(repeating: 0.06) : fur * 0.36

        let y0 = max(0, Int(cy - ry * 1.25)), y1 = min(h - 1, Int(cy + ry * 1.25))
        let x0 = max(0, Int(cx - rx * 1.25)), x1 = min(w - 1, Int(cx + rx * 1.25))
        guard y0 <= y1, x0 <= x1 else { return false }
        for y in y0 ... y1 {
            for x in x0 ... x1 {
                let i = (y * w + x) * 4
                let a = Double(p[i + 3]) / 255
                guard a > 0.01 else { continue }
                let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
                let cover = min(1, max(0, (1.12 - (dx * dx + dy * dy).squareRoot()) / 0.25))
                guard cover > 0 else { continue }
                // The closed lid curves down a little in the middle, fading out at the corners.
                let curve = cy + ry * 0.2 * (1 - dx * dx)
                let near = abs(Double(y) - curve)
                let line = max(0, 1 - near / max(0.8, ry * 0.17)) * min(1, max(0, (1 - abs(dx)) / 0.18))
                let shade = 1 - 0.14 * max(0, 1 - near / ry)
                // The fur's own texture, borrowed from just above the eye, over its average colour.
                var lid = fur
                let sy = y - Int(ry * 2.4)
                if sy >= 0 {
                    let j = (sy * w + x) * 4
                    let sa = Double(p[j + 3])
                    let cloned = SIMD3(Double(p[j]), Double(p[j + 1]), Double(p[j + 2])) / max(1, sa)
                    let off = cloned - fur
                    // Only fur like the lid's own (not an ear's pink or a brow's dark mark).
                    if sa > 240, plane[sy * w + x] < 40, (off * off).sum() < 0.03 {
                        lid = cloned * 0.55 + fur * 0.45
                    }
                }
                let colour = (lid * shade) * (1 - line) + seam * line
                for c in 0 ..< 3 {
                    let old = Double(p[i + c]) / 255
                    let new = colour[c] * a
                    p[i + c] = UInt8(max(0, min(255, (old + (new - old) * cover) * 255)))
                }
            }
        }
        return true
    }
}
