import CoreGraphics

/// Small Core Graphics compositions made once when a scene is built: the view
/// through a window and the room glimpsed through a door, cut to their openings.
enum Composite {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A grayscale copy of an opening mask (white = open) usable as a clip.
    static func mask(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// Sky and terrain cut to a window's opening; the terrain is multiplied by `grade` for the time of day.
    static func windowView(
        size: CGSize,
        opening: CGImage,
        skyTop: CGColor,
        skyBottom: CGColor,
        terrain: CGImage?,
        grade: CGColor
    ) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let clip = mask(opening),
              let ctx = CGContext(
                  data: nil,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: rect, mask: clip)
        if let gradient = CGGradient(colorsSpace: space, colors: [skyBottom, skyTop] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }
        if let terrain {
            // The lower half of the window shows the terrain, wider than the window so it reads as distance.
            let wide = CGFloat(w) * 2.2
            let tall = wide * CGFloat(terrain.height) / CGFloat(terrain.width)
            let place = CGRect(x: -CGFloat(w) * 0.6, y: CGFloat(h) * 0.05 - tall * 0.25, width: wide, height: tall)
            if let graded = graded(terrain, by: grade) {
                ctx.draw(graded, in: place)
            }
        }
        return ctx.makeImage()
    }

    /// An image multiplied by a colour, keeping its own transparency.
    static func graded(_ image: CGImage, by color: CGColor) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(color)
        ctx.fill(rect)
        // The multiply also painted the transparent parts; keep only where the image was.
        ctx.setBlendMode(.destinationIn)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    /// A flat colour cut to a door's opening: the next room, in shadow.
    static func doorway(size: CGSize, opening: CGImage, color: CGColor) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let clip = mask(opening),
              let ctx = CGContext(
                  data: nil,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: rect, mask: clip)
        ctx.setFillColor(color)
        ctx.fill(rect)
        return ctx.makeImage()
    }
}
