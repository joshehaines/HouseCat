import Accelerate
import CoreGraphics
import Foundation
import HouseCatCore

/// The coat recipe (SPEC "Coat recipe"; the reference is tools/asset-pipeline/tint.py, matched pixel for pixel
/// by CoatRecipeTests): a white painting tinted into a look with its masks. On the CPU with Accelerate, so a
/// whole cat renders in a fraction of a second even in a debug build; the results are cached as textures.
public enum CoatRecipe {
    /// A painting as planes the size of the sprite: colour 0–255 and alpha 0–255.
    public struct Planes: Sendable {
        public var width: Int
        public var height: Int
        public var r: [Float]
        public var g: [Float]
        public var b: [Float]
        public var alpha: [UInt8]

        public var count: Int {
            width * height
        }
    }

    /// The masks a sprite has, 0–1, the sprite's size; nil = 0 everywhere.
    public struct Masks: Sendable {
        /// 1 = tint, 0 = keep the painting (pink inner ears, nose, pads; the silhouette edge is always 1).
        public var fur: [Float]?
        public var pattern: [Float]?
        public var white: [Float]?
        public var irisLeft: [Float]?
        public var irisRight: [Float]?
        public var nose: [Float]?
        /// The painted whiskers (1 on a whisker), for the whisker slider.
        public var whiskers: [Float]?

        public init(
            fur: [Float]? = nil,
            pattern: [Float]? = nil,
            white: [Float]? = nil,
            irisLeft: [Float]? = nil,
            irisRight: [Float]? = nil,
            nose: [Float]? = nil,
            whiskers: [Float]? = nil
        ) {
            self.fur = fur
            self.pattern = pattern
            self.white = white
            self.irisLeft = irisLeft
            self.irisRight = irisRight
            self.nose = nose
            self.whiskers = whiskers
        }
    }

    /// The colours (0–255) and sliders of a look.
    public struct Look: Hashable, Sendable {
        public var coat: SIMD3<Float>
        public var pattern: SIMD3<Float>?
        public var eyeLeft: SIMD3<Float>?
        public var eyeRight: SIMD3<Float>?
        public var nose: SIMD3<Float>?
        /// 0 … 1, 0.5 as painted.
        public var eyeSize: Float
        /// 0 … 1, 1 as painted.
        public var whiskerLength: Float

        public init(
            coat: SIMD3<Float>,
            pattern: SIMD3<Float>? = nil,
            eyeLeft: SIMD3<Float>? = nil,
            eyeRight: SIMD3<Float>? = nil,
            nose: SIMD3<Float>? = nil,
            eyeSize: Float = 0.5,
            whiskerLength: Float = 1
        ) {
            self.coat = coat
            self.pattern = pattern
            self.eyeLeft = eyeLeft
            self.eyeRight = eyeRight
            self.nose = nose
            self.eyeSize = eyeSize
            self.whiskerLength = whiskerLength
        }
    }

    /// The tinted sprite, 8-bit planes (tint.py clips to 0–255 and truncates).
    public struct Output: Sendable {
        public var width: Int
        public var height: Int
        public var r: [UInt8]
        public var g: [UInt8]
        public var b: [UInt8]
        public var alpha: [UInt8]
    }

    static let depth: Float = 1.15

    public static func render(_ painting: Planes, masks: Masks, look: Look) -> Output {
        let n = painting.count
        let rgb = [painting.r, painting.g, painting.b]
        // L = luminance of the white painting, 0–1.
        var lum = [Float](repeating: 0, count: n)
        vDSP.multiply(0.3 / 255, painting.r, result: &lum)
        lum = vDSP.add(multiplication: (painting.g, 0.55 / 255), lum)
        lum = vDSP.add(multiplication: (painting.b, 0.15 / 255), lum)
        // shade = clip(L, 0, 1) ^ 1.15
        var shade = vDSP.clip(lum, to: 0 ... 1)
        var exponent = depth
        var count = Int32(n)
        shade.withUnsafeMutableBufferPointer { s in
            vvpowsf(s.baseAddress!, &exponent, s.baseAddress!, &count)
        }
        // Keep a little of the painted highlight; less on dark coats so the rim does not sparkle.
        let coatLum = 0.3 * look.coat.x + 0.55 * look.coat.y + 0.15 * look.coat.z
        let k = 0.35 * min(1, max(0.3, coatLum / 180))
        var keep = vDSP.clip(vDSP.add(-0.85 / 0.15, vDSP.multiply(1 / 0.15, lum)), to: 0 ... 1)
        keep = vDSP.multiply(k, keep)

        // The tint mask: the fur mask, irises taken out.
        var tint = masks.fur ?? [Float](repeating: 1, count: n)
        if masks.irisLeft != nil || masks.irisRight != nil {
            let zeros = [Float](repeating: 0, count: n)
            let irises = vDSP.clip(vDSP.add(masks.irisLeft ?? zeros, masks.irisRight ?? zeros), to: 0 ... 1)
            tint = vDSP.multiply(tint, vDSP.add(1, vDSP.multiply(-1, irises)))
        }

        var out: [[Float]] = []
        for c in 0 ..< 3 {
            let coat = look.coat[c]
            // col = mix(coat, patternColour, patternMask); fur = shade × col
            var fur: [Float]
            if let pattern = masks.pattern, let colour = look.pattern {
                let col = vDSP.add(coat, vDSP.multiply(colour[c] - coat, pattern))
                fur = vDSP.multiply(shade, col)
            } else {
                fur = vDSP.multiply(coat, shade)
            }
            fur = mix(fur, rgb[c], by: keep)
            if let white = masks.white {
                fur = mix(fur, rgb[c], by: white)
            }
            out.append(mix(rgb[c], fur, by: tint))
        }
        // Irises keep the painted value structure (dark rim, bright centre) in the chosen colour; then the nose.
        for (mask, colour, gain, ceiling) in [
            (masks.irisLeft, look.eyeLeft, Float(1 / 0.62), Float(1.35)),
            (masks.irisRight, look.eyeRight, Float(1 / 0.62), Float(1.35)),
            (masks.nose, look.nose, Float(1 / 0.72), Float(1.3)),
        ] {
            guard let mask, let colour, vDSP.maximum(mask) > 0 else { continue }
            let value = vDSP.clip(vDSP.multiply(gain, lum), to: 0 ... ceiling)
            for c in 0 ..< 3 {
                let target = vDSP.clip(vDSP.multiply(colour[c], value), to: 0 ... 255)
                out[c] = mix(out[c], target, by: mask)
            }
        }
        var result = Output(
            width: painting.width,
            height: painting.height,
            r: truncated(out[0]),
            g: truncated(out[1]),
            b: truncated(out[2]),
            alpha: painting.alpha
        )
        if look.whiskerLength < 1, let whiskers = masks.whiskers, let nose = masks.nose {
            trimWhiskers(&result, whiskers: whiskers, nose: nose, length: look.whiskerLength)
        }
        if abs(look.eyeSize - 0.5) > 0.01 {
            for iris in [masks.irisLeft, masks.irisRight].compactMap(\.self) {
                resizeEye(&result, iris: iris, size: look.eyeSize)
            }
        }
        return result
    }

    /// a + (b − a) × t
    static func mix(_ a: [Float], _ b: [Float], by t: [Float]) -> [Float] {
        vDSP.add(multiplication: (vDSP.subtract(b, a), t), a)
    }

    static func truncated(_ values: [Float]) -> [UInt8] {
        let clipped = vDSP.clip(values, to: 0 ... 255)
        var bytes = [UInt8](repeating: 0, count: clipped.count)
        vDSP.convertElements(of: clipped, to: &bytes, rounding: .towardZero)
        return bytes
    }

    // MARK: Sliders

    /// Shortens the painted whiskers: past a reach from the nose (its fraction of their painted reach), they fade out.
    static func trimWhiskers(_ image: inout Output, whiskers: [Float], nose: [Float], length: Float) {
        guard let centre = centroid(nose, width: image.width) else { return }
        var reach: Float = 0
        var strokes: [(index: Int, distance: Float)] = []
        for (i, w) in whiskers.enumerated() where w > 0.5 {
            let d = hypot(Float(i % image.width) - centre.x, Float(i / image.width) - centre.y)
            strokes.append((i, d))
            reach = max(reach, d)
        }
        let keep = reach * (Float(Tuning.Cat.shortestWhiskers) + (1 - Float(Tuning.Cat.shortestWhiskers)) * max(0, length))
        let feather = max(2, reach * 0.06)
        for stroke in strokes where stroke.distance > keep - feather {
            let fade = max(0, min(1, (keep - stroke.distance) / feather + 1))
            image.alpha[stroke.index] = UInt8(Float(image.alpha[stroke.index]) * fade)
        }
    }

    /// Makes an eye larger or smaller: the painting around the iris is magnified about its centre, easing to
    /// nothing at twice the iris's radius.
    static func resizeEye(_ image: inout Output, iris: [Float], size: Float) {
        guard let centre = centroid(iris, width: image.width) else { return }
        let area = vDSP.sum(iris)
        let radius = 2.2 * (area / .pi).squareRoot()
        guard radius > 2 else { return }
        let scale = 1 + Float(Tuning.Cat.eyeSizeRange) * (size * 2 - 1)
        let source = image
        let w = image.width, h = image.height
        let x0 = max(0, Int(centre.x - radius)), x1 = min(w - 1, Int(centre.x + radius))
        let y0 = max(0, Int(centre.y - radius)), y1 = min(h - 1, Int(centre.y + radius))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0 ... y1 {
            for x in x0 ... x1 {
                let dx = Float(x) - centre.x, dy = Float(y) - centre.y
                let d = (dx * dx + dy * dy).squareRoot() / radius
                guard d < 1 else { continue }
                let falloff = (1 - d * d) * (1 - d * d)
                let m = 1 + (scale - 1) * falloff
                let sx = centre.x + dx / m, sy = centre.y + dy / m
                let i = y * w + x
                let (r, g, b, a) = sample(source, x: sx, y: sy)
                image.r[i] = r
                image.g[i] = g
                image.b[i] = b
                image.alpha[i] = a
            }
        }
    }

    private static func sample(_ image: Output, x: Float, y: Float) -> (UInt8, UInt8, UInt8, UInt8) {
        let w = image.width, h = image.height
        let fx = max(0, min(Float(w - 1), x)), fy = max(0, min(Float(h - 1), y))
        let ix = min(w - 2, Int(fx)), iy = min(h - 2, Int(fy))
        let tx = fx - Float(ix), ty = fy - Float(iy)
        func at(_ plane: [UInt8]) -> UInt8 {
            let a = Float(plane[iy * w + ix]), b = Float(plane[iy * w + ix + 1])
            let c = Float(plane[(iy + 1) * w + ix]), d = Float(plane[(iy + 1) * w + ix + 1])
            let top = a + (b - a) * tx, bottom = c + (d - c) * tx
            return UInt8(max(0, min(255, (top + (bottom - top) * ty).rounded())))
        }
        return (at(image.r), at(image.g), at(image.b), at(image.alpha))
    }

    private static func centroid(_ mask: [Float], width: Int) -> SIMD2<Float>? {
        var sx: Float = 0, sy: Float = 0, total: Float = 0
        for (i, m) in mask.enumerated() where m > 0.05 {
            sx += Float(i % width) * m
            sy += Float(i / width) * m
            total += m
        }
        return total > 0 ? SIMD2(sx / total, sy / total) : nil
    }
}

public extension CoatRecipe.Output {
    /// A non-premultiplied RGBA image.
    var cgImage: CGImage? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var (pr, pg, pb, pa) = (r, g, b, alpha)
        let interleaved = rgba.withUnsafeMutableBytes { out in
            pr.withUnsafeMutableBytes { r in
                pg.withUnsafeMutableBytes { g in
                    pb.withUnsafeMutableBytes { b in
                        pa.withUnsafeMutableBytes { a in
                            func plane(_ p: UnsafeMutableRawBufferPointer) -> vImage_Buffer {
                                vImage_Buffer(
                                    data: p.baseAddress,
                                    height: vImagePixelCount(height),
                                    width: vImagePixelCount(width),
                                    rowBytes: width
                                )
                            }
                            var (sr, sg, sb, sa) = (plane(r), plane(g), plane(b), plane(a))
                            var dest = vImage_Buffer(
                                data: out.baseAddress,
                                height: vImagePixelCount(height),
                                width: vImagePixelCount(width),
                                rowBytes: width * 4
                            )
                            // The "ARGB" order is only the order of the arguments: here R, G, B, A.
                            let error = vImageConvert_Planar8toARGB8888(&sr, &sg, &sb, &sa, &dest, vImage_Flags(kvImageNoFlags))
                            guard error == kvImageNoError else { return error }
                            return vImagePremultiplyData_RGBA8888(&dest, &dest, vImage_Flags(kvImageNoFlags))
                        }
                    }
                }
            }
        }
        guard interleaved == kvImageNoError, let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
