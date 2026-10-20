import CoreGraphics
import Foundation
import HouseCatCore

/// Where a cat's face and head are in one of its sprites, from the builder's features mask (red and green the
/// irises, blue the nose) and the sprite's alpha: fractions of the sprite, origin top left. What outfits are
/// fitted by.
public struct CatFace: Equatable, Sendable {
    /// The irises' centres, left to right: two in a front or three-quarter view, one in a profile, none from
    /// behind or asleep.
    public var eyes: [CGPoint]
    public var nose: CGPoint?
    /// The head's outline across the eye line: its left and right edges (x) on that row (y).
    public var head: (left: CGFloat, right: CGFloat, y: CGFloat)?
    /// The top of the skull above the middle of the head.
    public var crown: CGPoint?
    /// The neck under the chin: its edges on that row.
    public var neck: (left: CGFloat, right: CGFloat, y: CGFloat)?
    /// The sprite's size in pixels, so distances are measured in one unit.
    public var size: CGSize

    public static func == (a: CatFace, b: CatFace) -> Bool {
        a.eyes == b.eyes && a.nose == b.nose && a.crown == b.crown && a.size == b.size
            && a.head?.left == b.head?.left && a.head?.right == b.head?.right && a.head?.y == b.head?.y
            && a.neck?.left == b.neck?.left && a.neck?.right == b.neck?.right && a.neck?.y == b.neck?.y
    }
}

public extension CatFace {
    /// The same face moved by a distance in the sprite's pixels (x right, y down).
    func moved(by d: CGVector) -> CatFace {
        let dx = d.dx / max(1, size.width), dy = d.dy / max(1, size.height)
        var face = self
        face.eyes = eyes.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        face.nose = nose.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        face.head = head.map { (left: $0.left + dx, right: $0.right + dx, y: $0.y + dy) }
        face.crown = crown.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        face.neck = neck.map { (left: $0.left + dx, right: $0.right + dx, y: $0.y + dy) }
        return face
    }
}

/// The shape of an outfit picture, measured once from its alpha: a hat's rim, glasses' lenses, neckwear's top.
/// Fractions of the picture, origin top left.
public struct OutfitShape: Equatable, Sendable {
    /// The middle of the bottom edge (a hat's rim) and the picture's painted width.
    public var rim: CGPoint
    public var rimWidth: CGFloat
    /// The middle of the top edge (a scarf's or collar's band) and the painted width again.
    public var top: CGPoint
    public var topWidth: CGFloat
    /// The holes the paint goes round, largest first (glasses' lenses).
    public var lenses: [CGPoint]
    public var size: CGSize
}

/// Fits an outfit to a cat (Josh, 18 Oct: the cat must wear what it is sold; SPEC "outfits are layered over any
/// look and never painted per cat"), from the head's own outline in each sprite, so it follows every body, breed,
/// kitten and pose: a hat's rim across the head between the eyes and the crown, as wide as the head; glasses' lenses
/// on the eyes; neckwear's band round the neck under the chin; all tilted with the eye line. Body garments are
/// painted for a standing cat and are not fitted.
public enum OutfitFit {
    public struct Placement: Equatable, Sendable {
        /// The point the outfit's anchor goes on, in sprite pixels from the top left.
        public var point: CGPoint
        /// The outfit's width in sprite pixels.
        public var width: CGFloat
        /// Radians, clockwise on screen.
        public var angle: CGFloat
        /// Where on the outfit picture that point is: fractions, origin bottom left (SpriteKit's anchor point).
        public var anchor: CGPoint
    }

    public enum Kind: Sendable {
        case hat
        case glasses
        case neck
    }

    public static func kind(_ outfit: OutfitsFile.Outfit) -> Kind? {
        switch outfit.slot {
        case .head: outfit.id.contains("glasses") ? .glasses : .hat
        case .neck: .neck
        case .body: nil
        }
    }

    /// Whether a hat sits higher on this look (tall ears, catbuilder.json's `outfits.tall_ears`).
    public static func tallEars(_ look: CatLook) -> Bool {
        Tuning.Outfits.tallEars.contains(look.body) || Tuning.Outfits.tallEars.contains(look.ears)
    }

    /// Whether a hat is lifted for this look's tall ears when wearing this outfit: not one the ears go under.
    public static func tallEars(_ look: CatLook, wearing outfit: OutfitsFile.Outfit) -> Bool {
        tallEars(look) && !coversEars(outfit)
    }

    /// Off only to draw the cat as it was before hats covered the ears (the fit sheets' before pictures).
    nonisolated(unsafe) public static var coversEarsOn = true

    /// Whether the cat's own ears go under this outfit (outfits.json `coversEars`: a hat with knitted ears, a cap, a
    /// brimmed hat), so they are hidden where it covers them (`EarCover`).
    public static func coversEars(_ outfit: OutfitsFile.Outfit) -> Bool {
        coversEarsOn && kind(outfit) == .hat && outfit.coversEars == true
    }

    /// Where a hat the ears go under hides the cat (Josh, 20 Oct: "show two sets of ears": a beanie's knitted ears
    /// sat beside the cat's own, a brim had ears through it): everything above the hat's rim, across the head and
    /// its ears either side, in the sprite's pixels from the top left. The head under the rim is the hat's to cover.
    public struct EarCover: Equatable, Sendable {
        /// A point on the rim's line, the way up from it (a unit vector, y down) and how far either side of it.
        public var origin: CGPoint
        public var up: CGVector
        public var half: CGFloat

        /// How much of a point is hidden (0 to 1), feathered over a pixel or two at the edges.
        public func hides(_ p: CGPoint) -> CGFloat {
            let dx = p.x - origin.x, dy = p.y - origin.y
            let above = dx * up.dx + dy * up.dy
            let along = abs(dx * -up.dy + dy * up.dx)
            func ramp(_ v: CGFloat) -> CGFloat {
                min(1, max(0, (v + 1.5) / 3))
            }
            return ramp(above) * ramp(half - along)
        }
    }

    /// The ear cover for a hat placed on a face (`place`'s placement): the rim's line a little above the rim, as
    /// wide as the head and its ears either side (Tuning.Outfits.earCoverWidth head widths each way).
    public static func earCover(_ fit: Placement, shape: OutfitShape, on face: CatFace, view: String? = nil) -> EarCover? {
        let t = Tuning.Outfits.self
        let w = face.size.width, h = face.size.height
        let eyes = profileEyes(face, view: view)
        guard let (left, right) = headSpan(face, eyes: eyes, w: w, h: h) else { return nil }
        // Up the picture, turned as the hat is (its angle is clockwise on screen, y down).
        let up = CGVector(dx: sin(fit.angle), dy: -cos(fit.angle))
        let tall = fit.width * shape.size.height / max(1, shape.size.width)
        let rise = tall * CGFloat(t.earCoverRise)
        let origin = CGPoint(x: fit.point.x + up.dx * rise, y: fit.point.y + up.dy * rise)
        return EarCover(origin: origin, up: up, half: (right - left) * CGFloat(t.earCoverWidth))
    }

    /// Lying down, the chin rests on the paws: neckwear is cut to the cat's outline (tucked under, never hanging
    /// below the floor).
    public static func tucksNeckwear(_ pose: CatPose) -> Bool {
        pose == .loafSide || pose == .loafThreeQuarterFront
    }

    /// The outfit picture for a pose (its view), or nil for a pose an outfit is not drawn on (curled asleep or
    /// mid-stretch, eyes shut).
    public static func view(for pose: CatPose) -> String? {
        switch pose {
        case .sitFront: "front"
        case .sitBack: "tqback"
        case .sitThreeQuarterFront, .loafThreeQuarterFront: "tqfront"
        case .sitSide, .loafSide: "side"
        // Eyes shut: the face cannot be found, and these are brief.
        case .sleepCurl, .stretchSide: nil
        }
    }

    /// Where an outfit goes on a face, or nil when this face cannot carry it.
    /// `size` is the outfit's own width against the head (a hat) or the neck (neckwear), outfits.json's `fit`.
    /// `view` is the outfit picture's view, for glasses whose lenses cannot be found (solid sunglasses, a lens seen
    /// edge on).
    public static func place(
        _ kind: Kind,
        shape: OutfitShape,
        on face: CatFace,
        view: String? = nil,
        size: Double? = nil,
        tallEars: Bool = false,
        coversEars: Bool = false
    ) -> Placement? {
        let t = Tuning.Outfits.self
        let w = face.size.width, h = face.size.height
        let pw = shape.size.width, ph = shape.size.height
        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * w, y: p.y * h)
        }
        func anchor(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: 1 - p.y)
        }
        // Side-on, a second eye is the far one peeking past the nose (the long-haired cats): a hat or neckwear
        // measured between the two was a fraction of the head and tilted (Josh, 20 Oct: "dont fit at all"), so
        // side-on they go by the near eye alone, as a profile. The glasses find the near eye below.
        let eyes = kind == .glasses ? face.eyes.map(px) : profileEyes(face, view: view)
        let angle: CGFloat = eyes.count >= 2 ? atan2(eyes[1].y - eyes[0].y, eyes[1].x - eyes[0].x) : 0
        switch kind {
        case .hat:
            guard let (left, right) = headSpan(face, eyes: eyes, w: w, h: h), let head = face.head, var crown = face.crown.map(px)
            else { return nil }
            let row = head.y * h
            let width = right - left
            // Side-on, the crown straight up from the head's middle is an ear's tip. A hat the ears go under sits on the
            // skull instead: no higher than its share of the head's length above the eye (the ear-less profile heads).
            if coversEars, view == "side" || eyes.count == 1 {
                crown.y = max(crown.y, row - width * CGFloat(t.profileSkull))
            }
            guard width > 1, shape.rimWidth > 0 else { return nil }
            // A headband painted side-on (much taller than wide): sized by its height over the head, its end down
            // by the cheek, so the band runs up the side of the head with the antler above. (From behind there is
            // no eye line to measure from, and the back's pictures are not side-on.)
            let lift = eyes.isEmpty ? 0 : row - crown.y
            if ph > pw * CGFloat(t.bandAspect), lift > 0 {
                var point = CGPoint(x: (left + right) / 2, y: row + lift * CGFloat(t.bandDrop))
                // Side-on, the band goes over the head behind the eye, not down across it (Josh, 20 Oct: outfits
                // "dont fit at all"): moved back towards the ears.
                if eyes.count == 1, let eye = eyes.first {
                    point.x += (point.x >= eye.x ? 1 : -1) * width * CGFloat(t.bandBack)
                }
                return Placement(point: point, width: lift * CGFloat(t.bandHeight) * pw / ph, angle: angle, anchor: anchor(shape.rim))
            }
            // The rim: across the head, part way from the eye line up to the crown.
            // Tall ears lift a hat that has holes for them; side-on the crown is already the ear's tip.
            let rise = (row - crown.y) * CGFloat(t.hatRise + (tallEars && eyes.count != 1 ? t.tallEarsLift : 0))
            let point = CGPoint(x: (left + right) / 2, y: row - rise)
            var pictureWidth = width * CGFloat(size ?? t.hatWidth) / shape.rimWidth
            // No taller than a hat can be over this head: a headband painted side-on is narrow, so sized by its
            // width it would tower over the cat.
            let tallest = lift * CGFloat(t.hatMaxHeight)
            if tallest > 0, shape.size.height > 0 {
                pictureWidth = min(pictureWidth, tallest * pw / ph)
            }
            return Placement(point: point, width: pictureWidth, angle: angle, anchor: anchor(shape.rim))
        case .glasses:
            // The lenses found in the picture, or where they sit in a pair painted for this view.
            let lenses = shape.lenses.count >= 2 ? shape.lenses : (view.flatMap { t.lenses[$0] }?.map { CGPoint(x: $0[0], y: $0[1]) } ?? [])
            // A profile can show the far eye peeking past the nose: the glasses go on the near one, further back.
            if view == "side", eyes.count >= 2, let head = face.head {
                let nose = face.nose.map(px)
                let near = eyes.max { a, b in
                    if let nose { return hypot(a.x - nose.x, a.y - nose.y) < hypot(b.x - nose.x, b.y - nose.y) }
                    return min(a.x - head.left * w, head.right * w - a.x) < min(b.x - head.left * w, head.right * w - b.x)
                }
                if let near {
                    let width = (head.right - head.left) * w * CGFloat(t.profileGlassesWidth)
                    return Placement(point: near, width: width, angle: 0, anchor: anchor(CGPoint(x: t.profileLens[0], y: t.profileLens[1])))
                }
            }
            if eyes.count >= 2, lenses.count >= 2 {
                let a = CGPoint(x: lenses[0].x * pw, y: lenses[0].y * ph)
                let b = CGPoint(x: lenses[1].x * pw, y: lenses[1].y * ph)
                let (l, r) = a.x < b.x ? (a, b) : (b, a)
                let lensSpan = hypot(r.x - l.x, r.y - l.y)
                let eyeSpan = hypot(eyes[1].x - eyes[0].x, eyes[1].y - eyes[0].y)
                guard lensSpan > 1 else { return nil }
                let scale = eyeSpan / lensSpan * CGFloat(t.lensFit)
                let middle = CGPoint(x: (eyes[0].x + eyes[1].x) / 2, y: (eyes[0].y + eyes[1].y) / 2)
                let lensAngle = atan2(r.y - l.y, r.x - l.x)
                let lensMiddle = CGPoint(x: (l.x + r.x) / 2 / pw, y: (l.y + r.y) / 2 / ph)
                return Placement(point: middle, width: pw * scale, angle: angle - lensAngle, anchor: anchor(lensMiddle))
            }
            // A profile: the lens, seen edge on at the front of the picture, on the one eye; the arm runs back
            // over the head.
            guard eyes.count == 1, let eye = eyes.first, let head = face.head else { return nil }
            let width = (head.right - head.left) * w * CGFloat(t.profileGlassesWidth)
            return Placement(point: eye, width: width, angle: 0, anchor: anchor(CGPoint(x: t.profileLens[0], y: t.profileLens[1])))
        case .neck:
            guard let neck = face.neck, shape.topWidth > 0 else { return nil }
            var left = neck.left * w, right = neck.right * w
            // No wider than the head allows (a loaf's neck runs into its body under the chin).
            if let (hl, hr) = headSpan(face, eyes: eyes, w: w, h: h), right - left > (hr - hl) * CGFloat(t.neckToHead) {
                let half = (hr - hl) * CGFloat(t.neckToHead) / 2, middle = (hl + hr) / 2
                left = middle - half
                right = middle + half
            }
            let point = CGPoint(x: (left + right) / 2, y: neck.y * h)
            var pictureWidth = (right - left) * CGFloat(size ?? t.neckWidth) / shape.topWidth
            // No longer than the head allows: a necklace seen side-on is a narrow strand, so sized by its width
            // it would hang to the floor; a strand (much taller than wide: the pearls) no longer than a head.
            if let (hl, hr) = headSpan(face, eyes: eyes, w: w, h: h), ph > 0 {
                let longest = ph > pw * CGFloat(t.strandAspect) ? t.strandMaxHeight : t.neckMaxHeight
                pictureWidth = min(pictureWidth, (hr - hl) * CGFloat(longest) * pw / ph)
            }
            let band = CGPoint(x: shape.top.x, y: min(1, shape.top.y + CGFloat(t.neckBandDrop)))
            return Placement(point: point, width: pictureWidth, angle: angle, anchor: anchor(band))
        }
    }

    /// The eyes in pixels; side-on only the near one (the far one peeking past the nose is closer to it).
    static func profileEyes(_ face: CatFace, view: String?) -> [CGPoint] {
        let w = face.size.width, h = face.size.height
        let eyes = face.eyes.map { CGPoint(x: $0.x * w, y: $0.y * h) }
        guard view == "side", eyes.count >= 2 else { return eyes }
        if let nose = face.nose.map({ CGPoint(x: $0.x * w, y: $0.y * h) }) {
            return eyes.max { hypot($0.x - nose.x, $0.y - nose.y) < hypot($1.x - nose.x, $1.y - nose.y) }.map { [$0] } ?? eyes
        }
        guard let head = face.head else { return [eyes[0]] }
        // No nose: the near eye is the one further in from the head's edges.
        return eyes.max { a, b in
            min(a.x - head.left * w, head.right * w - a.x) < min(b.x - head.left * w, head.right * w - b.x)
        }.map { [$0] } ?? eyes
    }

    /// The head's left and right edges in pixels: its outline at the eye line, no wider than the eyes allow (a
    /// loaf's head runs into its body there), a profile's centred a little behind its eye.
    static func headSpan(_ face: CatFace, eyes: [CGPoint], w: CGFloat, h: CGFloat) -> (CGFloat, CGFloat)? {
        let t = Tuning.Outfits.self
        guard let head = face.head else { return nil }
        let left = head.left * w, right = head.right * w
        if eyes.count >= 2 {
            let cap = hypot(eyes[1].x - eyes[0].x, eyes[1].y - eyes[0].y) * CGFloat(t.headToEyes)
            guard right - left > cap else { return (left, right) }
            let middle = (eyes[0].x + eyes[1].x) / 2
            return (middle - cap / 2, middle + cap / 2)
        }
        if let eye = eyes.first, let nose = face.nose.map({ CGPoint(x: $0.x * w, y: $0.y * h) }) {
            // Eye to nose straight (a flat face has its nose under the eye, not in front of it).
            let cap = hypot(eye.x - nose.x, eye.y - nose.y) * CGFloat(t.headToEyeNose)
            guard right - left > cap else { return (left, right) }
            let back: CGFloat = eye.x > nose.x ? 1 : -1
            let middle = eye.x + back * cap * CGFloat(t.profileHeadBack)
            return (middle - cap / 2, middle + cap / 2)
        }
        return (left, right)
    }

    // MARK: Measuring

    /// The face and head in a features mask and alpha (planes as stored), as fractions.
    /// `headOnly`: the picture is a head on its own (the puppet's), where two eyes close together on it are a
    /// profile with the far eye peeking past the nose.
    public static func face(features: [[UInt8]], alpha: [UInt8], width: Int, height: Int, headOnly: Bool = false) -> CatFace {
        let t = Tuning.Outfits.self
        func centroid(_ plane: [UInt8]) -> CGPoint? {
            var sx = 0, sy = 0, n = 0
            for y in stride(from: 0, to: height, by: 2) {
                let row = y * width
                for x in stride(from: 0, to: width, by: 2) where plane[row + x] > 127 {
                    sx += x
                    sy += y
                    n += 1
                }
            }
            guard n >= t.minimumFeaturePixels else { return nil }
            return CGPoint(x: CGFloat(sx) / CGFloat(n), y: CGFloat(sy) / CGFloat(n))
        }
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && x < width && y >= 0 && y < height && alpha[y * width + x] > 127
        }
        // The opaque run on a row through a column: its left and right edges.
        func run(through x: Int, row y: Int) -> (Int, Int)? {
            guard opaque(x, y) else { return nil }
            var l = x, r = x
            while opaque(l - 1, y) {
                l -= 1
            }
            while opaque(r + 1, y) {
                r += 1
            }
            return (l, r)
        }
        var eyes = features.prefix(2).compactMap(centroid).sorted { $0.x < $1.x }
        var nose = features.count > 2 ? centroid(features[2]) : nil
        // A nose above the eyes is the mask's mistake (an ear's pink inside taken for it, on some side paintings):
        // measured from it the head was a fraction of its size (Josh, 20 Oct: outfits that "dont fit at all").
        if let n = nose, let top = eyes.map(\.y).min(), n.y < top {
            nose = nil
        }
        // The head's outline across the eyes (or the nose, or near the top when neither shows).
        var head: (CGFloat, CGFloat, CGFloat)?
        var crown: CGPoint?
        var neck: (CGFloat, CGFloat, CGFloat)?
        let anchor: CGPoint? = eyes.isEmpty ? nose : CGPoint(
            x: eyes.map(\.x).reduce(0, +) / CGFloat(eyes.count),
            y: eyes.map(\.y).reduce(0, +) / CGFloat(eyes.count)
        )
        if let anchor, let (l, r) = run(through: Int(anchor.x), row: Int(anchor.y)) {
            head = (CGFloat(l), CGFloat(r), anchor.y)
        } else if eyes.isEmpty, nose == nil {
            // From behind: the head is the top of the sprite, below any tall ears (tufts make the first rows narrow).
            if let top = (0 ..< height).first(where: { y in (0 ..< width).contains { opaque($0, y) } }) {
                var row = top + Int(Double(height) * t.backHeadDrop)
                let wide = Int(Double(width) * t.backHeadMinWidth), lowest = Int(Double(height) * t.backHeadLowest)
                while row < lowest {
                    let xs = (0 ..< width).filter { opaque($0, row) }
                    if let mid = xs.isEmpty ? nil : xs[xs.count / 2], let (l, r) = run(through: mid, row: row), r - l >= wide {
                        head = (CGFloat(l), CGFloat(r), CGFloat(row))
                        break
                    }
                    row += 2
                }
            }
        }
        // A profile lying down: the row through the eye runs on into the body the chin rests against, so the
        // head is no longer than it can be from the eye's distance to the front of the face, on the far side.
        if eyes.count == 1, let eye = eyes.first, let (l, r, y) = head {
            let longest = min(eye.x - l, r - eye.x) * CGFloat(t.profileHeadToFront)
            if longest > 0, r - l > longest {
                head = eye.x - l < r - eye.x ? (l, l + longest, y) : (r - longest, r, y)
            }
        }
        if let (l, r, y) = head {
            // The crown straight up from the head's middle.
            let column = Int((l + r) / 2)
            var top = Int(y)
            while top > 0, opaque(column, top - 1) {
                top -= 1
            }
            crown = CGPoint(x: CGFloat(column), y: CGFloat(top))
            // The neck: under the chin, below the nose by part of the eye span (sleepy eyes sit lower, so not the
            // eyes' height). A puppet's head ends at the chin, so where the row is past the picture the neck is
            // as wide as the head allows, centred under it.
            func neckAt(_ estimate: Int) -> (CGFloat, CGFloat, CGFloat) {
                // A head on its own ends at the neck: the chin is no higher than the picture's bottom under the face
                // (where the outline narrows to the chin's tip, so the neck takes the head's width).
                var chin = estimate, atBottom = false
                if headOnly {
                    var bottom = Int(y)
                    while bottom + 1 < height, opaque(column, bottom + 1) {
                        bottom += 1
                    }
                    if bottom > chin {
                        chin = bottom
                        atBottom = true
                    }
                }
                if !atBottom, chin < height, let (nl, nr) = run(through: column, row: chin) {
                    return (CGFloat(nl), CGFloat(nr), CGFloat(chin))
                }
                let half = (r - l) * CGFloat(t.neckToHead) / 2
                return ((l + r) / 2 - half, (l + r) / 2 + half, CGFloat(chin))
            }
            let span = eyes.count >= 2 ? hypot(eyes[1].x - eyes[0].x, eyes[1].y - eyes[0].y) : 0
            // Two eyes close together on a wide head: a profile with the far eye peeking past the nose.
            let peeking = headOnly && span > 0 && span < (r - l) * CGFloat(t.profileEyeSpan)
            if let nose, eyes.count >= 2, !peeking {
                // Below the nose; a flat face has its nose high, between the eyes, so there well below the eyes.
                let eyeRow = (eyes[0].y + eyes[1].y) / 2
                let flat = nose.y - eyeRow < span * CGFloat(t.flatNose)
                neck = neckAt(Int(max(nose.y + span * CGFloat(t.chinDrop), flat ? eyeRow + span * CGFloat(t.chinBelowEyes) : 0)))
            } else if !eyes.isEmpty || nose != nil {
                neck = neckAt(Int(y + (r - l) * CGFloat(t.profileChinDrop)))
            }
        }
        let w = CGFloat(width), h = CGFloat(height)
        eyes = eyes.map { CGPoint(x: $0.x / w, y: $0.y / h) }
        return CatFace(
            eyes: eyes,
            nose: nose.map { CGPoint(x: $0.x / w, y: $0.y / h) },
            head: head.map { (left: $0.0 / w, right: $0.1 / w, y: $0.2 / h) },
            crown: crown.map { CGPoint(x: $0.x / w, y: $0.y / h) },
            neck: neck.map { (left: $0.0 / w, right: $0.1 / w, y: $0.2 / h) },
            size: CGSize(width: w, height: h)
        )
    }

    /// An outfit picture's rim, band and lenses, from its alpha.
    public static func shape(alpha: [UInt8], width: Int, height: Int) -> OutfitShape {
        func opaque(_ x: Int, _ y: Int) -> Bool {
            alpha[y * width + x] > 127
        }
        // The painted extent.
        var minX = width, maxX = 0, first = height, last = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) where opaque(x, y) {
                minX = min(minX, x)
                maxX = max(maxX, x)
                first = min(first, y)
                last = max(last, y)
            }
        }
        if minX > maxX {
            (minX, maxX, first, last) = (0, width - 1, 0, height - 1)
        }
        // The bottom and top edges as the median over the middle columns (a slanted rim's middle, not its corner).
        let inset = Int(Double(maxX - minX) * Tuning.Outfits.edgeInset)
        var bottoms: [Int] = [], tops: [Int] = []
        for x in stride(from: minX + inset, through: max(minX + inset, maxX - inset), by: 2) {
            if let top = (first ... last).first(where: { opaque(x, $0) }) {
                tops.append(top)
                bottoms.append((first ... last).last(where: { opaque(x, $0) }) ?? last)
            }
        }
        func median(_ values: [Int], _ fallback: Int) -> CGFloat {
            values.isEmpty ? CGFloat(fallback) : CGFloat(values.sorted()[values.count / 2])
        }
        let middle = CGFloat(minX + maxX) / 2
        let bl = CGFloat(minX), br = CGFloat(maxX), tl = CGFloat(minX), tr = CGFloat(maxX)
        let rimY = median(bottoms, last), topY = median(tops, first)
        // Holes: clear pixels the outside cannot reach (filled from the border), grouped, largest first.
        let step = 2, gw = (width + step - 1) / step, gh = (height + step - 1) / step
        var reached = [Bool](repeating: false, count: gw * gh)
        func clear(_ gx: Int, _ gy: Int) -> Bool {
            !opaque(min(width - 1, gx * step), min(height - 1, gy * step))
        }
        var queue: [(Int, Int)] = []
        for gx in 0 ..< gw {
            queue.append((gx, 0))
            queue.append((gx, gh - 1))
        }
        for gy in 0 ..< gh {
            queue.append((0, gy))
            queue.append((gw - 1, gy))
        }
        while let (x, y) = queue.popLast() {
            guard x >= 0, x < gw, y >= 0, y < gh, !reached[y * gw + x], clear(x, y) else { continue }
            reached[y * gw + x] = true
            queue.append(contentsOf: [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
        }
        var seen = reached
        var holes: [(count: Int, centre: CGPoint)] = []
        for gy in 0 ..< gh {
            for gx in 0 ..< gw where !seen[gy * gw + gx] && clear(gx, gy) {
                var stack = [(gx, gy)], n = 0, sx = 0, sy = 0
                seen[gy * gw + gx] = true
                while let (x, y) = stack.popLast() {
                    n += 1
                    sx += x
                    sy += y
                    for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                        where nx >= 0 && nx < gw && ny >= 0 && ny < gh && !seen[ny * gw + nx] && clear(nx, ny)
                    {
                        seen[ny * gw + nx] = true
                        stack.append((nx, ny))
                    }
                }
                holes.append((n, CGPoint(x: CGFloat(sx * step) / CGFloat(n), y: CGFloat(sy * step) / CGFloat(n))))
            }
        }
        let minimum = Tuning.Outfits.minimumLensCells
        let lenses = holes.filter { $0.count >= minimum }.sorted { $0.count > $1.count }.prefix(2).map(\.centre)
        let w = CGFloat(width), h = CGFloat(height)
        return OutfitShape(
            rim: CGPoint(x: middle / w, y: rimY / h),
            rimWidth: (br - bl) / w,
            top: CGPoint(x: middle / w, y: topY / h),
            topWidth: (tr - tl) / w,
            lenses: lenses.map { CGPoint(x: $0.x / w, y: $0.y / h) },
            size: CGSize(width: w, height: h)
        )
    }

    // MARK: Body garments

    /// A body garment is painted for each body, not fitted: over each resting pose (a picture the size of the pose's
    /// base painting, drawn exactly over it) and over the puppet's torso in each view (the torso's size with
    /// `Tuning.Outfits.torsoPad` of it added on every side). Nil for a pose it is not painted for (curled asleep or
    /// mid-stretch).
    public static func garment(_ outfit: OutfitsFile.Outfit, body: String, pose: CatPose) -> String? {
        guard outfit.slot == .body, view(for: pose) != nil else { return nil }
        return "outfits/body/outfit_\(outfit.id)_\(body)_\(pose.rawValue).png"
    }

    public static func garment(_ outfit: OutfitsFile.Outfit, body: String, view: String) -> String? {
        guard outfit.slot == .body else { return nil }
        return "outfits/body/outfit_\(outfit.id)_\(body)_\(view)_torso.png"
    }

    /// A body garment drawn over a picture of the cat, in `frame` (fractions of the picture, origin top left).
    public static func dress(_ cat: CGImage, garment: CGImage, frame: CGRect) -> CGImage? {
        let w = CGFloat(cat.width), h = CGFloat(cat.height)
        guard let context = CGContext(
            data: nil, width: cat.width, height: cat.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cat, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.draw(garment, in: CGRect(x: frame.minX * w, y: (1 - frame.maxY) * h, width: frame.width * w, height: frame.height * h))
        return context.makeImage()
    }

    // MARK: Pictures

    /// A picture of the cat with its outfit drawn on (the player's plaque, the widget's poses). The canvas grows
    /// at the top when a hat stands above the cat; `extra` is how many pixels it grew.
    public static func compose(
        _ cat: CGImage,
        face: CatFace,
        outfit: CGImage,
        shape: OutfitShape,
        kind: Kind,
        view: String? = nil,
        size: Double? = nil,
        tallEars: Bool = false,
        pose: CatPose? = nil,
        coversEars: Bool = false
    ) -> (image: CGImage, extra: Int)? {
        let w = CGFloat(cat.width), h = CGFloat(cat.height)
        var scaled = face
        scaled.size = CGSize(width: w, height: h)
        guard let fit = place(kind, shape: shape, on: scaled, view: view, size: size, tallEars: tallEars, coversEars: coversEars) else { return nil }
        let ow = fit.width, oh = ow * CGFloat(outfit.height) / CGFloat(max(1, outfit.width))
        // How far the outfit reaches above the picture (its top, from its anchor, roughly upright).
        let above = max(0, (1 - fit.anchor.y) * oh - fit.point.y)
        let extra = Int(above.rounded(.up))
        guard let context = CGContext(
            data: nil, width: cat.width, height: cat.height + extra, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cat, in: CGRect(x: 0, y: 0, width: w, height: h))
        // A hat the ears go under: the cat cleared above its rim, across the head and ears (the hat covers the rest).
        if coversEars, kind == .hat, let cover = earCover(fit, shape: shape, on: scaled, view: view) {
            let along = CGVector(dx: -cover.up.dy, dy: cover.up.dx)
            let reach = w + h
            let corners = [
                CGPoint(x: cover.origin.x - along.dx * cover.half, y: cover.origin.y - along.dy * cover.half),
                CGPoint(x: cover.origin.x + along.dx * cover.half, y: cover.origin.y + along.dy * cover.half),
                CGPoint(x: cover.origin.x + along.dx * cover.half + cover.up.dx * reach, y: cover.origin.y + along.dy * cover.half + cover.up.dy * reach),
                CGPoint(x: cover.origin.x - along.dx * cover.half + cover.up.dx * reach, y: cover.origin.y - along.dy * cover.half + cover.up.dy * reach),
            ].map { CGPoint(x: $0.x, y: h - $0.y) }
            context.saveGState()
            context.setBlendMode(.clear)
            context.addLines(between: corners)
            context.closePath()
            context.fillPath()
            context.restoreGState()
        }
        // Into the context's bottom-left frame: the fit point, then the outfit round its anchor, turned.
        func drawOutfit(_ into: CGContext) {
            into.saveGState()
            into.translateBy(x: fit.point.x, y: h - fit.point.y)
            into.rotate(by: -fit.angle)
            into.draw(outfit, in: CGRect(x: -fit.anchor.x * ow, y: -fit.anchor.y * oh, width: ow, height: oh))
            into.restoreGState()
        }
        if kind == .neck, pose.map(tucksNeckwear) == true, let layer = CGContext(
            data: nil, width: cat.width, height: cat.height + extra, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            // Only where the cat is.
            drawOutfit(layer)
            layer.setBlendMode(.destinationIn)
            layer.draw(cat, in: CGRect(x: 0, y: 0, width: w, height: h))
            layer.setBlendMode(.normal)
            layer.clear(CGRect(x: 0, y: h, width: w, height: CGFloat(extra)))
            if let tucked = layer.makeImage() {
                context.draw(tucked, in: CGRect(x: 0, y: 0, width: w, height: h + CGFloat(extra)))
            }
        } else {
            drawOutfit(context)
        }
        return context.makeImage().map { ($0, extra) }
    }
}

/// Where a resting pose's body garment goes on the painting drawn: the pose's ear and tail variants (folded,
/// tufted, bobtail ...) are cropped to their own outline, so the base painting the garment was painted over sits
/// somewhere inside them (outfits/body/variants.json, from tools/app-assets/garment_offsets.py).
@MainActor
public enum GarmentPlacement {
    private struct File: Decodable {
        var offsets: [String: [Double]]
    }

    private static var offsets: [String: [Double]]?

    /// The garment's rectangle on the drawn painting `drawn`, as fractions of it (origin top left).
    public static func frame(drawn: String, base: String, catArt: CatArt, art: ArtLibrary) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard drawn != base else { return whole }
        if offsets == nil {
            offsets = (try? art.data("outfits/body/variants.json", as: File.self))?.offsets ?? [:]
        }
        let d = catArt.paintedSize(drawn), b = catArt.paintedSize(base)
        guard d.width > 0, d.height > 0 else { return whole }
        let key = String((drawn as NSString).lastPathComponent.dropFirst(4).dropLast(4))
        let at = offsets?[key] ?? [Double(d.width - b.width) / 2, Double(d.height - b.height)]
        return CGRect(x: at[0] / d.width, y: at[1] / d.height, width: b.width / d.width, height: b.height / d.height)
    }
}

/// Outfit pictures' shapes, measured once each from the app's art.
@MainActor
public enum OutfitShapes {
    private static var cache: [String: OutfitShape] = [:]

    public static func shape(_ path: String, art: ArtLibrary) -> OutfitShape? {
        if let cached = cache[path] {
            return cached
        }
        guard let image = art.image(path), let raster = Raster(image), raster.planes.count == 4 else { return nil }
        let shape = OutfitFit.shape(alpha: raster.planes[3], width: raster.width, height: raster.height)
        cache[path] = shape
        return shape
    }
}
