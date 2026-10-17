import HouseCatCore
import SpriteKit

/// The code-drawn sky for a phase (Tuning.Sky): a vertical gradient stretched over the view.
enum Sky {
    static func color(_ rgb: [Double]?) -> SKColor {
        let c = rgb ?? [1, 1, 1]
        return SKColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
    }

    static func texture(_ phase: SkyPhase) -> SKTexture {
        let space = CGColorSpaceCreateDeviceRGB(), height = 256
        guard let ctx = CGContext(
            data: nil,
            width: 2,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
            let gradient = CGGradient(
                colorsSpace: space,
                colors: [color(Tuning.Sky.bottom[phase]).cgColor, color(Tuning.Sky.top[phase]).cgColor] as CFArray,
                locations: [0, 1]
            )
        else { return SKTexture() }
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        guard let image = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }
}
