import CoreGraphics

/// The cat's head and shoulders cut square from a picture of it sitting, for the player's badge (Josh, 19 Oct: the
/// badge's fixed crop cut the ears off): centred across the head, with the ear tips (or a hat) a little below the
/// top, so the whole head shows inside a ring.
public enum Headshot {
    /// The square's side, in head widths (across the eye line): the head, its ears and the top of the chest.
    static let side: CGFloat = 1.8
    /// Room above the ear tips, in sides: a ring is narrow at the top, and the ears must sit inside it.
    static let headroom: CGFloat = 0.1

    /// - Parameters:
    ///   - image: the cat as drawn, dressed or not (an outfit only adds room at the top, so across it matches the
    ///     undressed sprite).
    ///   - face: where the face is in the undressed sprite (`CatArt.face`); without one the head is taken to be the
    ///     picture's middle third.
    ///   - size: the square's side in pixels.
    public static func cut(_ image: CGImage, face: CatFace?, size: Int = 256) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let alpha = alphaPlane(image) else { return nil }
        let span = face?.head.map { (left: $0.left * CGFloat(width), right: $0.right * CGFloat(width)) }
            ?? (left: CGFloat(width) / 3, right: CGFloat(width) * 2 / 3)
        let middle = (span.left + span.right) / 2
        let headWidth = max(1, span.right - span.left)
        // The top of the cat over its head (an ear tip, a hat): the first row with ink across the head and its ears.
        let from = max(0, Int(middle - headWidth * 0.7))
        let to = min(width - 1, Int(middle + headWidth * 0.7))
        let top = from <= to ? (0 ..< height).first { row in
            (from ... to).contains { alpha[row * width + $0] > 40 }
        } ?? 0 : 0
        // Big ears (an Oriental's) reach out where a ring is narrow: the square grows until they are inside it.
        var ears: [CGPoint] = []
        for row in stride(from: top, to: min(height, top + Int(headWidth * 0.6)), by: 2) {
            for column in stride(from: from, through: to, by: 2) where alpha[row * width + column] > 40 {
                ears.append(CGPoint(x: CGFloat(column) - middle, y: CGFloat(row - top)))
            }
        }
        var side = headWidth * Self.side
        func inside(_ point: CGPoint) -> Bool {
            let radius = side / 2
            return hypot(point.x, point.y + side * headroom - radius) <= radius * 0.97
        }
        while side < headWidth * 2.6, !ears.allSatisfy(inside) {
            side *= 1.04
        }
        let crop = CGRect(x: middle - side / 2, y: CGFloat(top) - side * headroom, width: side, height: side)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        // The crop is measured from the top left; the context draws from the bottom left.
        let scale = CGFloat(size) / side
        context.draw(image, in: CGRect(
            x: -crop.minX * scale,
            y: CGFloat(size) - (CGFloat(height) - crop.minY) * scale,
            width: CGFloat(width) * scale,
            height: CGFloat(height) * scale
        ))
        return context.makeImage()
    }

    /// The picture's alpha, a byte a pixel, rows from the top.
    private static func alphaPlane(_ image: CGImage) -> [UInt8]? {
        var alpha = [UInt8](repeating: 0, count: image.width * image.height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? alpha : nil
    }
}
