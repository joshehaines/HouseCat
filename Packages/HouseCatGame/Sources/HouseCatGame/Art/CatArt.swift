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

    /// A film of the cat walking or running (Josh, 19 Oct: "B is the best by far"; tools/asset-pipeline/walk): one
    /// stride of a white cat filmed in place, each frame a sprite like the parts (`frames`, tinted the same way). In
    /// the frames' master pixels: the cat's standing height (the CatNode's, breed and all), where its feet are on the
    /// floor from the top left (the CatNode's origin), the frame's size, and how far the floor goes by in a stride (x
    /// right, y down); and how long the stride took on film.
    public struct Film: Decodable, Sendable {
        public var frames: [String]
        public var height: Double
        public var feet: [Double]
        public var size: [Double]
        public var stride: [Double]
        public var seconds: Double
        /// Points of the start frame (where the ears join the head and end, the tail's root, the torso's middle)
        /// followed through the frames, and where they were in the start frame; in the frames' master pixels.
        public var points: [String: [[Double]]]?
        public var start: [String: [Double]]?
        /// A one-shot film ("clip": a scratch, a sit-down) rather than a stride, with its loop (a scratch's raking:
        /// frame indices from and to); a stride's most gathered frame (the cat standing) and most stretched (a leap).
        public var kind: String?
        public var loop: [Int]?
        public var stand: Int?
        public var stretch: Int?
        /// A jump's origin in each frame (master pixels): its feet while they are on the ground, its body in the air;
        /// and each frame's scale against the first (the camera came closer or drew back).
        public var origins: [[Double]]?
        public var scales: [Double]?

        public var isClip: Bool {
            kind == "clip"
        }
    }

    private struct FilmIndex: Decodable {
        var films: [String: Film]
        var files: [String: Entry]
    }

    public let root: URL
    public let builder: CatBuilder
    /// The films by "<body>/<view>/<gait>" (films/films.json).
    public let films: [String: Film]
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
        var entries = try JSONDecoder().decode(Index.self, from: Data(contentsOf: root.appendingPathComponent("index.json"))).files
        let filmIndex = (try? Data(contentsOf: root.appendingPathComponent("films/films.json")))
            .flatMap { try? JSONDecoder().decode(FilmIndex.self, from: $0) }
        entries.merge(filmIndex?.files ?? [:]) { old, _ in old }
        self.entries = entries
        films = filmIndex?.films ?? [:]
        builder = try CatBuilder.load(from: root.appendingPathComponent("builder.json"))
    }

    /// The set inside the app's art folder.
    @MainActor
    public convenience init(art: ArtLibrary) throws {
        try self.init(root: art.root.appendingPathComponent("cat/custom"))
    }

    /// The film of a body walking or running in a view, if there is one.
    public func film(body: String, view: String, gait: String) -> Film? {
        films["\(body)/\(view)/\(gait)"]
    }

    /// A film frame tinted into the look, not kept (the cat keeps its own frames while it has the look). `cutting`
    /// takes the film's own ears or tail out of it (their masks, "ears" or "tail"), for the look's swapped ones to go
    /// on instead; the head stays whole where an ear joined it. The masks were carried through the film and lag the
    /// part, so each is widened first, the outline near the cut smoothed, and any sliver left loose of the body there
    /// dropped (Josh, 20 Oct: "two sets of ears": the film's ear rims and tips were left beside the swapped ones, and
    /// the film's tail beside a bobtail).
    public func filmFrame(_ path: String, look: CatLook, cutting parts: [String] = [], garment: CGImage? = nil) -> CGImage? {
        guard var output = render(CatBuilder.Sprite(path: path, takesWhite: true), look: look) else { return nil }
        if let garment, let layer = filmGarment(path, garment: garment, size: (output.width, output.height)) {
            // The garment over the fur (straight alpha, as the frame's planes are).
            for index in output.alpha.indices where layer.alpha[index] > 0 {
                let ga = Float(layer.alpha[index]) / 255, oa = Float(output.alpha[index]) / 255
                let ra = ga + oa * (1 - ga)
                guard ra > 0 else { continue }
                func over(_ g: UInt8, _ o: UInt8) -> UInt8 {
                    UInt8(max(0, min(255, ((Float(g) * ga + Float(o) * oa * (1 - ga)) / ra).rounded())))
                }
                output.r[index] = over(layer.r[index], output.r[index])
                output.g[index] = over(layer.g[index], output.g[index])
                output.b[index] = over(layer.b[index], output.b[index])
                output.alpha[index] = UInt8(max(0, min(255, (ra * 255).rounded())))
            }
        }
        if !parts.isEmpty, let entry = entries[path] {
            let size = (output.width, output.height)
            func plane(_ name: String, widen: Int = 0) -> [Float]? {
                guard entry.masks.contains(name), let raster = Raster.read(root.appendingPathComponent("masks/\(name)/\(path)")) else {
                    return nil
                }
                var bytes = raster.width == size.0 && raster.height == size.1
                    ? raster.planes[0] : Raster.scaled(raster.planes[0], from: (raster.width, raster.height), to: size)
                if widen > 0 {
                    bytes = Raster.widened(bytes, width: size.0, height: size.1, by: widen)
                }
                return Raster.floats(bytes, scale: 1 / 255)
            }
            func pixels(_ share: Double) -> Int {
                max(1, Int((Double(size.1) * share).rounded()))
            }
            let head = plane("head")
            let p = Tuning.Puppet.self
            for part in parts {
                let ears = part == "ears"
                let widen = pixels(ears ? p.filmCutWiden : p.filmTailCutWiden)
                let smooth = pixels(ears ? p.filmCutSmooth : p.filmTailCutSmooth)
                guard let cut = plane(part, widen: widen) else { continue }
                for index in cut.indices {
                    let away = cut[index] - (ears ? head?[index] ?? 0 : 0)
                    let keep = 1 - min(1, max(0, away * 1.6))
                    output.alpha[index] = UInt8(Float(output.alpha[index]) * keep)
                }
                // Near the cut: the outline opened (shrunk, then grown back), taking a sliver the head's mask kept of
                // an ear (its back edge) or a thin end of tail; then anything there no longer joined to the body.
                guard let near = plane(part, widen: widen + 4 * smooth) else { continue }
                let shrunk = Raster.narrowed(output.alpha, width: size.0, height: size.1, by: smooth)
                let opened = Raster.widened(shrunk, width: size.0, height: size.1, by: smooth)
                for index in near.indices where near[index] > 0.5 {
                    output.alpha[index] = min(output.alpha[index], opened[index])
                }
                Raster.dropLoose(&output.alpha, width: size.0, height: size.1, within: near)
            }
        }
        return output.cgImage
    }

    /// Whether a film's frames carry the torso's map, so a body garment can be drawn on them.
    public func filmTakesGarments(_ film: Film) -> Bool {
        film.frames.first.flatMap { entries[$0]?.masks.contains("uv") } ?? false
    }

    /// A body garment's picture laid on a film frame where the frame's map of the torso puts it (masks/uv: red and
    /// green where each pixel is in the torso's own picture, blue where a garment may be drawn), as the puppet carries
    /// the same picture on its torso, `Tuning.Outfits.torsoPad` wider than the torso each way; straight-alpha planes
    /// at `size`, or nil where the frame has no map. The picture is sampled between its pixels.
    func filmGarment(_ path: String, garment: CGImage, size: (Int, Int)) -> (r: [UInt8], g: [UInt8], b: [UInt8], alpha: [UInt8])? {
        guard let entry = entries[path], entry.masks.contains("uv"),
              let map = Raster.read(root.appendingPathComponent("masks/uv/\(path)")), map.planes.count >= 3,
              let picture = Raster(garment), picture.planes.count == 4, picture.width > 1, picture.height > 1 else { return nil }
        let (w, h) = size
        let planes = map.planes.prefix(3).map { plane in
            map.width == w && map.height == h ? plane : Raster.scaled(plane, from: (map.width, map.height), to: (w, h))
        }
        let range = Tuning.Outfits.filmMapRange
        let low = Float(range[0]), span = Float(range[1] - range[0])
        let spread = Float(1 + 2 * Tuning.Outfits.torsoPad)
        let premultiplied = [.premultipliedFirst, .premultipliedLast].contains(garment.alphaInfo)
        let gw = picture.width, gh = picture.height
        var r = [UInt8](repeating: 0, count: w * h), g = r, b = r, a = r
        // The garment's planes, straight alpha.
        var pr = picture.planes[0], pg = picture.planes[1], pb = picture.planes[2]
        let pa = picture.planes[3]
        if premultiplied {
            for i in pa.indices where pa[i] > 0 && pa[i] < 255 {
                let k = 255 / Float(pa[i])
                pr[i] = UInt8(min(255, (Float(pr[i]) * k).rounded()))
                pg[i] = UInt8(min(255, (Float(pg[i]) * k).rounded()))
                pb[i] = UInt8(min(255, (Float(pb[i]) * k).rounded()))
            }
        }
        for y in 0 ..< h {
            for x in 0 ..< w {
                let index = y * w + x
                let allowed = Float(planes[2][index]) / 255
                guard allowed > 0.004 else { continue }
                let u = Float(planes[0][index]) / 255 * span + low
                let v = Float(planes[1][index]) / 255 * span + low
                let gx = ((u - 0.5) / spread + 0.5) * Float(gw) - 0.5
                let gy = ((v - 0.5) / spread + 0.5) * Float(gh) - 0.5
                guard gx > -1, gy > -1, gx < Float(gw), gy < Float(gh) else { continue }
                let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down))
                let fx = gx - Float(x0), fy = gy - Float(y0)
                func sample(_ plane: [UInt8], weighted: Bool) -> Float {
                    func at(_ px: Int, _ py: Int) -> Float {
                        guard px >= 0, py >= 0, px < gw, py < gh else { return 0 }
                        let value = Float(plane[py * gw + px])
                        // Colour weighted by alpha, so a clear neighbour does not darken the edge.
                        return weighted ? value * Float(pa[py * gw + px]) / 255 : value
                    }
                    return at(x0, y0) * (1 - fx) * (1 - fy) + at(x0 + 1, y0) * fx * (1 - fy)
                        + at(x0, y0 + 1) * (1 - fx) * fy + at(x0 + 1, y0 + 1) * fx * fy
                }
                let alpha = sample(pa, weighted: false) / 255
                guard alpha > 0.003 else { continue }
                a[index] = UInt8(max(0, min(255, (alpha * allowed * 255).rounded())))
                r[index] = UInt8(max(0, min(255, (sample(pr, weighted: true) / alpha).rounded())))
                g[index] = UInt8(max(0, min(255, (sample(pg, weighted: true) / alpha).rounded())))
                b[index] = UInt8(max(0, min(255, (sample(pb, weighted: true) / alpha).rounded())))
            }
        }
        return (r, g, b, a)
    }

    /// Where a bobtail goes on a film frame with its own tail cut out: the rump's edge nearest the tail's followed
    /// root (the followed point drifts off the body in some frames, so the bobtail floated beside the rump), in the
    /// film's master pixels; nil where there is no rump near it.
    public static func seatedRoot(_ image: CGImage?, film: Film, frame: Int) -> CGPoint? {
        guard let image, let track = film.points?["tail_root"], frame < track.count, track[frame].count == 2,
              film.size.count == 2, film.size[0] > 0, let raster = Raster(image), raster.planes.count == 4 else { return nil }
        let k = Double(image.width) / film.size[0]
        let alpha = raster.planes[3], w = raster.width, h = raster.height
        let cx = track[frame][0] * k, cy = track[frame][1] * k
        let reach = Int((Double(h) * Tuning.Puppet.bobtailSeatReach).rounded())
        // A tail joins the rump above the body's middle, never down a hind leg.
        let middle = film.points?["torso_middle"].flatMap { frame < $0.count && $0[frame].count == 2 ? $0[frame][1] * k : nil }
        let lowest = min(h - 1, Int(cy) + reach, middle.map { Int($0 + Double(h) * Tuning.Puppet.bobtailBelowMiddle) } ?? h - 1)
        var best: (Double, Int, Int)?
        guard max(0, Int(cy) - reach) <= lowest else { return nil }
        for y in max(0, Int(cy) - reach) ... lowest {
            for x in max(0, Int(cx) - reach) ... min(w - 1, Int(cx) + reach) where alpha[y * w + x] > 160 {
                let d = (Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)
                if best == nil || d < best!.0 {
                    best = (d, x, y)
                }
            }
        }
        return best.map { CGPoint(x: Double($0.1) / k, y: Double($0.2) / k) }
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

    /// Where the face is in a sprite (its features mask and alpha), for fitting outfits; cached. `closedEyes`: where
    /// the eyes are, as fractions of the sprite, when they are shut and so not in the mask (curled up or stretching).
    public func face(_ path: String, closedEyes: [CGPoint] = []) -> CatFace? {
        let key = closedEyes.isEmpty ? path : "\(path)|\(closedEyes.map { "\($0.x),\($0.y)" }.joined(separator: ";"))"
        if let cached = lock.withLock({ faces[key] }) {
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
        // Shut eyes drawn into the iris planes as small discs, left to right.
        if !closedEyes.isEmpty {
            if features.count < 3 {
                features = Array(repeating: [UInt8](repeating: 0, count: size.0 * size.1), count: 3)
            }
            let radius = max(3, size.0 / 60)
            for (i, eye) in closedEyes.prefix(2).enumerated() {
                features[i] = [UInt8](repeating: 0, count: size.0 * size.1)
                let cx = Int(eye.x * CGFloat(size.0)), cy = Int(eye.y * CGFloat(size.1))
                for y in max(0, cy - radius) ... min(size.1 - 1, cy + radius) {
                    for x in max(0, cx - radius) ... min(size.0 - 1, cx + radius) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                        features[i][y * size.0 + x] = 255
                    }
                }
            }
        }
        let face = OutfitFit.face(features: features, alpha: alpha.planes[0], width: size.0, height: size.1, headOnly: path.hasSuffix("_head.png") || path.hasSuffix("_head_noears.png"))
        lock.withLock { faces[key] = face }
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

    /// A plane with every pixel the brightest within `by` pixels of it (a mask grown outwards).
    static func widened(_ plane: [UInt8], width: Int, height: Int, by radius: Int) -> [UInt8] {
        var input = plane
        var output = [UInt8](repeating: 0, count: plane.count)
        let kernel = UInt(radius * 2 + 1)
        input.withUnsafeMutableBytes { i in
            output.withUnsafeMutableBytes { o in
                var src = vImage_Buffer(data: i.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                var dst = vImage_Buffer(data: o.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                _ = vImageMax_Planar8(&src, &dst, nil, 0, 0, kernel, kernel, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return output
    }

    /// Clears the parts of an alpha plane cut loose of its largest piece, where `within` is over a half.
    static func dropLoose(_ alpha: inout [UInt8], width: Int, height: Int, within: [Float]) {
        var label = [Int32](repeating: 0, count: alpha.count)
        var sizes: [Int] = [0]
        var stack: [Int] = []
        for start in alpha.indices where alpha[start] > 76 && label[start] == 0 {
            let id = Int32(sizes.count)
            var count = 0
            label[start] = id
            stack.append(start)
            while let index = stack.popLast() {
                count += 1
                let x = index % width, y = index / width
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let n = ny * width + nx
                    if label[n] == 0, alpha[n] > 76 {
                        label[n] = id
                        stack.append(n)
                    }
                }
            }
            sizes.append(count)
        }
        guard sizes.count > 2, let largest = sizes.indices.dropFirst().max(by: { sizes[$0] < sizes[$1] }) else { return }
        for index in alpha.indices where label[index] != 0 && Int(label[index]) != largest && within[index] > 0.5 {
            alpha[index] = 0
        }
    }

    /// A plane with every pixel the darkest within `by` pixels of it (a mask shrunk inwards).
    static func narrowed(_ plane: [UInt8], width: Int, height: Int, by radius: Int) -> [UInt8] {
        var input = plane
        var output = [UInt8](repeating: 0, count: plane.count)
        let kernel = UInt(radius * 2 + 1)
        input.withUnsafeMutableBytes { i in
            output.withUnsafeMutableBytes { o in
                var src = vImage_Buffer(data: i.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                var dst = vImage_Buffer(data: o.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                _ = vImageMin_Planar8(&src, &dst, nil, 0, 0, kernel, kernel, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return output
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
