import CoreGraphics
import Foundation
import HouseCatCore

/// A painted leg's joints, found from its own outline so it works for every body, breed and coat without new
/// paintings (Josh, 19 Oct: the legs swung from the hip as stiff pieces; then "front legs don't have joints in them";
/// then a full rebuild): where a hind leg bends at the hock, the ankle above its paw, the paw's sole and toe. The leg
/// bends there in one piece (CatSkin), not cut.
enum CatLimb {
    /// Where a leg bends and stands, as fractions of its picture (origin top left): the hock (hind legs only), the
    /// wrist or ankle just above the paw, the middle of the paw's sole and the tip of its toes; and how far round
    /// each joint the pieces overlap (fractions of the picture's height).
    struct Joints: Equatable {
        var hock: CGPoint?
        var hockRadius: CGFloat = 0
        var ankle: CGPoint
        var ankleRadius: CGFloat
        var sole: CGPoint
        var toe: CGPoint
    }

    /// The leg's joints. The hock is the point of the outline's centre line furthest off the line from hip to ankle
    /// (painted as a bend); the ankle (or wrist) the narrowest row above the paw; the toe the paw's front at the
    /// floor (painted facing left: its leftmost point there).
    static func joints(of image: CGImage, hind: Bool) -> Joints? {
        let width = image.width, height = image.height
        guard width > 2, height > 8, let alpha = alphaPlane(image) else { return nil }
        var centre = [CGFloat?](repeating: nil, count: height)
        var span = [CGFloat](repeating: 0, count: height)
        var left = [Int](repeating: width, count: height)
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
                left[row] = low
            }
        }
        guard let top = centre.firstIndex(where: { $0 != nil }), let bottom = centre.lastIndex(where: { $0 != nil }), bottom - top > 8
        else { return nil }
        let length = bottom - top
        func row(_ share: Double) -> Int {
            top + Int(Double(length) * share)
        }
        func average(_ rows: ClosedRange<Int>) -> CGFloat {
            let values = rows.compactMap { centre[$0] }
            return values.isEmpty ? 0 : values.reduce(0, +) / CGFloat(values.count)
        }
        // The ankle: the narrowest the leg gets above the paw (widths smoothed over a few rows, so fur tufts do not
        // decide it).
        let reach = max(1, length / 40)
        var ankleRow = row(0.82), narrowest = CGFloat.greatestFiniteMagnitude
        for candidate in row(0.66) ... row(0.9) {
            let rows = max(top, candidate - reach) ... min(bottom, candidate + reach)
            let mean = rows.map { span[$0] }.reduce(0, +) / CGFloat(rows.count)
            if mean < narrowest {
                narrowest = mean
                ankleRow = candidate
            }
        }
        let ankleX = centre[ankleRow] ?? average(bottom - 2 ... bottom)
        let soleX = average(bottom - max(2, length / 30) ... bottom)
        let toeX = left[max(top, bottom - max(2, length / 40)) ... bottom].min() ?? Int(soleX)
        var joints = Joints(
            ankle: CGPoint(x: ankleX / CGFloat(width), y: CGFloat(ankleRow) / CGFloat(height)),
            ankleRadius: max(span[ankleRow], 2) / 2 * 1.35 / CGFloat(height),
            sole: CGPoint(x: soleX / CGFloat(width), y: CGFloat(bottom) / CGFloat(height)),
            toe: CGPoint(x: (CGFloat(toeX) + 2) / CGFloat(width), y: CGFloat(bottom) / CGFloat(height))
        )
        guard hind else { return joints }
        let hipX = average(top ... top + max(2, length / 20))
        let ankleLength = ankleRow - top
        var best: CGFloat = 0, hockRow = top + Int(Double(ankleLength) * 0.6)
        for candidate in (top + Int(Double(ankleLength) * 0.35)) ..< (top + Int(Double(ankleLength) * 0.85)) {
            guard let x = centre[candidate] else { continue }
            let t = CGFloat(candidate - top) / CGFloat(ankleLength)
            // Painted facing left, a hock juts back: to the right.
            let off = x - (hipX + (ankleX - hipX) * t)
            if off > best {
                best = off
                hockRow = candidate
            }
        }
        // A short, fluffy hind leg painted without a clear hock stays one piece to the paw, as a front leg does.
        guard best >= CGFloat(length) * CGFloat(Tuning.Puppet.hockBend) else { return joints }
        joints.hock = CGPoint(x: (centre[hockRow] ?? hipX) / CGFloat(width), y: CGFloat(hockRow) / CGFloat(height))
        joints.hockRadius = max(span[hockRow], 2) / 2 * 1.35 / CGFloat(height)
        return joints
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
                // Near the underside: clear somewhere within `band` rows below (a stray hair is not the body).
                var clear = row + band >= height
                for below in stride(from: row + 1, through: min(height - 1, row + band), by: 1) where pixels[(below * width + column) * 4 + 3] < 40 {
                    clear = true
                    break
                }
                guard clear else { continue }
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

    static func alphaPlane(_ image: CGImage) -> [UInt8]? {
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
