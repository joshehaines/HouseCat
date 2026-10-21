import CoreGraphics
import Foundation
import ImageIO
import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Every outfit on every picture of the cat the game draws (Josh, 20 Oct: "do a full scan of the clothing ... make
/// sure everything works well with every type of cat shape etc. this is a key feature of the game and has to work
/// correctly"): each body's puppet heads, every resting pose in every ear and tail variant, and every frame of every
/// walk and run film, with every hat, pair of glasses and neckwear fitted as the game fits it; and every body garment
/// over every pose and torso it is painted for. Checked mechanically: an outfit is there wherever the cat can wear it,
/// its size against the head is in range, it sits where it belongs on the face, it never jumps between neighbouring
/// frames of a film, and a garment stays inside the cat. HOUSECAT_OUTFIT_REPORT=<file> also writes every measurement
/// as CSV.
@MainActor
@Suite("Every outfit on every cat")
struct OutfitMatrixTests {
    let art: ArtLibrary
    let catArt: CatArt
    let outfits: [OutfitsFile.Outfit]

    init() throws {
        art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
        catArt = try CatArt(art: art)
        outfits = try ContentBundle.load(from: repo.appendingPathComponent("Content")).outfits.outfits
    }

    /// One picture of the cat an outfit is fitted to.
    struct Picture {
        var name: String
        var path: String
        var view: String
        /// The look's ears (a pose variant's), for tall ears.
        var ears: String
        var body: String
        /// For a film: which, and the frame.
        var film: String?
        var frame: Int?
        /// For a resting pose: which (curled up or stretching its eyes are shut, and put where they were measured),
        /// and the look's tail.
        var pose: CatPose?
        var tail = "own"
    }

    static let standardEars = ["own", "rounded", "folded", "tufted", "oriental"]

    /// Every picture an outfit is fitted to: puppet heads, resting poses in every variant, every film frame the cat
    /// shows (a film that hides the face hands the outfit to the puppet, so its frames are not used).
    func pictures() -> [Picture] {
        var out: [Picture] = []
        for body in catArt.builder.data.bodies {
            let ears = body.earSwaps ? Self.standardEars : ["own"]
            for view in ["side", "tqfront", "front"] {
                let head = "parts/cat_\(body.id)_\(view)_head.png"
                out.append(Picture(name: "\(body.id) \(view) head", path: head, view: view, ears: "own", body: body.id))
                let earless = head.replacingOccurrences(of: ".png", with: "_noears.png")
                if catArt.has(earless) {
                    out.append(Picture(name: "\(body.id) \(view) head with swapped ears", path: earless, view: view, ears: "rounded", body: body.id))
                }
            }
            for pose in CatPose.allCases {
                guard let view = OutfitFit.view(for: pose) else { continue }
                for ear in ears {
                    for tail in body.tailSwaps ? ["own", "bobtail"] : ["own"] {
                        let look = CatLook(body: body.id, ears: ear, tail: tail)
                        let path = catArt.builder.pose(pose.rawValue, look: look).path
                        guard catArt.has(path) else { continue }
                        out.append(Picture(
                            name: "\(body.id) \(pose.rawValue) \(ear) \(tail)", path: path, view: view, ears: ear, body: body.id, pose: pose, tail: tail
                        ))
                    }
                }
            }
            for view in ["side", "tqfront"] {
                for gait in ["walk", "run"] {
                    guard let film = catArt.film(body: body.id, view: view, gait: gait) else { continue }
                    let eyes = view == "side" ? 1 : 2
                    let share = Double(film.frames.filter { (catArt.face($0)?.eyes.count ?? 0) >= eyes }.count) / Double(max(1, film.frames.count))
                    guard share >= Tuning.Outfits.filmFaces else { continue }
                    for (i, frame) in film.frames.enumerated() {
                        out.append(Picture(name: "\(body.id) \(view) \(gait) \(i)", path: frame, view: view, ears: "own", body: body.id, film: "\(body.id)/\(view)/\(gait)", frame: i))
                    }
                }
            }
        }
        return out
    }

    /// The face an outfit of `kind` is fitted to on a picture, as the game finds it.
    func face(_ picture: Picture, kind: OutfitFit.Kind? = nil) -> CatFace? {
        if let key = picture.film, let frame = picture.frame, let film = catArt.films[key] {
            return CatNode.filmFace(film, frame: frame, side: picture.view == "side", catArt: catArt)
        }
        if let pose = picture.pose {
            let look = CatLook(body: picture.body, ears: picture.ears, tail: picture.tail)
            return OutfitFit.restingFace(pose, look: look, catArt: catArt, art: art, for: kind)
        }
        return catArt.face(picture.path)
    }

    /// An outfit fitted to a picture, measured against its face: in head widths from the eyes' middle (x right, y
    /// down; curled up, along the head as it lies, x along the shut eyes and y square to them), its width against the
    /// head, and where on the face the head was found.
    struct Measure {
        var picture: Picture
        var outfit: String
        var kind: OutfitFit.Kind
        var placed: Bool
        var width = 0.0
        var dx = 0.0
        var dy = 0.0
        var angle = 0.0
        var headWidth = 0.0
        /// The fitted point in the picture's own pixels (films: the film's master pixels), for continuity.
        var point = CGPoint.zero
        var pictureWidth = 0.0
        /// A headband painted side-on (sized by the head's height, its end down by the cheek).
        var band = false
    }

    func measure(_ picture: Picture, _ outfit: OutfitsFile.Outfit, kind: OutfitFit.Kind) -> Measure? {
        guard let path = outfit.sprites[picture.view == "tqback" ? "tqback" : picture.view],
              let shape = OutfitShapes.shape(path, art: art), let face = face(picture, kind: kind) else { return nil }
        let look = CatLook(body: picture.body, ears: picture.ears)
        let tall = OutfitFit.tallEars(look, wearing: outfit)
        var m = Measure(picture: picture, outfit: outfit.id, kind: kind, placed: false)
        guard let fit = OutfitFit.place(
            kind, shape: shape, on: face, view: picture.view, size: outfit.fit, tallEars: tall, coversEars: OutfitFit.coversEars(outfit)
        ) else { return m }
        let w = face.size.width, h = face.size.height
        // Measured from the eyes themselves (asleep, glasses are fitted to eyes pushed up onto the forehead).
        let asleep = picture.pose == .sleepCurl
        let plain = asleep && kind == .glasses ? self.face(picture) ?? face : face
        let eyes = OutfitFit.profileEyes(plain, view: picture.view)
        guard let (left, right) = OutfitFit.headSpan(plain, eyes: eyes, w: w, h: h), right - left > 1 else { return m }
        let hw = right - left
        let anchor = eyes.isEmpty
            ? CGPoint(x: (left + right) / 2, y: (face.head?.y ?? 0) * h)
            : CGPoint(x: eyes.map(\.x).reduce(0, +) / CGFloat(eyes.count), y: eyes.map(\.y).reduce(0, +) / CGFloat(eyes.count))
        m.placed = true
        m.headWidth = hw
        // The outfit's painted width (a hat's rim, neckwear's band, the whole of a pair of glasses) against the head.
        let painted = switch kind {
        case .hat: shape.rimWidth
        case .neck: shape.topWidth
        case .glasses: 1.0
        }
        m.width = fit.width * painted / hw
        m.band = kind == .hat && !eyes.isEmpty && shape.size.height > shape.size.width * CGFloat(Tuning.Outfits.bandAspect)
        m.dx = (fit.point.x - anchor.x) / hw
        m.dy = (fit.point.y - anchor.y) / hw
        m.angle = fit.angle
        if asleep, eyes.count == 2 {
            // Along the head as it lies: turned so the eyes are level.
            let e = eyes.sorted { $0.x < $1.x }
            let tilt = atan2(e[1].y - e[0].y, e[1].x - e[0].x)
            (m.dx, m.dy) = (m.dx * cos(tilt) + m.dy * sin(tilt), m.dy * cos(tilt) - m.dx * sin(tilt))
            m.angle -= tilt
        }
        if let key = picture.film, let film = catArt.films[key], film.size.count == 2 {
            let k = film.size[0] / w
            m.point = CGPoint(x: fit.point.x * k, y: fit.point.y * k)
            m.pictureWidth = fit.width * k
        } else {
            m.point = fit.point
            m.pictureWidth = fit.width
        }
        return m
    }

    func allMeasures() -> [Measure] {
        var out: [Measure] = []
        let pictures = pictures()
        for outfit in outfits {
            guard let kind = OutfitFit.kind(outfit) else { continue }
            for picture in pictures {
                if let m = measure(picture, outfit, kind: kind) {
                    out.append(m)
                }
            }
        }
        return out
    }

    /// What is wrong with an outfit on a picture, if anything: the ranges it looks right in, in head widths from the
    /// eyes (the contact sheets of every body, 20 Oct).
    func problems(_ m: Measure) -> [String] {
        let name = "\(m.outfit) on \(m.picture.name)"
        guard m.placed else {
            // Glasses need eyes: from behind there are none.
            return m.kind == .glasses && m.picture.view == "tqback" ? [] : ["\(name): not worn"]
        }
        var out: [String] = []
        func within(_ what: String, _ value: Double, _ low: Double, _ high: Double) {
            if value < low || value > high {
                out.append("\(name): \(what) \(String(format: "%.2f", value)) outside \(low)...\(high)")
            }
        }
        let back = m.picture.view == "tqback", side = m.picture.view == "side"
        switch m.kind {
        case .hat:
            within("width against the head", m.width, 0.3, 1.6)
            if m.band {
                // Its end comes down by the cheek, behind the eye.
                within("height", m.dy, -0.8, 0.3)
                within("distance behind the eye", m.dx, -0.1, 0.6)
            } else {
                // The rim above the eye line (from behind, about level with where the eyes would be).
                within("height", m.dy, back ? -0.45 : -0.8, back ? 0.1 : -0.1)
                within("distance across", m.dx, side ? -0.1 : -0.4, 0.4)
            }
        case .glasses:
            within("width against the head", m.width, 0.6, 2.0)
            within("distance across from the eyes", m.dx, -0.3, 0.3)
            if m.picture.pose == .sleepCurl {
                // Asleep, pushed up off the shut eyes onto the forehead.
                within("height above the shut eyes", m.dy, -0.45, -0.1)
            } else {
                within("height off the eyes", m.dy, -0.12, 0.12)
            }
        case .neck:
            within("width against the head", m.width, 0.15, 1.0)
            // Under the chin; side-on behind the throat, no further back than just behind the head.
            within("depth under the eyes", m.dy, 0.2, 1.0)
            within("distance across", m.dx, side ? -0.1 : -0.3, side ? 1.0 : 0.3)
        }
        return out
    }

    /// Every hat, pair of glasses and neckwear on every picture of every cat: worn wherever it can be, its size
    /// against the head and its place on the face in range.
    @Test func everyOutfitSitsWhereItBelongsOnEveryPicture() {
        let measures = allMeasures()
        #expect(measures.count > 25000)
        let found = measures.flatMap(problems)
        #expect(found.isEmpty, "\(found.count) problems:\n\(found.prefix(40).joined(separator: "\n"))")
    }

    /// From one frame of a walk or run to the next, an outfit moves with the face and keeps its size: against the
    /// face it moves no more than a fifth of the head, and grows or shrinks by less than a sixth.
    @Test func noOutfitJumpsBetweenAFilmsFrames() {
        var films: [String: [Int: Measure]] = [:]
        for m in allMeasures() where m.placed {
            if let film = m.picture.film, let frame = m.picture.frame {
                films["\(film) \(m.outfit)", default: [:]][frame] = m
            }
        }
        #expect(!films.isEmpty)
        var found: [String] = []
        for (key, frames) in films {
            let count = (frames.keys.max() ?? 0) + 1
            for i in 0 ..< count {
                guard let a = frames[i], let b = frames[(i + 1) % count] else { continue }
                let move = hypot(b.dx - a.dx, b.dy - a.dy), grow = b.pictureWidth / max(1, a.pictureWidth)
                if move > 0.2 || grow > 1.15 || grow < 1 / 1.15 {
                    found.append("\(key) \(i)->\((i + 1) % count): moved \(String(format: "%.2f", move)) heads, size x\(String(format: "%.2f", grow))")
                }
            }
        }
        #expect(found.isEmpty, "\(found.count) jumps:\n\(found.sorted().prefix(40).joined(separator: "\n"))")
    }

    /// Curled up asleep with its eyes shut, a hat sits on the crown above them and glasses are pushed up onto the
    /// forehead, between the eyes and the crown; stretching, the shut eye is found (`outfits/poses.json`, or the
    /// features mask), so glasses go on it.
    @Test func asleepAHatSitsOnTheCrownAndGlassesOnTheForehead() throws {
        for body in catArt.builder.data.bodies {
            let look = CatLook(body: body.id)
            let curled = try #require(OutfitFit.restingFace(.sleepCurl, look: look, catArt: catArt, art: art), "\(body.id)")
            try #require(curled.eyes.count == 2, "\(body.id) curled up")
            let crown = try #require(curled.crown, "\(body.id)")
            let glasses = try #require(OutfitFit.restingFace(.sleepCurl, look: look, catArt: catArt, art: art, for: .glasses))
            let w = curled.size.width, h = curled.size.height
            func middle(_ face: CatFace) -> CGPoint {
                CGPoint(x: (face.eyes[0].x + face.eyes[1].x) / 2 * w, y: (face.eyes[0].y + face.eyes[1].y) / 2 * h)
            }
            let eyes = middle(curled), lifted = middle(glasses), top = CGPoint(x: crown.x * w, y: crown.y * h)
            #expect(top.y < eyes.y, "\(body.id): the crown is above the eyes")
            let up = hypot(top.x - eyes.x, top.y - eyes.y)
            #expect(hypot(lifted.x - eyes.x, lifted.y - eyes.y) > up * 0.2, "\(body.id): the glasses are off the eyes")
            #expect(hypot(top.x - lifted.x, top.y - lifted.y) < up, "\(body.id): the glasses are up toward the crown")
            let stretching = try #require(OutfitFit.restingFace(.stretchSide, look: look, catArt: catArt, art: art), "\(body.id)")
            #expect(!stretching.eyes.isEmpty, "\(body.id) stretching")
        }
    }

    /// A body garment's painting against the cat it is drawn over: the share of it off the cat (beyond a sliver of
    /// the cat's own outline), and how much of the cat it covers. `variant`: an ear or tail variant's painting, where
    /// the game draws it only where the cat is.
    struct GarmentFit {
        var name: String
        var off: Double
        var cover: Double
        var variant: Bool
    }

    /// A picture's outline at most `Self.across` cells wide (each cell opaque where any of it is), the cat's widened.
    struct Outline {
        var width: Int
        var height: Int
        var opaque: [Bool]
        var near: [Bool]
    }

    static let across = 100

    /// A picture read at the outline's size (decoding and walking the whole of each took most of the time).
    static func small(_ url: URL) -> Raster? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: across,
              ] as CFDictionary)
        else { return nil }
        return Raster(image)
    }

    static func outline(_ raster: Raster, widen: Double) -> Outline {
        let alpha = raster.planes.count == 4 ? raster.planes[3] : raster.planes[0]
        let k = max(1, (raster.width + Self.across - 1) / Self.across)
        let w = (raster.width + k - 1) / k, h = (raster.height + k - 1) / k
        var opaque = [Bool](repeating: false, count: w * h)
        alpha.withUnsafeBufferPointer { a in
            opaque.withUnsafeMutableBufferPointer { o in
                for y in 0 ..< raster.height {
                    let row = y * raster.width, cell = (y / k) * w
                    for x in 0 ..< raster.width where a[row + x] > 127 {
                        o[cell + x / k] = true
                    }
                }
            }
        }
        // Widened by a square of cells, a row pass then a column pass.
        let pad = max(1, Int((Double(w) * widen).rounded()))
        var wide = opaque, near = opaque
        opaque.withUnsafeBufferPointer { o in
            wide.withUnsafeMutableBufferPointer { r in
                for y in 0 ..< h {
                    for x in 0 ..< w where o[y * w + x] {
                        for xx in max(0, x - pad) ... min(w - 1, x + pad) {
                            r[y * w + xx] = true
                        }
                    }
                }
            }
        }
        wide.withUnsafeBufferPointer { r in
            near.withUnsafeMutableBufferPointer { n in
                for y in 0 ..< h {
                    for x in 0 ..< w where r[y * w + x] {
                        for yy in max(0, y - pad) ... min(h - 1, y + pad) {
                            n[yy * w + x] = true
                        }
                    }
                }
            }
        }
        return Outline(width: w, height: h, opaque: opaque, near: near)
    }

    func garmentFits() throws -> [GarmentFit] {
        var out: [GarmentFit] = []
        var cats: [String: Outline] = [:], garmentOutlines: [String: Outline] = [:]
        // The garment's cells over the cat's: off it, and how much of the cat it covers.
        func fit(_ name: String, garment path: String, over catPath: String, frame: CGRect, variant: Bool) -> GarmentFit? {
            if cats[catPath] == nil {
                cats[catPath] = Self.small(catArt.root.appendingPathComponent("alpha/\(catPath)")).map { Self.outline($0, widen: 0.012) }
            }
            if garmentOutlines[path] == nil {
                garmentOutlines[path] = Self.small(art.url(path)).map { Self.outline($0, widen: 0) }
            }
            guard let cat = cats[catPath], let g = garmentOutlines[path] else { return nil }
            var cells = 0, off = 0
            var covered = [Bool](repeating: false, count: cat.width * cat.height)
            // Every garment cell's middle, on the cat's cells (as finely as the cat's grid).
            let sx = max(1, Int(Double(cat.width) * frame.width)), sy = max(1, Int(Double(cat.height) * frame.height))
            for j in 0 ..< sy {
                let gy = min(g.height - 1, j * g.height / sy)
                for i in 0 ..< sx {
                    let gx = min(g.width - 1, i * g.width / sx)
                    guard g.opaque[gy * g.width + gx] else { continue }
                    cells += 1
                    let cx = Int((frame.minX + (Double(i) + 0.5) / Double(sx) * frame.width) * Double(cat.width))
                    let cy = Int((frame.minY + (Double(j) + 0.5) / Double(sy) * frame.height) * Double(cat.height))
                    guard cx >= 0, cy >= 0, cx < cat.width, cy < cat.height, cat.near[cy * cat.width + cx] else {
                        off += 1
                        continue
                    }
                    if cat.opaque[cy * cat.width + cx] {
                        covered[cy * cat.width + cx] = true
                    }
                }
            }
            let catCells = cat.opaque.filter { $0 }.count
            return GarmentFit(
                name: name, off: Double(off) / Double(max(1, cells)), cover: Double(covered.filter { $0 }.count) / Double(max(1, catCells)), variant: variant
            )
        }
        let garments = outfits.filter { $0.slot == .body }
        let pad = Tuning.Outfits.torsoPad
        for body in catArt.builder.data.bodies {
            let ears = body.earSwaps ? Self.standardEars : ["own"]
            for garment in garments {
                for pose in CatPose.allCases {
                    guard let path = OutfitFit.garment(garment, body: body.id, pose: pose), art.has(path) else { continue }
                    let base = "poses/cat_\(body.id)_\(pose.rawValue).png"
                    for ear in ears {
                        for tail in body.tailSwaps ? ["own", "bobtail"] : ["own"] {
                            let drawn = catArt.builder.pose(pose.rawValue, look: CatLook(body: body.id, ears: ear, tail: tail)).path
                            guard catArt.has(drawn) else { continue }
                            let frame = GarmentPlacement.frame(drawn: drawn, base: base, catArt: catArt, art: art)
                            let name = "\(garment.id) on \(body.id) \(pose.rawValue) \(ear) \(tail)"
                            if let f = fit(name, garment: path, over: drawn, frame: frame, variant: drawn != base) {
                                out.append(f)
                            }
                        }
                    }
                }
                for view in CatNode.View.allCases {
                    guard let path = OutfitFit.garment(garment, body: body.id, view: view.rawValue), art.has(path) else { continue }
                    let torso = catArt.builder.part("torso", view: view.rawValue, look: CatLook(body: body.id)).path
                    let frame = CGRect(x: -pad, y: -pad, width: 1 + 2 * pad, height: 1 + 2 * pad)
                    if let f = fit("\(garment.id) on \(body.id) \(view.rawValue) torso", garment: path, over: torso, frame: frame, variant: false) {
                        out.append(f)
                    }
                }
            }
        }
        return out
    }

    /// Every body garment on every body, over every resting pose in every ear and tail variant and over the walking
    /// torso: on the cat (a puffy life vest or raincoat may stand a little off a thin cat's fur, as painted; on a
    /// variant it is drawn only where the cat is, so it must line up: as little off it as on the base painting), and
    /// covering a fair share of it (the life vest that was only straps).
    @Test func everyGarmentStaysOnTheCat() throws {
        let fits = try garmentFits()
        #expect(fits.count > 3300)
        var found: [String] = []
        for f in fits {
            let torso = f.name.hasSuffix("torso")
            let mostOff = torso ? 0.08 : f.variant ? 0.1 : 0.12
            if f.off > mostOff {
                found.append("\(f.name): \(Int(f.off * 100))% off the cat")
            }
            if f.cover < (torso ? 0.35 : 0.1) {
                found.append("\(f.name): covers only \(Int(f.cover * 100))% of the cat")
            }
        }
        #expect(found.isEmpty, "\(found.count) problems:\n\(found.prefix(40).joined(separator: "\n"))")
    }

    /// A colour in Lab (D65) from sRGB 0-255.
    static func lab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        func linear(_ c: Double) -> Double {
            let v = c / 255
            return v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92
        }
        let (lr, lg, lb) = (linear(r), linear(g), linear(b))
        let x = (0.4124 * lr + 0.3576 * lg + 0.1805 * lb) / 0.9505, y = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
        let z = (0.0193 * lr + 0.1192 * lg + 0.9505 * lb) / 1.089
        func f(_ t: Double) -> Double {
            t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116
        }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    /// Every body garment is the same colour on every body (each body's was painted by its own edit, and some came
    /// out another colour: the Persian's life vest brown, the long-haired slim cat's Christmas jumper bright red;
    /// `tools/asset-pipeline/garments/recolour.py`): the middle of its colours over all its pictures no further from the
    /// garment's usual. A printed garment by its ground, the darker half of it (the black under the skeleton's bones, the
    /// red under the jumper's snowflakes): how much is print differs by body, and the onesie's middle fell on the black
    /// for some cats and among the bones for others (21 Oct). Not the Hawaiian shirt, whose share of flowers differs.
    @Test func everyGarmentIsOneColourOnEveryBody() throws {
        let printed: Set = ["xmasjumper", "pyjamas", "skeleton"]
        var found: [String] = []
        for garment in outfits where garment.slot == .body && garment.id != "hawaiian" {
            var middles: [String: (Double, Double, Double)] = [:]
            for body in catArt.builder.data.bodies {
                var pixels: [(Double, Double, Double)] = []
                for pose in CatPose.allCases {
                    guard let path = OutfitFit.garment(garment, body: body.id, pose: pose), art.has(path),
                          let raster = Self.small(art.url(path)), raster.planes.count == 4 else { continue }
                    let alpha = raster.planes[3]
                    for i in stride(from: 0, to: alpha.count, by: 3) where alpha[i] > 240 {
                        let k = 255 / Double(alpha[i])
                        pixels.append(Self.lab(Double(raster.planes[0][i]) * k, Double(raster.planes[1][i]) * k, Double(raster.planes[2][i]) * k))
                    }
                }
                func middle(_ v: [Double]) -> Double {
                    v.isEmpty ? 0 : v.sorted()[v.count / 2]
                }
                if printed.contains(garment.id), !pixels.isEmpty {
                    let cut = middle(pixels.map(\.0))
                    pixels = pixels.filter { $0.0 <= cut }
                }
                middles[body.id] = (middle(pixels.map(\.0)), middle(pixels.map(\.1)), middle(pixels.map(\.2)))
            }
            func middle(_ v: [Double]) -> Double {
                v.sorted()[v.count / 2]
            }
            let usual = (middle(middles.values.map(\.0)), middle(middles.values.map(\.1)), middle(middles.values.map(\.2)))
            for (body, m) in middles {
                let off = ((m.0 - usual.0) * (m.0 - usual.0) + (m.1 - usual.1) * (m.1 - usual.1) + (m.2 - usual.2) * (m.2 - usual.2)).squareRoot()
                if off > 15 {
                    found.append("\(garment.id) on \(body): \(Int(off)) from its colour on the other cats")
                }
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    /// The outfit nodes drawn now (named "outfit", with nothing above them hidden or faded out), in the cat.
    static func drawn(_ cat: CatNode) -> [SKNode] {
        var out: [SKNode] = []
        cat.enumerateChildNodes(withName: "//outfit") { node, _ in
            var at: SKNode? = node
            while let n = at, n !== cat {
                if n.isHidden || n.alpha < 0.01 {
                    return
                }
                at = n.parent
            }
            out.append(node)
        }
        return out
    }

    /// The node's left-right mirroring in the cat (-1 flipped).
    static func mirrored(_ node: SKNode, in cat: CatNode) -> CGFloat {
        var sign: CGFloat = 1
        var at: SKNode? = node
        while let n = at, n !== cat {
            sign *= n.xScale < 0 ? -1 : 1
            at = n.parent
        }
        return sign
    }

    /// One outfit of each kind (where every outfit goes is measured above) on every body as the game draws it,
    /// standing in each view, walking and running and in every resting pose, facing either way: drawn wherever the cat
    /// can wear it (curled up and stretching too since 21 Oct; glasses never from behind), turned with the cat and
    /// mirrored with it, a hat or glasses or neckwear at the cat's front when it stands, walks or runs, and a hat the
    /// ears go under hiding them (curled up, the hat on the crown covers them by itself).
    @Test func theCatWearsEveryOutfitInEveryStateFacingEitherWay() throws {
        let rig = try art.data("cat/rig.json", as: PuppetRig.self)
        var found: [String] = []
        var checked = 0
        enum State {
            case stand(CatNode.View)
            case film(CatNode.View, CatNode.Gait, Double)
            case pose(CatPose)
        }
        var states: [(String, State)] = CatNode.View.allCases.map { ("stand \($0.rawValue)", .stand($0)) }
        for view in [CatNode.View.side, .tqfront] {
            for gait in [CatNode.Gait.walk, .run] {
                for at in [0.2, 0.7] {
                    states.append(("\(gait == .run ? "run" : "walk") \(view.rawValue) \(at)", .film(view, gait, at)))
                }
            }
        }
        states += CatPose.allCases.map { ("\($0.rawValue)", .pose($0)) }
        for body in catArt.builder.data.bodies {
            let look = catArt.builder.normalized(CatLook(body: body.id))
            let filmed = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
            filmed.loadFilmsNow()
            let kinds = ["beanie", "partyhat", "antlers", "roundglasses", "sunglasses", "bowtie", "pearls", "hoodie", "lifevest"]
            for outfit in outfits where kinds.contains(outfit.id) {
                let kind = OutfitFit.kind(outfit)
                // Where it is facing left, to see it mirrored facing right.
                var leftAt: [String: [CGPoint]] = [:]
                for right in [false, true] {
                    // One cat through every state in turn: standing, walking and running, then resting.
                    let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
                    cat.shareFilms(from: filmed)
                    cat.wear(outfit)
                    var clock = 0.0
                    for (name, state) in states {
                        var moving = true, poseOf: CatPose?
                        switch state {
                        case let .stand(view):
                            cat.stopCycle()
                            cat.show(view, facingRight: right)
                            cat.step(0)
                            moving = view != .front
                        case let .film(view, gait, at):
                            cat.show(view, facingRight: right)
                            cat.move(gait)
                            let seconds = catArt.film(body: body.id, view: view.rawValue, gait: gait == .run ? "run" : "walk")?.seconds ?? 1
                            // To this point of the loop from wherever the last state left it.
                            let to = seconds * at, step = (to - clock.truncatingRemainder(dividingBy: seconds) + seconds).truncatingRemainder(dividingBy: seconds)
                            cat.step(0.001)
                            cat.step(step)
                            clock = to
                        case let .pose(pose):
                            cat.show(pose == .sitBack ? .tqfront : .side, facingRight: right)
                            cat.settle(into: pose, duration: 0)
                            cat.step(0)
                            poseOf = pose
                            moving = false
                        }
                        checked += 1
                        let label = "\(outfit.id) on \(body.id) \(name) facing \(right ? "right" : "left")"
                        let nodes = Self.drawn(cat)
                        let bare = kind == .glasses && poseOf == .sitBack
                        if bare {
                            if !nodes.isEmpty {
                                found.append("\(label): drawn")
                            }
                            continue
                        }
                        guard !nodes.isEmpty else {
                            found.append("\(label): not drawn")
                            continue
                        }
                        for node in nodes where Self.mirrored(node, in: cat) != (right ? -1 : 1) {
                            found.append("\(label): not turned with the cat")
                        }
                        // A hat, glasses or neckwear at the head's end: the cat's front.
                        let drawing = cat.calculateAccumulatedFrame()
                        let places = nodes.map { $0.convert(CGPoint.zero, to: cat) }
                        if kind != nil, moving {
                            for at in places where (at.x > drawing.midX) != right {
                                found.append("\(label): at the back end of the cat")
                            }
                        }
                        // Facing right, where it was facing left on the cat, mirrored: as a share of the cat's outline (a
                        // painting turns about its own anchor, not the cat's feet, and the cat breathes in between).
                        let across = places.map {
                            CGPoint(
                                x: (right ? drawing.maxX - $0.x : $0.x - drawing.minX) / max(1, drawing.width),
                                y: ($0.y - drawing.minY) / max(1, drawing.height)
                            )
                        }
                            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
                        if !right {
                            leftAt[name] = across
                        } else if let left = leftAt[name] {
                            if across.count != left.count || zip(across, left).contains(where: { abs($0.x - $1.x) > 0.01 || abs($0.y - $1.y) > 0.02 }) {
                                found.append("\(label): not where it is facing left, mirrored")
                            }
                        }
                        if OutfitFit.coversEars(outfit), kind == .hat, poseOf.map(OutfitFit.hidesUnderHat) ?? true {
                            for node in nodes {
                                let under = (node.parent as? SKSpriteNode)?.shader != nil
                                if !under {
                                    found.append("\(label): the ears are not under the hat")
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(checked > 2000)
        #expect(found.isEmpty, "\(found.count) problems:\n\(found.prefix(40).joined(separator: "\n"))")
    }

    @Test func writeTheReport() throws {
        guard let file = ProcessInfo.processInfo.environment["HOUSECAT_OUTFIT_REPORT"] else { return }
        var lines = ["outfit,kind,picture,path,view,film,frame,placed,width,dx,dy,angle,headWidth,px,py,pw"]
        for m in allMeasures() {
            let kind = switch m.kind {
            case .hat: "hat"
            case .glasses: "glasses"
            case .neck: "neck"
            }
            lines.append([
                m.outfit, kind, m.picture.name, m.picture.path, m.picture.view, m.picture.film ?? "", m.picture.frame.map(String.init) ?? "",
                m.placed ? "1" : "0", String(format: "%.3f", m.width), String(format: "%.3f", m.dx), String(format: "%.3f", m.dy),
                String(format: "%.3f", m.angle), String(format: "%.1f", m.headWidth), String(format: "%.1f", m.point.x),
                String(format: "%.1f", m.point.y), String(format: "%.1f", m.pictureWidth),
            ].joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
        let garments = try garmentFits().map { "\($0.name),\(String(format: "%.3f", $0.off)),\(String(format: "%.3f", $0.cover)),\($0.variant)" }
        try (["garment,off,cover,variant"] + garments).joined(separator: "\n")
            .write(toFile: file.replacingOccurrences(of: ".csv", with: "_garments.csv"), atomically: true, encoding: .utf8)
    }
}
