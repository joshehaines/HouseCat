import HouseCatCore
import SpriteKit

/// The cat: a cut-out puppet of painted parts for moving (walk, run, rub), and
/// the painted resting poses for staying put (sit, loaf, sleep, stretch), with a
/// cross-fade between them (STYLE.md, ASSETS.md §7). The node's origin is
/// between the cat's feet on the floor.
@MainActor
public final class CatNode: SKNode {
    public enum View: String, CaseIterable, Sendable {
        case side
        case tqfront
        case front
    }

    public private(set) var body: String
    /// The look, when the cat is drawn from the builder's white sprites (nil: the plain painted set).
    public private(set) var look: CatLook?
    /// The standing height in the parent's units (the breed's size and a kitten's taken in).
    public private(set) var height: CGFloat
    private let baseHeight: CGFloat
    private var isKitten: Bool
    private let art: ArtLibrary
    private let catArt: CatArt?
    private let rig: PuppetRig
    /// One puppet per view; only the current one is shown. Each is an effect node so it
    /// can fade as one flat picture: faded part by part, the joints would show through.
    private var puppets: [View: SKEffectNode] = [:]
    private(set) var parts: [View: [String: SKSpriteNode]] = [:]
    private var restAngles: [View: [String: CGFloat]] = [:]
    private var restPositions: [View: [String: CGPoint]] = [:]
    private let poseNode = SKSpriteNode()
    public private(set) var view: View = .tqfront
    public private(set) var facingRight = false
    public private(set) var pose: CatPose?
    private var cycle: (gait: Gait, phase: CGFloat)?
    /// The outfit the cat wears (OutfitFit: hats, glasses, neckwear), on each view's head and on the pose on show.
    public private(set) var outfit: OutfitsFile.Outfit?
    private var outfitNodes: [SKNode] = []
    private(set) var poseOutfit: SKNode?

    /// How the legs go: a walk (one foot at a time), a trot (diagonal pairs) or a run (a gallop: the front pair,
    /// then the back pair, the body rocking).
    public enum Gait: Sendable {
        case walk
        case trot
        case run
    }

    /// The pace the cat is moving over the floor now (the parent's units a second), so its stride keeps up with
    /// it; 0 leaves each gait at its own beat (a puppet walking on the spot).
    public var moveSpeed: CGFloat = 0
    /// How far below the cat its shadow is (it stays on the floor or the seat while the cat is in the air).
    public var shadowDrop: CGFloat = 0 {
        didSet { placeShadow() }
    }

    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 1, height: 0.42))
    /// The cat's own clock, for breathing, blinks and the idle sway.
    private var clock: TimeInterval = 0
    private var nextBlink: TimeInterval = 2
    private var blinkEnds: TimeInterval?
    private var blinkAgain = false
    private var nextTwitch: TimeInterval = 5
    private var twitchEnds: TimeInterval = 0
    private var headLook: CGFloat = 0
    private var headLookTarget: CGFloat = 0
    private var nextLook: TimeInterval = 3
    /// The open-eyed pictures a blink stands in for, to put back.
    private var openPose: SKTexture?
    private var openHead: (View, SKTexture)?
    /// A squash or stretch on the puppet (crouching, landing), eased back to nothing.
    private var squashAmount: CGFloat = 0
    /// Scratching (seconds since it reared up): on its hind legs against a post, the front paws raking it in turn.
    public private(set) var scratchTime: TimeInterval?
    /// Each view's puppet's width standing (for its shadow).
    private var puppetWidths: [View: CGFloat] = [:]
    /// The legs jointed at the hock or wrist (CatLimb), in the side and three-quarter views, so a paw stays planted
    /// as the body passes over it.
    private var limbs: [View: [String: Limb]] = [:]
    /// The way the cat is moving over the floor (the parent's axes), for its paws to step back along it; nil, the
    /// way it faces.
    public var moveDirection: CGVector?

    /// A jointed leg: its pieces (the leg's own node from the shoulder to the wrist or the hip to the hock, the
    /// piece from the hock to the ankle on a hind leg, and the paw), its joints (each in the frame of the piece it
    /// hangs from, about that piece's pivot), the paw's sole and toe tip (in the paw's frame, about the ankle), and
    /// where it stands at rest in the puppet's frame.
    private struct Limb {
        let upper: SKSpriteNode
        let middle: SKSpriteNode?
        let paw: SKSpriteNode
        let hock: CGPoint?
        let ankle: CGPoint
        let sole: CGPoint
        let toe: CGPoint
        let hip: CGPoint
        let hind: Bool
        /// The paw's angle in the puppet's frame standing flat, as painted.
        let level: CGFloat
        let restSole: CGPoint
        let restToe: CGPoint
        let restAnkle: CGPoint
    }

    /// A cat in a look from the builder (`catArt` given), or the plain painted short_slim set.
    public init(
        art: ArtLibrary,
        rig: PuppetRig,
        catArt: CatArt? = nil,
        look: CatLook? = nil,
        isKitten: Bool = false,
        body: String = "short_slim",
        height: CGFloat
    ) {
        self.art = art
        self.rig = rig
        self.catArt = catArt
        self.look = catArt == nil ? nil : (look ?? .midnight)
        self.body = catArt == nil ? body : (look ?? .midnight).body
        self.isKitten = isKitten
        baseHeight = height
        self.height = height
        super.init()
        name = "Cat"
        poseNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        poseNode.alpha = 0
        poseNode.zPosition = 0.05
        addChild(poseNode)
        shadow.fillColor = SKColor(white: 0, alpha: CGFloat(Tuning.Puppet.shadowAlpha))
        shadow.strokeColor = .clear
        shadow.zPosition = -0.02
        shadow.name = "shadow"
        addChild(shadow)
        rebuild()
    }

    /// Draws the cat in another look (the builder's live preview, an edit from the profile): the puppet is
    /// rebuilt in the view and pose it was in.
    public func apply(look newLook: CatLook, isKitten kitten: Bool? = nil) {
        guard catArt != nil else { return }
        look = newLook
        body = newLook.body
        if let kitten {
            isKitten = kitten
        }
        rebuild()
    }

    private func rebuild() {
        let keepView = view, keepFacing = facingRight, keepPose = pose
        stopCycle()
        for puppet in puppets.values {
            puppet.removeFromParent()
        }
        puppets = [:]
        parts = [:]
        restAngles = [:]
        restPositions = [:]
        puppetWidths = [:]
        let breedScale = look.flatMap { catArt?.builder.body($0.body)?.scale } ?? 1
        height = baseHeight * CGFloat(breedScale) * CGFloat(isKitten ? Tuning.Cat.kittenScale : 1)
        for view in View.allCases {
            build(view)
        }
        pose = nil
        show(keepView, facingRight: keepFacing)
        layOutfit()
        if let keepPose {
            settle(into: keepPose, duration: 0)
        }
    }

    // MARK: Outfits

    /// Puts an outfit on (nil takes it off): hats, glasses and neckwear fitted to the face, body garments painted for
    /// this body's torso and resting poses.
    public func wear(_ outfit: OutfitsFile.Outfit?) {
        self.outfit = outfit
        layOutfit()
        if let pose {
            layPoseOutfit(pose)
        }
    }

    private var hasTallEars: Bool {
        look.map(OutfitFit.tallEars) ?? false
    }

    /// The outfit on each puppet view's head, so it turns and bobs with it.
    private func layOutfit() {
        for node in outfitNodes {
            node.removeFromParent()
        }
        outfitNodes = []
        if let outfit, outfit.slot == .body, let look {
            layTorsoGarment(outfit, look: look)
            return
        }
        guard let outfit, let kind = OutfitFit.kind(outfit), let catArt, let look else { return }
        for view in View.allCases {
            guard let head = parts[view]?["head"], let picture = outfit.sprites[view.rawValue],
                  let shape = OutfitShapes.shape(picture, art: art),
                  let face = catArt.face(catArt.builder.part("head", view: view.rawValue, look: look).path),
                  let fit = OutfitFit.place(kind, shape: shape, on: face, view: view.rawValue, size: outfit.fit, tallEars: hasTallEars)
            else { continue }
            outfitNodes.append(put(picture, fit: fit, face: face, on: head))
        }
    }

    /// A body garment on each view's torso, so it moves with the walk (the legs, head and tail stay bare).
    private func layTorsoGarment(_ outfit: OutfitsFile.Outfit, look: CatLook) {
        let pad = CGFloat(Tuning.Outfits.torsoPad)
        for view in View.allCases {
            guard let torso = parts[view]?["torso"], let path = OutfitFit.garment(outfit, body: look.body, view: view.rawValue),
                  art.has(path) else { continue }
            let node = SKSpriteNode(
                texture: art.texture(path),
                size: CGSize(width: torso.size.width * (1 + 2 * pad), height: torso.size.height * (1 + 2 * pad))
            )
            // Centred on the torso's picture, above it and below the head.
            node.position = CGPoint(x: (0.5 - torso.anchorPoint.x) * torso.size.width, y: (0.5 - torso.anchorPoint.y) * torso.size.height)
            node.zPosition = CGFloat(Tuning.Outfits.torsoGarmentZ)
            node.name = "outfit"
            torso.addChild(node)
            outfitNodes.append(node)
        }
    }

    /// A body garment over the resting pose on show, where the pose's base painting sits in it.
    private func layPoseGarment(_ outfit: OutfitsFile.Outfit, pose: CatPose, catArt: CatArt, look: CatLook) {
        guard let path = OutfitFit.garment(outfit, body: look.body, pose: pose), art.has(path) else { return }
        let drawn = catArt.builder.pose(pose.rawValue, look: look).path
        let frame = GarmentPlacement.frame(drawn: drawn, base: "poses/cat_\(look.body)_\(pose.rawValue).png", catArt: catArt, art: art)
        let size = poseNode.size
        let node = SKSpriteNode(texture: art.texture(path), size: CGSize(width: frame.width * size.width, height: frame.height * size.height))
        node.anchorPoint = CGPoint(x: 0, y: 1)
        node.position = CGPoint(x: (frame.minX - poseNode.anchorPoint.x) * size.width, y: (1 - frame.minY - poseNode.anchorPoint.y) * size.height)
        node.zPosition = CGFloat(Tuning.Outfits.zLift)
        node.name = "outfit"
        poseNode.addChild(node)
        poseOutfit = node
    }

    /// The outfit on the resting pose on show (its own view's picture; a curl is seen from the side).
    private func layPoseOutfit(_ pose: CatPose) {
        poseOutfit?.removeFromParent()
        poseOutfit = nil
        if let outfit, outfit.slot == .body, let catArt, let look {
            layPoseGarment(outfit, pose: pose, catArt: catArt, look: look)
            return
        }
        guard let outfit, let kind = OutfitFit.kind(outfit), let catArt, let look,
              let view = OutfitFit.view(for: pose), let picture = outfit.sprites[view],
              let shape = OutfitShapes.shape(picture, art: art),
              let face = catArt.face(catArt.builder.pose(pose.rawValue, look: look).path),
              let fit = OutfitFit.place(kind, shape: shape, on: face, view: view, size: outfit.fit, tallEars: hasTallEars) else { return }
        guard kind == .neck, OutfitFit.tucksNeckwear(pose) else {
            poseOutfit = put(picture, fit: fit, face: face, on: poseNode)
            return
        }
        // Lying down, neckwear only where the cat is.
        let crop = SKCropNode()
        let mask = SKSpriteNode(texture: poseNode.texture, size: poseNode.size)
        mask.anchorPoint = poseNode.anchorPoint
        crop.maskNode = mask
        crop.zPosition = CGFloat(Tuning.Outfits.zLift)
        poseNode.addChild(crop)
        _ = put(picture, fit: fit, face: face, on: poseNode, into: crop)
        poseOutfit = crop
    }

    /// An outfit picture on a sprite, where the fit says, in the sprite's own frame (it follows its turns and flips).
    private func put(_ picture: String, fit: OutfitFit.Placement, face: CatFace, on parent: SKSpriteNode, into container: SKNode? = nil) -> SKNode {
        let painted = art.paintedSize(picture)
        let size = parent.size
        let width = fit.width / max(1, face.size.width) * size.width
        let node = SKSpriteNode(
            texture: art.texture(picture),
            size: CGSize(width: width, height: width * painted.height / max(1, painted.width))
        )
        node.anchorPoint = fit.anchor
        let fx = fit.point.x / max(1, face.size.width), fy = fit.point.y / max(1, face.size.height)
        node.position = CGPoint(x: (fx - parent.anchorPoint.x) * size.width, y: (1 - fy - parent.anchorPoint.y) * size.height)
        node.zRotation = -fit.angle
        node.zPosition = CGFloat(Tuning.Outfits.zLift)
        node.name = "outfit"
        (container ?? parent).addChild(node)
        return node
    }

    /// A part's or pose's texture and its master size.
    private func sprite(part name: String, view: View) -> (SKTexture, CGSize) {
        if let catArt, let look, let repainted = repainted(name, view: view) {
            return (catArt.texture(repainted, look: look), catArt.paintedSize(repainted.path))
        }
        if let catArt, let look {
            let sprite = catArt.builder.part(name, view: view.rawValue, look: look)
            return (catArt.texture(sprite, look: look), catArt.paintedSize(sprite.path))
        }
        let path = "cat/base/\(body)/cat_\(body)_\(view.rawValue)_\(name).png"
        return (art.texture(path), art.paintedSize(path))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The side view's ears painted in profile (Josh, 19 Oct: the cupped ears, pink insides facing out, looked
    /// strange on a head seen from the side), when this body or ear shape has them; else nil, the old ones.
    private func profileEar(_ name: String, view: View) -> CatBuilder.Sprite? {
        guard Self.profileEars, view == .side, name.hasPrefix("ear_"), let catArt, let look,
              Tuning.Puppet.profileEarBodies.contains(look.body) else { return nil }
        let sprite = catArt.builder.part(name, view: view.rawValue, look: look)
        let path = sprite.path.replacingOccurrences(of: ".png", with: "_profile.png")
        return catArt.has(path) ? CatBuilder.Sprite(path: path, takesWhite: sprite.takesWhite) : nil
    }

    /// A leg painted again as one leg where the old painting held a pair (Josh, 19 Oct: the legs looked completely
    /// off walking; the long-haired slim body walked on eight), the same size so the rig fits it; else nil.
    private func singleLeg(_ name: String, view: View) -> CatBuilder.Sprite? {
        guard name.hasPrefix("leg_"), let catArt, let look else { return nil }
        let sprite = catArt.builder.part(name, view: view.rawValue, look: look)
        let path = sprite.path.replacingOccurrences(of: ".png", with: "_single.png")
        return catArt.has(path) ? CatBuilder.Sprite(path: path, takesWhite: sprite.takesWhite) : nil
    }

    /// A part's newer painting, if it has one: a profile ear, a single leg.
    private func repainted(_ name: String, view: View) -> CatBuilder.Sprite? {
        profileEar(name, view: view) ?? singleLeg(name, view: view)
    }

    /// Off only to compare with the old cupped ears (the movement renders).
    nonisolated(unsafe) static var profileEars = true

    /// A profile ear stands on its base: the middle of its bottom rows, found from its outline.
    private func earPivot(_ sprite: CatBuilder.Sprite) -> CGPoint? {
        guard let catArt, let look, let image = catArt.image(sprite, look: look) else { return nil }
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let rows = max(2, height / 16)
        var sum = 0.0, weight = 0.0
        for row in (height - rows) ..< height {
            for column in 0 ..< width {
                let a = Double(alpha[row * width + column])
                sum += Double(column) * a
                weight += a
            }
        }
        guard weight > 0 else { return nil }
        return CGPoint(x: sum / weight / Double(width), y: 0.05)
    }

    // MARK: Building the puppet

    /// The common scale: the painted standing reference is `height` tall.
    private func wholeScale(_ view: View) -> CGFloat {
        guard let spec = rig.sets[body]?[view.rawValue], spec.whole.count == 2 else { return 1 }
        return height / CGFloat(spec.whole[1])
    }

    private func build(_ view: View) {
        guard let spec = rig.sets[body]?[view.rawValue], spec.assembled.count == 2 else { return }
        // Parts are painted at their own scale: size them so the assembled rest pose matches the reference.
        let partScale = height / CGFloat(spec.assembled[1])
        let root = SKNode()
        var nodes: [String: SKSpriteNode] = [:]
        var rests: [String: CGFloat] = [:]
        // A heavier or lighter cat on the weight slider: the torso is drawn wider or narrower, the legs follow.
        let stretch = look.flatMap { catArt?.builder.torsoStretch($0) } ?? 1
        for (name, part) in spec.parts {
            // A side head painted with its own ear (the long-haired slim body's) takes no ear parts over it: two
            // pairs of ears. Swap ears still go on.
            if view == .side, name.hasPrefix("ear_"), Tuning.Puppet.sideHeadsWithEars.contains(body), (look?.ears ?? "own") == "own" {
                continue
            }
            let (texture, painted) = sprite(part: name, view: view)
            let width = painted.width * partScale * (name == "torso" ? CGFloat(stretch) : 1)
            let node = SKSpriteNode(texture: texture, size: CGSize(width: width, height: painted.height * partScale))
            node.anchorPoint = CGPoint(x: part.pivot[0], y: 1 - part.pivot[1])
            if let profile = profileEar(name, view: view), let pivot = earPivot(profile) {
                node.anchorPoint = pivot
            }
            node.name = name
            if name == "torso", let image = partImage(name, view: view), let soft = CatLimb.softenUnderside(image) {
                let texture = SKTexture(cgImage: soft)
                texture.filteringMode = .linear
                node.texture = texture
            }
            if name.hasPrefix("leg_"), name.hasSuffix("_far") {
                // The far legs a shade darker, behind the body.
                node.color = .black
                node.colorBlendFactor = CGFloat(Tuning.Puppet.farLegShade)
            }
            let rest = -CGFloat(part.angle ?? 0) * .pi / 180
            node.zRotation = rest
            rests[name] = rest
            nodes[name] = node
        }
        for (name, part) in spec.parts {
            guard let node = nodes[name] else { continue }
            if let parentName = part.parent, let parent = nodes[parentName], let parentPart = spec.parts[parentName] {
                // The joint on the parent, relative to the parent's pivot, in the parent's (unrotated) frame.
                node.position = CGPoint(
                    x: (CGFloat(part.at[0]) - CGFloat(parentPart.pivot[0])) * parent.size.width,
                    y: -(CGFloat(part.at[1]) - CGFloat(parentPart.pivot[1])) * parent.size.height
                )
                node.zPosition = CGFloat(part.z - parentPart.z) * 0.001
                parent.addChild(node)
            } else {
                node.zPosition = CGFloat(part.z) * 0.001
                root.addChild(node)
            }
        }
        // Stand the puppet on its feet: lowest point on the floor, centred on the origin.
        let frame = root.calculateAccumulatedFrame()
        puppetWidths[view] = frame.width
        for child in root.children {
            child.position.x -= frame.midX
            child.position.y -= frame.minY
        }
        joint(view, nodes: nodes, root: root)
        let holder = SKEffectNode()
        holder.shouldEnableEffects = false
        holder.addChild(root)
        holder.isHidden = true
        addChild(holder)
        puppets[view] = holder
        parts[view] = nodes
        restAngles[view] = rests
        restPositions[view] = nodes.mapValues(\.position)
    }

    /// Cuts each leg at its joints (CatLimb) in the side and three-quarter views: the leg's node keeps the top piece,
    /// each piece below hangs from the one above at their joint, drawn just behind it.
    private func joint(_ view: View, nodes: [String: SKSpriteNode], root: SKNode) {
        guard view != .front else { return }
        var made: [String: Limb] = [:]
        let torsoRest = restAngles[view]?["torso"] ?? nodes["torso"]?.zRotation ?? 0
        for (name, node) in nodes where name.hasPrefix("leg_") {
            let hind = name.hasPrefix("leg_back")
            guard let image = partImage(name, view: view), let found = CatLimb.joints(of: image, hind: hind) else { continue }
            var cuts: [CatLimb.Cut] = []
            if let hock = found.hock {
                cuts.append(CatLimb.Cut(centre: hock, radius: found.hockRadius))
            }
            cuts.append(CatLimb.Cut(centre: found.ankle, radius: found.ankleRadius))
            guard let pieces = CatLimb.split(image, at: cuts), pieces.count == cuts.count + 1 else { continue }
            let size = node.size
            // From one point of the picture to another (fractions, origin top left), in a piece's frame.
            func offset(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
                CGPoint(x: (to.x - from.x) * size.width, y: -(to.y - from.y) * size.height)
            }
            func texture(_ image: CGImage) -> SKTexture {
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = .linear
                return texture
            }
            node.texture = texture(pieces[0])
            var parent = node, parentPivot = CGPoint(x: node.anchorPoint.x, y: 1 - node.anchorPoint.y)
            var hung: [SKSpriteNode] = []
            for (cut, image) in zip(cuts, pieces.dropFirst()) {
                let piece = SKSpriteNode(texture: texture(image), size: size)
                piece.anchorPoint = CGPoint(x: cut.centre.x, y: 1 - cut.centre.y)
                piece.position = offset(parentPivot, cut.centre)
                piece.zPosition = -0.0004
                piece.color = node.color
                piece.colorBlendFactor = node.colorBlendFactor
                piece.name = name + (hung.count == cuts.count - 1 ? ".paw" : ".middle")
                parent.addChild(piece)
                hung.append(piece)
                parent = piece
                parentPivot = cut.centre
            }
            guard let paw = hung.last else { continue }
            let nodePivot = CGPoint(x: node.anchorPoint.x, y: 1 - node.anchorPoint.y)
            let ankle = offset(found.hock ?? nodePivot, found.ankle)
            let sole = offset(found.ankle, found.sole), toe = offset(found.ankle, found.toe)
            made[name] = Limb(
                upper: node,
                middle: hung.count > 1 ? hung[0] : nil,
                paw: paw,
                hock: found.hock.map { offset(nodePivot, $0) },
                ankle: ankle,
                sole: sole,
                toe: toe,
                hip: node.position,
                hind: hind,
                level: torsoRest + node.zRotation,
                restSole: paw.convert(sole, to: root),
                restToe: paw.convert(toe, to: root),
                restAnkle: paw.convert(.zero, to: root)
            )
        }
        limbs[view] = made
    }

    /// Where a jointed leg's paw is now (the middle of its sole), in the cat's parent's frame (for checking it stays
    /// put); nil when that leg is not jointed in the view on show.
    func paw(_ name: String) -> CGPoint? {
        guard let limb = limbs[view]?[name], let parent else { return nil }
        return limb.paw.convert(limb.sole, to: parent)
    }

    /// A part's picture in the cat's look (or the plain set's): a leg to cut at its joint, the torso to soften.
    private func partImage(_ name: String, view: View) -> CGImage? {
        if let catArt, let look {
            return catArt.image(repainted(name, view: view) ?? catArt.builder.part(name, view: view.rawValue, look: look), look: look)
        }
        return art.image("cat/base/\(body)/cat_\(body)_\(view.rawValue)_\(name).png")
    }

    /// Where a jointed leg is in its stride: where its ankle (or wrist) goes, in the puppet's frame; how far its paw
    /// turns off flat (anticlockwise, painted facing left: the heel up, the toes down); and, in the air, how high its
    /// hip rides and the ankle's places at lift-off and landing with how far it has come (`swing`, 0 to 1).
    private struct Step {
        var ankle: CGPoint
        var angle: CGFloat
        var raise: CGFloat = 0
        var swing: (from: CGPoint, to: CGPoint, u: Double)?
    }

    /// Puts a jointed leg where `step` says. A front leg, straight, points at its wrist's place and slides up into
    /// the body (hidden behind it) when that is nearer than the leg is long, as a cat's shoulder blade rides up. A
    /// hind leg on the floor bends at the hock to reach it; in the air, it eases from how it left the floor to how it
    /// will land, its hip riding up and its hock folding the paw forward under it, as a cat's does.
    private func place(_ limb: Limb, _ step: Step, torso: SKNode) {
        // Into the torso's frame, where the hip is.
        let c = cos(torso.zRotation), s = sin(torso.zRotation)
        func local(_ point: CGPoint) -> CGPoint {
            let v = CGPoint(x: point.x - torso.position.x, y: point.y - torso.position.y)
            return CGPoint(x: v.x * c + v.y * s, y: -v.x * s + v.y * c)
        }
        let hip = limb.hip
        var turned: CGFloat
        if let hock = limb.hock, let middle = limb.middle {
            let a = hypot(hock.x, hock.y), b = hypot(limb.ankle.x, limb.ankle.y)
            // The leg's turn and the hock's for the ankle at `target`, the hip where it is at rest.
            func bend(_ target: CGPoint) -> (upper: CGFloat, middle: CGFloat) {
                let knee = CatLimb.knee(hip: hip, target: target, upper: a, lower: b, bend: 1)
                let upper = atan2(knee.y - hip.y, knee.x - hip.x) - atan2(hock.y, hock.x)
                return (upper, atan2(target.y - knee.y, target.x - knee.x) - atan2(limb.ankle.y, limb.ankle.x) - upper)
            }
            var angles = bend(local(step.ankle))
            if let swing = step.swing {
                let from = bend(local(swing.from)), to = bend(local(swing.to))
                let k = CGFloat(swing.u * swing.u * (3 - 2 * swing.u))
                func blend(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                    x + atan2(sin(y - x), cos(y - x)) * k
                }
                let fold = CGFloat(Tuning.Puppet.hockFold) * .pi / 180 * CGFloat(sin(swing.u * .pi))
                angles = (blend(from.upper, to.upper), blend(from.middle, to.middle) - fold)
            }
            limb.upper.position = CGPoint(x: hip.x, y: hip.y + step.raise)
            limb.upper.zRotation = angles.upper
            middle.zRotation = angles.middle
            turned = angles.upper + angles.middle
        } else {
            let target = local(step.ankle)
            let dx = target.x - hip.x, dy = target.y - hip.y
            let distance = max(hypot(dx, dy), 0.001), length = hypot(limb.ankle.x, limb.ankle.y)
            turned = atan2(dy, dx) - atan2(limb.ankle.y, limb.ankle.x)
            limb.upper.zRotation = turned
            let slide = min(length * CGFloat(Tuning.Puppet.shoulderDrop), max(-length * 0.3, distance - length))
            limb.upper.position = CGPoint(x: hip.x + dx / distance * slide, y: hip.y + dy / distance * slide)
        }
        limb.paw.zRotation = limb.level + step.angle - torso.zRotation - turned
    }

    /// A gait's paw path: the share of a stride a paw is in the air, how far it travels under the body while down
    /// and how high it lifts, the way forward, and how far the body sits below standing (the puppet's frame).
    private struct Path {
        var swingShare: Double
        var sweep: CGFloat
        var lift: CGFloat
        var way: CGVector
        var drop: CGFloat
    }

    /// Where a jointed leg goes `f` of the way through its stride (the paw in the air for the first `swingShare` of
    /// it). On the floor, the paw slides back under the body as fast as the cat goes forward, so it stays put on the
    /// floor, and at the end rolls up onto its toes; in the air, the ankle swings forward in an arc while the paw
    /// folds back and opens out flat again to land.
    private func stepping(_ limb: Limb, at f: Double, on path: Path) -> Step {
        let (swingShare, sweep, lift, way, drop) = (path.swingShare, path.sweep, path.lift, path.way, path.drop)
        let p = Tuning.Puppet.self
        let rad = CGFloat.pi / 180
        let roll = CGFloat(limb.hind ? p.hindPawRoll : p.frontPawRoll) * rad
        let fold = CGFloat(limb.hind ? p.hindPawFold : p.frontPawFold) * rad
        let reach = CGFloat(p.pawReach) * rad
        func ease(_ t: Double) -> CGFloat {
            let k = max(0, min(1, t))
            return CGFloat(k * k * (3 - 2 * k))
        }
        // The ankle with the paw planted `along` the way forward, rolled `turn` onto its toes.
        func planted(_ along: CGFloat, _ turn: CGFloat) -> CGPoint {
            let shift = CGPoint(x: along * way.dx, y: along * way.dy + drop)
            guard turn != 0 else {
                return CGPoint(x: limb.restAnkle.x + shift.x, y: limb.restAnkle.y + shift.y)
            }
            let toe = CGPoint(x: limb.restToe.x + shift.x, y: limb.restToe.y + shift.y)
            let arm = CGPoint(x: limb.restAnkle.x - limb.restToe.x, y: limb.restAnkle.y - limb.restToe.y)
            let c = cos(turn), s = sin(turn)
            return CGPoint(x: toe.x + arm.x * c - arm.y * s, y: toe.y + arm.x * s + arm.y * c)
        }
        if f >= swingShare {
            let v = (f - swingShare) / (1 - swingShare)
            let rolling = (v - (1 - p.pawRollShare)) / p.pawRollShare
            let turn = rolling > 0 ? roll * ease(rolling) : 0
            return Step(ankle: planted(sweep * CGFloat(0.5 - v), turn), angle: turn)
        }
        let u = f / swingShare
        let from = planted(-sweep / 2, roll), to = planted(sweep / 2, 0)
        let k = ease(u)
        let ankle = CGPoint(
            x: from.x + (to.x - from.x) * k,
            y: from.y + (to.y - from.y) * k + lift * CGFloat(sin(u * .pi))
        )
        let angle: CGFloat = if u < 0.4 {
            roll + (fold - roll) * ease(u / 0.4)
        } else if u < 0.85 {
            fold + (-reach - fold) * ease((u - 0.4) / 0.45)
        } else {
            -reach * (1 - ease((u - 0.85) / 0.15))
        }
        return Step(ankle: ankle, angle: angle, raise: lift * CGFloat(p.hipRaise * sin(u * .pi)), swing: (from, to, u))
    }

    // MARK: Showing

    /// Shows one view of the puppet, facing left or right (the side view is painted facing left). Resting in a
    /// pose, the painting stays on show and the view is the one it will get up in.
    public func show(_ view: View, facingRight: Bool) {
        restoreEyes()
        self.view = view
        self.facingRight = facingRight
        for node in puppets.values {
            node.xScale = facingRight ? -1 : 1
        }
        poseNode.xScale = facingRight ? -1 : 1
        showOnlyOne()
        placeShadow()
    }

    /// One drawing of the cat at a time: the painting while it rests in a pose, else the puppet in its view. Two at
    /// once, even fading, read as a second cat (a fade cut short left the puppet showing behind the painting).
    private func showOnlyOne() {
        let resting = pose != nil
        poseNode.removeAction(forKey: "swap")
        poseNode.alpha = resting ? 1 : 0
        for (v, node) in puppets {
            node.alpha = 1
            node.isHidden = resting || v != view
        }
    }

    /// Turns the moving puppet to another view: the new view takes over at once with a quick squash across, as a
    /// body turning (a cross-fade showed both views, a second cat, for a moment); a change of facing alone flips.
    public func turn(to newView: View, facingRight: Bool, duration: TimeInterval = Tuning.Puppet.turnSeconds) {
        guard newView != view, pose == nil, puppets[view] != nil, let new = puppets[newView] else {
            show(newView, facingRight: facingRight)
            return
        }
        let oldView = view
        let keep = cycle
        show(newView, facingRight: facingRight)
        resetPose(oldView)
        cycle = keep
        let flip: CGFloat = facingRight ? -1 : 1
        new.removeAction(forKey: "turn")
        new.xScale = flip * CGFloat(Tuning.Puppet.turnSquash)
        let settle = SKAction.scaleX(to: flip, duration: duration)
        settle.timingMode = .easeOut
        new.run(settle, withKey: "turn")
    }

    /// The builder's sprite for a resting pose in this cat's look.
    private func poseBuilderSprite(_ pose: CatPose) -> CatBuilder.Sprite? {
        guard let catArt, let look else { return nil }
        let sprite = catArt.builder.pose(pose.rawValue, look: look)
        return catArt.has(sprite.path) ? sprite : nil
    }

    /// The painted resting pose's texture and master size, if the set has it.
    private func poseSprite(_ pose: CatPose) -> (SKTexture, CGSize)? {
        if let catArt, let look {
            guard let sprite = poseBuilderSprite(pose) else { return nil }
            return (catArt.texture(sprite, look: look), catArt.paintedSize(sprite.path))
        }
        let path = "cat/poses/plain/cat_\(body)_\(pose.rawValue).png"
        guard art.has(path) else { return nil }
        return (art.texture(path), art.paintedSize(path))
    }

    /// Settles into a painted resting pose: from moving, the puppet sits down a little and the painting takes over
    /// at the bottom of the dip; from another painting (a glance, a stretch), the new one takes over at once with a
    /// little settle. `crossFade` fades painting into painting instead (the logo's curl; two cats for a moment).
    public func settle(into pose: CatPose, duration: TimeInterval = Tuning.Puppet.settleSeconds, crossFade: Bool = false) {
        guard let (texture, painted) = poseSprite(pose) else {
            stopCycle()
            return
        }
        restoreEyes()
        let was = self.pose
        stopCycle()
        if crossFade, let was, was != pose, duration > 0, let old = poseNode.copy() as? SKSpriteNode {
            old.removeAllActions()
            old.zPosition = poseNode.zPosition + 0.01
            addChild(old)
            old.run(.sequence([.fadeOut(withDuration: duration), .removeFromParent()]))
        }
        let s = wholeScale(view)
        let stretch = look.flatMap { catArt?.builder.torsoStretch($0) } ?? 1
        poseNode.texture = texture
        poseNode.size = CGSize(width: painted.width * s * CGFloat(stretch), height: painted.height * s)
        self.pose = pose
        layPoseOutfit(pose)
        poseNode.removeAllActions()
        if was == nil, duration > 0 {
            // The puppet stays on show through the dip; then the painting, and only the painting.
            squash(CGFloat(Tuning.Puppet.sitDownDip))
            poseNode.alpha = 0
            poseNode.run(.sequence([
                .wait(forDuration: Tuning.Puppet.sitDownSeconds),
                .run { [weak self] in self?.showOnlyOne() },
            ]), withKey: "swap")
        } else {
            showOnlyOne()
            if was != nil, was != pose, duration > 0, !crossFade {
                squash(CGFloat(Tuning.Puppet.sitDownDip) * 0.5)
            }
        }
        placeShadow()
    }

    /// From a resting pose back to the puppet, ready to move: it comes up from a crouch, the painting gone at once.
    public func rise(to view: View, facingRight: Bool, duration: TimeInterval = Tuning.Puppet.riseSeconds) {
        let was = pose
        pose = nil
        show(view, facingRight: facingRight)
        if was != nil, duration > 0 {
            squash(CGFloat(Tuning.Puppet.sitDownDip))
        }
        placeShadow()
    }

    // MARK: Moving

    /// Starts the walk cycle: one foot at a time, the body bobbing twice a stride, the tail swaying.
    public func walk() {
        move(.walk)
    }

    /// Starts the run: a gallop, the body rocking and the tail streaming.
    public func run() {
        move(.run)
    }

    /// Starts (or changes to) a gait, keeping the stride's place.
    public func move(_ gait: Gait) {
        cycle = (gait, cycle?.phase ?? 0)
    }

    public func stopCycle() {
        cycle = nil
        scratchTime = nil
        moveSpeed = 0
        resetPose(view)
    }

    private func resetPose(_ view: View) {
        guard let nodes = parts[view], let rests = restAngles[view] else { return }
        for (name, node) in nodes {
            node.zRotation = rests[name] ?? 0
            if let rest = restPositions[view]?[name] {
                node.position = rest
            }
        }
        for limb in (limbs[view] ?? [:]).values {
            limb.upper.position = limb.hip
            limb.middle?.zRotation = 0
            limb.paw.zRotation = 0
        }
        if let root = puppets[view]?.children.first {
            root.position = .zero
            root.zRotation = 0
        }
    }

    /// Rears up against something to scratch it: in the side view (facing it), up on its hind legs, the front paws
    /// raking it in turn until `stopScratching`.
    public func scratch() {
        guard pose == nil else { return }
        stopCycle()
        if view != .side {
            show(.side, facingRight: facingRight)
        }
        scratchTime = 0
    }

    /// Down from scratching onto all fours (a little bump as the front feet land).
    public func stopScratching() {
        guard scratchTime != nil else { return }
        stopCycle()
        squash(CGFloat(Tuning.Puppet.sitDownDip))
        placeShadow()
    }

    /// The scratch at `t` seconds: the body tips up about the hips, the back legs stay standing under them, the
    /// head stays nearer level, and the front legs reach up the post and rake it in turn.
    private func scratching(_ t: TimeInterval) {
        guard let nodes = parts[.side], let rests = restAngles[.side], let root = puppets[.side]?.children.first,
              let hipNode = nodes["leg_back_near"], let hipParent = hipNode.parent else { return }
        let p = Tuning.Puppet.self
        func set(_ name: String, _ angle: CGFloat) {
            nodes[name]?.zRotation = (rests[name] ?? 0) - angle
        }
        let k = CGFloat(min(1, t / p.scratchRiseSeconds))
        let up = k * k * (3 - 2 * k)
        let rear = CGFloat(p.scratchRearDegrees) * .pi / 180 * up
        // Turn about the hips (painted facing left, so up is clockwise), keeping them where they stand.
        let hip = hipParent.convert(hipNode.position, to: root)
        let c = cos(rear), s = sin(rear)
        root.zRotation = -rear
        root.position = CGPoint(x: hip.x - (hip.x * c + hip.y * s), y: hip.y - (-hip.x * s + hip.y * c))
        set("leg_back_near", -rear)
        set("leg_back_far", -rear)
        let stroke = CGFloat(sin(t * 2 * .pi * p.scratchHz))
        let reach = CGFloat(p.scratchReachDegrees) * .pi / 180 * up
        let rake = CGFloat(p.scratchRakeDegrees) * .pi / 180 * up
        set("leg_front_near", reach + rake * stroke)
        set("leg_front_far", reach - rake * stroke)
        set("head", -rear * CGFloat(p.scratchHeadLevel))
        let tailName = nodes["tail_up"] != nil ? "tail_up" : "tail"
        set(tailName, -rear * 0.35 + CGFloat(p.idleTailSway * .pi / 180 * sin(t * 2 * .pi * p.idleTailHz)))
        // Only the hind feet on the floor: the shadow gathers under them.
        placeShadow()
        shadow.position.x = hip.x * up * (facingRight ? -1 : 1)
        shadow.xScale *= 1 - 0.35 * up
        shadow.yScale *= 1 - 0.35 * up
    }

    /// Crouches (or squashes on landing) by a share of the height; it eases back by itself.
    public func squash(_ amount: CGFloat) {
        squashAmount = amount
    }

    /// Advances the stride and the cat's life at rest; called each frame by the scene.
    public func step(_ dt: TimeInterval) {
        clock += dt
        live(dt)
        if let t = scratchTime {
            scratchTime = t + dt
            scratching(t + dt)
            return
        }
        guard var current = cycle, let nodes = parts[view], let rests = restAngles[view],
              let spec = rig.sets[body]?[view.rawValue] else { return }
        let p = Tuning.Puppet.self
        let (stride, beat, pace, swingScale) = switch current.gait {
        case .walk: (p.walkStride, p.walkHz, p.walkSpeed, 1.0)
        case .trot: (p.trotStride, (p.walkHz + p.runHz) / 2, p.trotSpeed, 1.15)
        case .run: (p.runStride, p.runHz, p.runSpeed, p.runSwing)
        }
        // The stride keeps pace with the floor; a slow start takes short steps.
        let hz = moveSpeed > 0 ? max(0.3, Double(moveSpeed) / (stride * Double(height))) : beat
        let reach = moveSpeed > 0 ? CGFloat(min(1, max(0.35, Double(moveSpeed) / pace))) : 1
        current.phase = (current.phase + CGFloat(dt * hz)).truncatingRemainder(dividingBy: 1)
        cycle = current
        let phase = current.phase
        let swing = CGFloat(spec.walk?.legSwing ?? 20) * CGFloat(swingScale) * .pi / 180 * reach
        func set(_ name: String, _ angle: CGFloat) {
            nodes[name]?.zRotation = (rests[name] ?? 0) - angle
        }
        /// A leg's swing through its stride: forward quickly, back slowly with the foot on the floor.
        func leg(_ offset: CGFloat) -> CGFloat {
            let f = (phase + offset).truncatingRemainder(dividingBy: 1)
            if f < 0.38 {
                let k = f / 0.38
                return -1 + 2 * k * k * (3 - 2 * k)
            }
            return 1 - 2 * (f - 0.38) / 0.62
        }
        let offsets: [(String, CGFloat)] = switch current.gait {
        case .walk: [("leg_back_near", 0), ("leg_front_near", 0.25), ("leg_back_far", 0.5), ("leg_front_far", 0.75)]
        case .trot: [("leg_front_near", 0), ("leg_back_far", 0), ("leg_front_far", 0.5), ("leg_back_near", 0.5)]
        case .run: [("leg_front_near", 0), ("leg_front_far", 0.1), ("leg_back_near", 0.5), ("leg_back_far", 0.6)]
        }
        let t = phase * 2 * .pi
        let tailName = nodes["tail_up"] != nil ? "tail_up" : "tail"
        let sway = CGFloat(spec.walk?.tailSway ?? 6) * .pi / 180
        let nod = CGFloat(spec.walk?.headBob ?? 2) * .pi / 180
        var bob: CGFloat
        switch current.gait {
        case .walk, .trot:
            bob = (0.5 - 0.5 * cos(2 * t)) * height * CGFloat(current.gait == .walk ? p.walkBob : (p.walkBob + p.runBob) / 2)
            set(tailName, sway * sin(t - 1.1) * (current.gait == .trot ? 1.2 : 1))
            set("head", nod * sin(2 * t) * 0.7)
        case .run:
            // A gallop: the body rocks, the head stays steadier, the tail streams back.
            let pitch = CGFloat(p.gallopPitch) * .pi / 180 * reach
            set("torso", pitch * sin(t))
            set("head", -pitch * 0.7 * sin(t) + nod * 0.5 * sin(2 * t))
            set(tailName, -CGFloat(p.runTailDrop) * .pi / 180 * reach + sway * 0.6 * sin(2 * t))
            bob = max(0, sin(t)) * height * CGFloat(p.runBob)
        }
        bob *= reach
        puppets[view]?.children.first?.position.y = bob
        if let jointed = limbs[view], !jointed.isEmpty, let torso = nodes["torso"] {
            // Each paw on its own path: planted, it slides back under the body as fast as the cat goes forward (so it
            // stays put on the floor); lifted, it swings forward in an arc. Hips and joints follow (CatLimb).
            let (swingShare, liftShare, crouch) = switch current.gait {
            case .walk: (p.walkSwing, p.walkLift, p.walkCrouch)
            case .trot: (p.trotSwing, p.trotLift, p.walkCrouch)
            case .run: (p.runSwingShare, p.runLift, p.runCrouch)
            }
            let travel = moveSpeed > 0 ? Double(moveSpeed) / hz : stride * Double(height)
            // Coming towards you at a slant, a stride is foreshortened: shorter steps.
            let sweep = CGFloat((1 - swingShare) * travel * (view == .side ? 1 : p.slantStride))
            let low = CGFloat(crouch) * height * reach
            let lift = CGFloat(liftShare) * height * reach
            let path = Path(swingShare: swingShare, sweep: sweep, lift: lift, way: forward(), drop: low - bob)
            for (name, offset) in offsets {
                guard let limb = jointed[name] else { continue }
                let f = Double((phase + offset).truncatingRemainder(dividingBy: 1))
                place(limb, stepping(limb, at: f, on: path), torso: torso)
            }
            // The body a little lower while moving, the legs a little bent under it.
            puppets[view]?.children.first?.position.y = bob - low
        } else if view == .front, let rest = restPositions[view] {
            // Legs are relative to the torso, which is scaled up from the parts' pixels; lift in its units.
            let lift = (nodes["leg_front_near"]?.size.height ?? 0) * CGFloat(p.frontLegLift) * reach
            for (name, offset) in offsets {
                nodes[name]?.position.y = (rest[name]?.y ?? 0) + max(0, leg(offset)) * lift
            }
        } else {
            for (name, offset) in offsets {
                set(name, swing * leg(offset))
            }
        }
    }

    /// The way forward in the puppet's frame (painted facing left; flipped when facing right), along the floor.
    private func forward() -> CGVector {
        let fallback = view == .side ? CGVector(dx: -1, dy: 0) : CGVector(dx: -0.96, dy: -0.28)
        guard var way = moveDirection, hypot(way.dx, way.dy) > 0.01 else { return fallback }
        // Back along the floor is up the screen: a paw that far up behind reads as a kick, so the path keeps mostly
        // level (a flat picture of a leg cannot go back into the room).
        way.dy *= CGFloat(Tuning.Puppet.pathRise)
        let length = hypot(way.dx, way.dy)
        way = CGVector(dx: way.dx / length, dy: way.dy / length)
        // In the puppet's frame, forward is left (-x); a cat facing right is the puppet flipped.
        return CGVector(dx: facingRight ? -way.dx : way.dx, dy: way.dy)
    }

    // MARK: Life at rest

    /// Breathing (deeper and slower asleep), blinks, and standing still, the tail swaying, the head looking about,
    /// an ear twitching now and then.
    private func live(_ dt: TimeInterval) {
        let p = Tuning.Puppet.self
        if squashAmount != 0 {
            squashAmount *= max(0, 1 - CGFloat(dt) * 7)
            if abs(squashAmount) < 0.002 {
                squashAmount = 0
            }
        }
        let breath: [Double] = switch pose {
        case .sleepCurl: p.breathSleep
        case .loafSide, .loafThreeQuarterFront: p.breathLoaf
        case .stretchSide: [0, 0]
        case .some: p.breathSit
        case nil: p.breathStand
        }
        let rise = CGFloat(breath[0] * sin(clock * 2 * .pi * breath[1]))
        let root = puppets[view]?.children.first
        root?.xScale = 1 + squashAmount * 0.5
        if pose != nil {
            poseNode.yScale = (1 - squashAmount) * (1 + rise)
            root?.yScale = 1 - squashAmount
        } else {
            poseNode.yScale = 1
            root?.yScale = (1 - squashAmount) * (cycle == nil ? 1 + rise : 1)
        }
        // Blinks, now and then; a double blink sometimes.
        if let ends = blinkEnds, clock >= ends {
            restoreEyes()
            if blinkAgain {
                blinkAgain = false
                nextBlink = clock + 0.14
            }
        }
        if blinkEnds == nil, clock >= nextBlink {
            blink()
        }
        guard pose == nil, cycle == nil, scratchTime == nil, let nodes = parts[view], let rests = restAngles[view] else { return }
        let tailName = nodes["tail_up"] != nil ? "tail_up" : "tail"
        let sway = CGFloat(p.idleTailSway * .pi / 180 * sin(clock * 2 * .pi * p.idleTailHz))
        nodes[tailName]?.zRotation = (rests[tailName] ?? 0) - sway
        if clock >= nextLook {
            headLookTarget = CGFloat(Double.random(in: -1 ... 1) * p.idleHeadTurn * .pi / 180)
            nextLook = clock + Double.random(in: 1.5 ... 4)
        }
        headLook += (headLookTarget - headLook) * min(1, CGFloat(dt) * 3)
        nodes["head"]?.zRotation = (rests["head"] ?? 0) - headLook
        if clock >= nextTwitch {
            twitchEnds = clock + 0.16
            nextTwitch = clock + Double.random(in: p.earTwitchGap[0] ... p.earTwitchGap[1])
        }
        let twitch = clock < twitchEnds ? CGFloat(sin((1 - (twitchEnds - clock) / 0.16) * .pi) * p.earTwitch * .pi / 180) : 0
        nodes["ear_near"]?.zRotation = (rests["ear_near"] ?? 0) - twitch
    }

    /// Shuts the eyes for a moment: a blink, or a slow blink (a cat's way of saying it trusts you). Nothing when the
    /// cat shows no eyes (asleep, from behind).
    public func blink(slow: Bool = false) {
        let p = Tuning.Puppet.self
        nextBlink = clock + Double.random(in: p.blinkGap[0] ... p.blinkGap[1]) + (slow ? 1.5 : 0)
        guard blinkEnds == nil || slow, let catArt, let look else { return }
        restoreEyes()
        if let pose {
            guard let sprite = poseBuilderSprite(pose), let shut = catArt.blinkTexture(sprite, look: look) else { return }
            openPose = poseNode.texture
            poseNode.texture = shut
        } else if let head = parts[view]?["head"], let open = head.texture {
            guard let shut = catArt.blinkTexture(catArt.builder.part("head", view: view.rawValue, look: look), look: look) else { return }
            openHead = (view, open)
            head.texture = shut
        } else {
            return
        }
        blinkEnds = clock + (slow ? p.slowBlinkSeconds : p.blinkSeconds)
        blinkAgain = !slow && Int.random(in: 0 ..< 100) < p.doubleBlinkPercent
    }

    /// Opens the eyes again (before anything else changes the picture).
    private func restoreEyes() {
        if let openPose {
            poseNode.texture = openPose
            self.openPose = nil
        }
        if let (shown, open) = openHead {
            parts[shown]?["head"]?.texture = open
            openHead = nil
        }
        blinkEnds = nil
    }

    /// How many drawings of the cat are on show (any part see-through or not): always one.
    var drawingsOnShow: Int {
        let pictures: [SKNode] = [poseNode] + Array(puppets.values) + children.filter { $0 is SKSpriteNode && $0 !== poseNode }
        return pictures.filter { !$0.isHidden && $0.alpha > 0.01 }.count
    }

    /// The cat's own outline in its parent's units (the puppet or the painting on show, not its shadow).
    public var bodyFrame: CGRect {
        let shown: [SKNode] = pose != nil ? [poseNode] : (puppets[view].map { [$0] } ?? [])
        let local = shown.reduce(CGRect.null) { $0.union($1.calculateAccumulatedFrame()) }
        guard !local.isNull, let parent else { return local }
        return CGRect(
            origin: parent.convert(local.origin, from: self),
            size: CGSize(width: local.width * abs(xScale), height: local.height * abs(yScale))
        ).standardized
    }

    /// The soft shadow under the cat: as wide as the pose or the puppet, left on the floor (or seat) when the cat
    /// is in the air, smaller and fainter the higher it goes.
    private func placeShadow() {
        let width: CGFloat = if pose != nil {
            poseNode.size.width
        } else {
            puppetWidths[view] ?? height
        }
        let high = max(0, shadowDrop) / max(1, height)
        let k = max(0.45, 1 - high * 0.6)
        let w = width * CGFloat(Tuning.Puppet.shadowWidth) * k
        shadow.xScale = max(1, w)
        shadow.yScale = max(1, w)
        shadow.position = CGPoint(x: 0, y: -shadowDrop + w * 0.04)
        shadow.alpha = k
    }
}
