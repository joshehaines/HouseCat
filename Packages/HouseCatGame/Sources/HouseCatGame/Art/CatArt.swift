import Accelerate
import CoreGraphics
import Foundation
import HouseCatCore
import ImageIO
import SpriteKit

/// The cat builder's white sprites (App/Art/cat/custom, built by tools/app-assets/build_cat_art.py) tinted into
/// a look with the coat recipe. Sprite paths are CatBuilder's, relative to the set; sizes are reported in master
/// pixels like ArtLibrary's. Thread-safe: a cat can be drawn off the main thread while the room builds.
public final class CatArt: @unchecked Sendable {
    public struct Entry: Decodable, Sendable {
        public var master: [Double]
        public var size: [Int]
        public var scale: Double
        public var masks: [String]
    }

    private struct Index: Decodable {
        var files: [String: Entry]
    }

    public let root: URL
    public let builder: CatBuilder
    private let entries: [String: Entry]
    private let lock = NSLock()
    private var images: [Key: CGImage] = [:]
    private var textures: [Key: SKTexture] = [:]
    private var faces: [String: CatFace] = [:]
    private var blinks: [Key: BlinkEntry] = [:]

    private struct Key: Hashable {
        var path: String
        var look: CoatRecipe.Look
        var pattern: String?
        var white: String?
    }

    public init(root: URL) throws {
        self.root = root
        entries = try JSONDecoder().decode(Index.self, from: Data(contentsOf: root.appendingPathComponent("index.json"))).files
        builder = try CatBuilder.load(from: root.appendingPathComponent("builder.json"))
    }

    /// The set inside the app's art folder.
    @MainActor
    public convenience init(art: ArtLibrary) throws {
        try self.init(root: art.root.appendingPathComponent("cat/custom"))
    }

    public func has(_ path: String) -> Bool {
        entries[path] != nil
    }

    /// The master's size in pixels.
    public func paintedSize(_ path: String) -> CGSize {
        guard let entry = entries[path], entry.master.count == 2 else { return .zero }
        return CGSize(width: entry.master[0], height: entry.master[1])
    }

    /// The recipe's colours and sliders for a look.
    public func recipeLook(_ look: CatLook) -> CoatRecipe.Look {
        let c = builder.colours(look)
        func v(_ rgb: RGB) -> SIMD3<Float> {
            SIMD3(Float(rgb.r), Float(rgb.g), Float(rgb.b))
        }
        return CoatRecipe.Look(
            coat: v(c.coat),
            pattern: c.pattern.map(v),
            eyeLeft: v(c.eyeLeft),
            eyeRight: v(c.eyeRight),
            nose: v(c.nose),
            eyeSize: Float(look.eyeSize),
            whiskerLength: Float(look.whiskerLength)
        )
    }

    /// A sprite tinted into the look.
    public func image(_ sprite: CatBuilder.Sprite, look: CatLook) -> CGImage? {
        guard let entry = entries[sprite.path] else { return nil }
        let pattern = look.pattern.flatMap { entry.masks.contains($0) ? $0 : nil }
        let white = sprite.takesWhite ? look.white.flatMap { entry.masks.contains($0) ? $0 : nil } : nil
        let key = Key(path: sprite.path, look: recipeLook(look), pattern: pattern, white: white)
        if let cached = lock.withLock({ images[key] }) {
            return cached
        }
        let image = render(sprite, look: look)?.cgImage
        lock.withLock { images[key] = image }
        return image
    }

    /// The tinted sprite's planes, straight alpha (not cached: for checking against the reference).
    public func render(_ sprite: CatBuilder.Sprite, look: CatLook) -> CoatRecipe.Output? {
        guard let entry = entries[sprite.path], let painting = painting(sprite.path) else { return nil }
        let pattern = look.pattern.flatMap { entry.masks.contains($0) ? $0 : nil }
        let white = sprite.takesWhite ? look.white.flatMap { entry.masks.contains($0) ? $0 : nil } : nil
        let masks = masks(sprite.path, entry: entry, pattern: pattern, white: white, size: (painting.width, painting.height))
        return CoatRecipe.render(painting, masks: masks, look: recipeLook(look))
    }

    public func texture(_ sprite: CatBuilder.Sprite, look: CatLook) -> SKTexture {
        let entry = entries[sprite.path]
        let key = Key(
            path: sprite.path,
            look: recipeLook(look),
            pattern: look.pattern.flatMap { entry?.masks.contains($0) == true ? $0 : nil },
            white: sprite.takesWhite ? look.white.flatMap { entry?.masks.contains($0) == true ? $0 : nil } : nil
        )
        if let cached = lock.withLock({ textures[key] }) {
            return cached
        }
        let texture = image(sprite, look: look).map { SKTexture(cgImage: $0) } ?? SKTexture()
        texture.filteringMode = .linear
        lock.withLock { textures[key] = texture }
        return texture
    }

    /// Where the face is in a sprite (its features mask and alpha), for fitting outfits; cached.
    public func face(_ path: String) -> CatFace? {
        if let cached = lock.withLock({ faces[path] }) {
            return cached
        }
        guard let entry = entries[path], let alpha = Raster.read(root.appendingPathComponent("alpha/\(path)")) else { return nil }
        let size = (alpha.width, alpha.height)
        var features: [[UInt8]] = []
        if entry.masks.contains("features"), let raster = Raster.read(root.appendingPathComponent("masks/features/\(path)")),
           raster.planes.count >= 3
        {
            features = raster.planes.prefix(3).map { plane in
                raster.width == size.0 && raster.height == size.1 ? plane : Raster.scaled(plane, from: (raster.width, raster.height), to: size)
            }
        }
        let face = OutfitFit.face(features: features, alpha: alpha.planes[0], width: size.0, height: size.1, headOnly: path.hasSuffix("_head.png"))
        lock.withLock { faces[path] = face }
        return face
    }

    /// A sprite's blink picture in a look (CatArt+Blink.swift), made once.
    func blinkEntry(_ sprite: CatBuilder.Sprite, look: CatLook, make: () -> BlinkEntry) -> BlinkEntry {
        let entry = entries[sprite.path]
        let key = Key(
            path: sprite.path,
            look: recipeLook(look),
            pattern: look.pattern.flatMap { entry?.masks.contains($0) == true ? $0 : nil },
            white: sprite.takesWhite ? look.white.flatMap { entry?.masks.contains($0) == true ? $0 : nil } : nil
        )
        if let cached = lock.withLock({ blinks[key] }) {
            return cached
        }
        let made = make()
        lock.withLock { blinks[key] = made }
        return made
    }

    /// Forgets every tinted sprite (after the look changes, the old ones are not drawn again).
    public func purge() {
        lock.withLock {
            images.removeAll()
            textures.removeAll()
            blinks.removeAll()
        }
    }

    // MARK: Loading

    /// The white painting: its colour (JPEG) and alpha (PNG).
    func painting(_ path: String) -> CoatRecipe.Planes? {
        guard let colour = Raster.read(root.appendingPathComponent("base/\(path).jpg")),
              let alpha = Raster.read(root.appendingPathComponent("alpha/\(path)")),
              colour.width == alpha.width, colour.height == alpha.height, colour.planes.count >= 3 else { return nil }
        return CoatRecipe.Planes(
            width: colour.width,
            height: colour.height,
            r: Raster.floats(colour.planes[0]),
            g: Raster.floats(colour.planes[1]),
            b: Raster.floats(colour.planes[2]),
            alpha: alpha.planes[0]
        )
    }

    func masks(_ path: String, entry: Entry, pattern: String?, white: String?, size: (Int, Int)) -> CoatRecipe.Masks {
        func grey(_ mask: String?) -> [Float]? {
            guard let mask, entry.masks.contains(mask),
                  let raster = Raster.read(root.appendingPathComponent("masks/\(mask)/\(path)")) else { return nil }
            let plane = raster.width == size.0 && raster.height == size.1
                ? raster.planes[0]
                : Raster.scaled(raster.planes[0], from: (raster.width, raster.height), to: size)
            return Raster.floats(plane, scale: 1 / 255)
        }
        var masks = CoatRecipe.Masks(fur: grey("fur"), pattern: grey(pattern), white: grey(white), whiskers: grey("whiskers"))
        if entry.masks.contains("features"), let raster = Raster.read(root.appendingPathComponent("masks/features/\(path)")),
           raster.planes.count >= 3
        {
            let planes = raster.planes.prefix(3).map { plane in
                raster.width == size.0 && raster.height == size.1
                    ? plane
                    : Raster.scaled(plane, from: (raster.width, raster.height), to: size)
            }
            masks.irisLeft = Raster.floats(planes[0], scale: 1 / 255)
            masks.irisRight = Raster.floats(planes[1], scale: 1 / 255)
            masks.nose = Raster.floats(planes[2], scale: 1 / 255)
        }
        return masks
    }
}

/// An image file's pixels exactly as stored (no colour management), as planes: grey, RGB or RGBA.
public struct Raster: Sendable {
    public var width: Int
    public var height: Int
    public var planes: [[UInt8]]

    public init(width: Int, height: Int, planes: [[UInt8]]) {
        self.width = width
        self.height = height
        self.planes = planes
    }

    public static func read(_ url: URL) -> Raster? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Raster(image)
    }

    public init?(_ image: CGImage) {
        guard image.bitsPerComponent == 8, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let w = image.width, h = image.height, rowBytes = image.bytesPerRow, components = image.bitsPerPixel / 8
        width = w
        height = h
        var source = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: bytes),
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: rowBytes
        )
        func plane() -> [UInt8] {
            [UInt8](repeating: 0, count: w * h)
        }
        func buffer(_ p: UnsafeMutableRawBufferPointer) -> vImage_Buffer {
            vImage_Buffer(data: p.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
        }
        switch components {
        case 1:
            var grey = plane()
            grey.withUnsafeMutableBytes { p in
                var dest = buffer(p)
                _ = vImageCopyBuffer(&source, &dest, 1, vImage_Flags(kvImageNoFlags))
            }
            planes = [grey]
        case 3:
            var (r, g, b) = (plane(), plane(), plane())
            r.withUnsafeMutableBytes { pr in
                g.withUnsafeMutableBytes { pg in
                    b.withUnsafeMutableBytes { pb in
                        var (dr, dg, db) = (buffer(pr), buffer(pg), buffer(pb))
                        _ = vImageConvert_RGB888toPlanar8(&source, &dr, &dg, &db, vImage_Flags(kvImageNoFlags))
                    }
                }
            }
            planes = [r, g, b]
        case 4:
            var (m0, m1, m2, m3) = (plane(), plane(), plane(), plane())
            m0.withUnsafeMutableBytes { p0 in
                m1.withUnsafeMutableBytes { p1 in
                    m2.withUnsafeMutableBytes { p2 in
                        m3.withUnsafeMutableBytes { p3 in
                            var (d0, d1, d2, d3) = (buffer(p0), buffer(p1), buffer(p2), buffer(p3))
                            _ = vImageConvert_ARGB8888toPlanar8(&source, &d0, &d1, &d2, &d3, vImage_Flags(kvImageNoFlags))
                        }
                    }
                }
            }
            let memory = [m0, m1, m2, m3]
            // The planes in memory order; put them as R, G, B, A.
            let little = image.bitmapInfo.contains(.byteOrder32Little)
            let alphaFirst = [.first, .premultipliedFirst, .noneSkipFirst].contains(image.alphaInfo)
            let order: [Int] = switch (little, alphaFirst) {
            case (false, false): [0, 1, 2, 3] // RGBA
            case (false, true): [1, 2, 3, 0] // ARGB
            case (true, false): [3, 2, 1, 0] // ABGR
            case (true, true): [2, 1, 0, 3] // BGRA
            }
            planes = order.map { memory[$0] }
        default:
            return nil
        }
    }

    /// 0–255 bytes as floats, times `scale`.
    static func floats(_ bytes: [UInt8], scale: Float = 1) -> [Float] {
        var out = [Float](repeating: 0, count: bytes.count)
        vDSP.convertElements(of: bytes, to: &out)
        return scale == 1 ? out : vDSP.multiply(scale, out)
    }

    /// A plane resampled to another size (the half-size masks up to their sprite's size).
    static func scaled(_ plane: [UInt8], from: (Int, Int), to: (Int, Int)) -> [UInt8] {
        var input = plane
        var output = [UInt8](repeating: 0, count: to.0 * to.1)
        input.withUnsafeMutableBytes { i in
            output.withUnsafeMutableBytes { o in
                var src = vImage_Buffer(
                    data: i.baseAddress,
                    height: vImagePixelCount(from.1),
                    width: vImagePixelCount(from.0),
                    rowBytes: from.0
                )
                var dst = vImage_Buffer(data: o.baseAddress, height: vImagePixelCount(to.1), width: vImagePixelCount(to.0), rowBytes: to.0)
                _ = vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return output
    }
}
