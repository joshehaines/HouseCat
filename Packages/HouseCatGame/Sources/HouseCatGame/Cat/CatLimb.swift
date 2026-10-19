import CoreGraphics
import Foundation

/// A painted leg made into two pieces jointed at its hock (a hind leg) or wrist (a front leg), so it can bend as it
/// steps and its paw can stay put on the floor (Josh, 19 Oct: the back legs looked strange moving sideways; they
/// swung from the hip as one stiff piece, the paw sliding through an arc). Found from the leg's own outline, so it
/// works for every body, breed and coat without new paintings.
enum CatLimb {
    /// Where a leg bends and where it stands, as fractions of its picture (origin top left), and how far round the
    /// joint the two pieces overlap (a fraction of the picture's height).
    struct Joints: Equatable {
        var knee: CGPoint
        var foot: CGPoint
        var radius: CGFloat
    }

    /// The leg's joint: on a hind leg the hock, the point of its outline's centre line furthest off the line from hip
    /// to paw (painted as a bend); on a straight front leg, the wrist, a little over halfway down. The foot is the
    /// middle of the paw's sole.
    static func joints(of image: CGImage) -> Joints? {
        let width = image.width, height = image.height
        guard width > 2, height > 8, let alpha = alphaPlane(image) else { return nil }
        var centre = [CGFloat?](repeating: nil, count: height)
        var span = [CGFloat](repeating: 0, count: height)
        for row in 0 ..< height {
            var low = -1, high = -1
            for column in 0 ..< width where alpha[row * width + column] > 128 {
                if low < 0 {
                    low = column
                }
                high = column
            }
            if low >= 0 {
                centre[row] = CGFloat(low + high) / 2
                span[row] = CGFloat(high - low)
            }
        }
        guard let top = centre.firstIndex(where: { $0 != nil }), let bottom = centre.lastIndex(where: { $0 != nil }), bottom - top > 8
        else { return nil }
        let length = bottom - top
        func average(_ rows: ClosedRange<Int>) -> CGFloat {
            let values = rows.compactMap { centre[$0] }
            return values.isEmpty ? 0 : values.reduce(0, +) / CGFloat(values.count)
        }
        let hipX = average(top ... top + max(2, length / 20))
        let footX = average(bottom - max(2, length / 30) ... bottom)
        var best: CGFloat = 0, kneeRow = top + Int(Double(length) * 0.62)
        for row in (top + Int(Double(length) * 0.35)) ..< (top + Int(Double(length) * 0.82)) {
            guard let x = centre[row] else { continue }
            let t = CGFloat(row - top) / CGFloat(length)
            let off = x - (hipX + (footX - hipX) * t)
            if abs(off) > abs(best) {
                best = off
                kneeRow = row
            }
        }
        if abs(best) < CGFloat(length) * 0.03 {
            kneeRow = top + Int(Double(length) * 0.62)
        }
        let kneeX = centre[kneeRow] ?? hipX
        let radius = max(span[kneeRow], 2) / 2 * 1.35
        return Joints(
            knee: CGPoint(x: kneeX / CGFloat(width), y: CGFloat(kneeRow) / CGFloat(height)),
            foot: CGPoint(x: footX / CGFloat(width), y: CGFloat(bottom) / CGFloat(height)),
            radius: radius / CGFloat(height)
        )
    }

    /// The leg cut in two at its joint, each the leg's whole picture size: the upper piece above the joint and round
    /// it, its edge below the joint feathered; the lower piece below the joint and round it, hard-edged and drawn
    /// behind. The round overlap is centred on the joint, so the lower piece turning about the joint keeps its edge
    /// under the upper piece: no seam, however far it bends.
    static func split(_ image: CGImage, joints: Joints) -> (upper: CGImage, lower: CGImage)? {
        let width = image.width, height = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: info
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let kx = joints.knee.x * CGFloat(width), ky = joints.knee.y * CGFloat(height)
        let r = joints.radius * CGFloat(height)
        var upper = pixels, lower = pixels
        for row in 0 ..< height {
            // The buffer's rows run top down, as the fractions do.
            let y = CGFloat(row) + 0.5
            for column in 0 ..< width {
                let x = CGFloat(column) + 0.5
                let distance = hypot(x - kx, y - ky)
                let up: CGFloat = if y < ky {
                    1
                } else if distance <= r * 0.8 {
                    1
                } else if distance >= r {
                    0
                } else {
                    1 - smooth((distance - r * 0.8) / (r * 0.2))
                }
                let down: CGFloat = y > ky || distance < r ? 1 : 0
                let index = (row * width + column) * 4
                if up < 1 {
                    for channel in 0 ..< 4 {
                        upper[index + channel] = UInt8(CGFloat(pixels[index + channel]) * up)
                    }
                }
                if down < 1 {
                    for channel in 0 ..< 4 {
                        lower[index + channel] = 0
                    }
                }
            }
        }
        func make(_ bytes: [UInt8]) -> CGImage? {
            var bytes = bytes
            return bytes.withUnsafeMutableBytes { buffer -> CGImage? in
                CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: info
                )?.makeImage()
            }
        }
        guard let top = make(upper), let bottom = make(lower) else { return nil }
        return (top, bottom)
    }

    /// Where the joint goes for the paw to reach `target` from `hip` (two bones `upper` and `lower` long), bending
    /// to the `bend` side (+1 anticlockwise of the hip-to-paw line, -1 clockwise); beyond reach, the leg points at it.
    static func knee(hip: CGPoint, target: CGPoint, upper a: CGFloat, lower b: CGFloat, bend: CGFloat) -> CGPoint {
        let dx = target.x - hip.x, dy = target.y - hip.y
        let reach = max(abs(a - b) + 0.001, min(a + b - 0.001, hypot(dx, dy)))
        let cosine = (a * a + reach * reach - b * b) / (2 * a * reach)
        let angle = atan2(dy, dx) + bend * acos(max(-1, min(1, cosine)))
        return CGPoint(x: hip.x + a * cos(angle), y: hip.y + a * sin(angle))
    }

    /// The torso without the warm rim light painted along its underside: the legs join there, under it, and the bright
    /// edge read as a seam across the top of every leg. Each pixel near the lower edge takes the colour from a little
    /// further in, keeping its own alpha.
    static func softenUnderside(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: info
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let band = max(2, Int(Double(height) * 0.045))
        var out = pixels
        for column in 0 ..< width {
            for row in 0 ..< height {
                let index = (row * width + column) * 4
                let alpha = Int(pixels[index + 3])
                guard alpha > 0 else { continue }
                // Near the underside: clear within `band` rows below.
                let below = min(height - 1, row + band)
                guard pixels[(below * width + column) * 4 + 3] < 40 else { continue }
                let source = max(0, row - band * 2)
                let from = (source * width + column) * 4
                let fromAlpha = Int(pixels[from + 3])
                guard fromAlpha > 200 else { continue }
                for channel in 0 ..< 3 {
                    out[index + channel] = UInt8(Int(pixels[from + channel]) * alpha / fromAlpha)
                }
            }
        }
        return out.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: info
            )?.makeImage()
        }
    }

    private static func smooth(_ t: CGFloat) -> CGFloat {
        let k = max(0, min(1, t))
        return k * k * (3 - 2 * k)
    }

    private static func alphaPlane(_ image: CGImage) -> [UInt8]? {
        var alpha = [UInt8](repeating: 0, count: image.width * image.height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? alpha : nil
    }
}
