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
    /// The legs that bend (CatSkin), in the side and three-quarter views, so a paw stays planted as the body passes
    /// over it.
    private var limbs: [View: [String: Limb]] = [:]
    /// Each view's body that bends with the stride (CatSkin): its torso's grid, its tail's bones.
    private var bodies: [View: Body] = [:]
    /// How far the cat has got into moving (0 standing, 1 on its way), eased, for the head's carriage.
    private var carriage: CGFloat = 0
    /// Walking and running, the cat is a film (CatArt films; Josh, 19 Oct, of the rebuilt puppet and a generated
    /// film: "B is the best by far"); off only to look at the puppet's own walk (its tests and renders).
    nonisolated(unsafe) static var films = true
    /// The film on show: a holder that flips and turns like a puppet view, the frame in it squashing like the puppet.
    private let filmHolder = SKNode()
    private let filmNode = SKSpriteNode()
    /// The films' frames in this look by "<view>/<gait>" (tinted off the main thread), the look they are for, which
    /// film and frame is on show, and the outfit on it.
    private var filmFrames: [String: [SKTexture]] = [:]
    private var filmLook = 0
    private var filmOnShow: String?
    private var filmFrame = -1
    private var filmOutfit: SKNode?
    /// The look's swapped ears and bobtail on the film (the puppet's own pieces), where the film's own were cut out.
    private var filmPieces: [String: SKSpriteNode] = [:]
    /// The way the cat is moving over the floor (the parent's axes), for its paws to step back along it; nil, the
    /// way it faces.
    public var moveDirection: CGVector?

    /// A leg that bends (Josh, 19 Oct: "full rebuild"): one picture, uncut, with a grid over it. Its node turns with
    /// the upper bone (from the hip to the hock on a hind leg, from the shoulder to the elbow at the body's lower edge
    /// on a front leg); below the joint the lower bone bends (to the ankle, or to a front leg's paw: no wrist), and a
    /// hind leg's paw bends again at the ankle. Each grid point takes a share of each bone, blended over the joint, so
    /// it bends like fur over a joint, with no cut. Points are in the leg node's frame at rest; `hip` and the rest
    /// places are in the torso's and the puppet's frames.
    private struct Limb {
        let node: SKSpriteNode
        let skin: Skin
        /// Each grid point's share of the upper bone, the lower and the paw.
        let weights: [SIMD3<Float>]
        let hind: Bool
        let joint: CGPoint
        /// The lower bone's end: a hind leg's ankle, a front leg's sole.
        let end: CGPoint
        let sole: CGPoint
        let toe: CGPoint
        /// Which side the joint bends to (+1 anticlockwise of the line from the hip to the paw).
        let bend: CGFloat
        let hip: CGPoint
        let rest: CGFloat
        /// The paw's angle in the puppet's frame standing flat, as painted.
        let level: CGFloat
        let restSole: CGPoint
        let restToe: CGPoint
        let restAnkle: CGPoint
        /// How far the lower bone and the paw are bent now (radians, anticlockwise).
        var lower: CGFloat = 0
        var paw: CGFloat = 0
    }

    /// A view's torso that bends (CatSkin): the spine arches and stretches, a shoulder blade rides up over a front leg
    /// taking the weight, the shoulder and haunch go with the near legs under them; and where the head, tail and near
    /// legs join it at rest (the torso's frame), so they go with it.
    private struct Body {
        let skin: Skin
        let length: CGFloat
        let depth: CGFloat
        let spine: CGFloat
        let shoulder: CGPoint?
        let haunch: CGPoint?
        let neck: CGPoint?
        let tailRoot: CGPoint?
        let tail: TailChain?
        let tailSkin: Skin?
    }

    /// How the torso is bent now: the spine (radians; positive arches the back, the ends down), the near shoulder
    /// blade up (points), the shoulder and haunch turned with the near legs (radians) and the shoulder lifted.
    private struct Bend {
        var flex: CGFloat = 0
        var blade: CGFloat = 0
        var shoulderTurn: CGFloat = 0
        var shoulderLift: CGFloat = 0
        var haunchTurn: CGFloat = 0
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
        filmHolder.zPosition = 0.04
        filmHolder.isHidden = true
        filmHolder.addChild(filmNode)
        addChild(filmHolder)
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
        prepareFilms()
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
        filmFrame = -1
        if let pose {
            layPoseOutfit(pose)
        }
    }

    /// Tall ears lift a hat, unless they go under it.
    private var hasTallEars: Bool {
        guard let look else { return false }
        return outfit.map { OutfitFit.tallEars(look, wearing: $0) } ?? OutfitFit.tallEars(look)
    }

    /// Whether the outfit on is a hat the cat's ears go under.
    private var earsUnderHat: Bool {
        outfit.map(OutfitFit.coversEars) ?? false
    }

    /// The outfit on each puppet view's head, so it turns and bobs with it. A hat the ears go under hides them: the
    /// ear parts and anything of the head above its rim (a breed's head is painted with its ears).
    private func layOutfit() {
        for node in outfitNodes {
            node.removeFromParent()
        }
        outfitNodes = []
        for nodes in parts.values {
            nodes["head"]?.shader = nil
            nodes["ear_near"]?.isHidden = false
            nodes["ear_far"]?.isHidden = false
        }
        if let outfit, outfit.slot == .body, let look {
            layTorsoGarment(outfit, look: look)
            return
        }
        guard let outfit, let kind = OutfitFit.kind(outfit), let catArt, let look else { return }
        for view in View.allCases {
            guard let head = parts[view]?["head"], let picture = outfit.sprites[view.rawValue],
                  let shape = OutfitShapes.shape(picture, art: art),
                  let face = catArt.face(headSprite(view, catArt: catArt, look: look).path),
                  let fit = OutfitFit.place(kind, shape: shape, on: face, view: view.rawValue, size: outfit.fit, tallEars: hasTallEars, coversEars: earsUnderHat)
            else { continue }
            outfitNodes.append(put(picture, fit: fit, face: face, on: head))
            if earsUnderHat {
                cover(head, with: OutfitFit.earCover(fit, shape: shape, on: face, view: view.rawValue), face: face)
                parts[view]?["ear_near"]?.isHidden = true
                parts[view]?["ear_far"]?.isHidden = true
            }
        }
    }

    /// Hides a picture above a hat's rim (`OutfitFit.EarCover`), in a shader so it holds for whatever texture the
    /// node shows next (a blink, the next frame of a film); nil shows it all again.
    private func cover(_ node: SKSpriteNode, with cover: OutfitFit.EarCover?, face: CatFace) {
        guard let cover, face.size.width > 0, face.size.height > 0 else {
            node.shader = nil
            return
        }
        let shader = SKShader(source: Self.earCoverSource, uniforms: [
            SKUniform(name: "u_cover_origin", vectorFloat2: SIMD2(Float(cover.origin.x / face.size.width), Float(1 - cover.origin.y / face.size.height))),
            SKUniform(name: "u_cover_size", vectorFloat2: SIMD2(Float(face.size.width), Float(face.size.height))),
            // Up the picture with y up, as the texture's coordinates run.
            SKUniform(name: "u_cover_up", vectorFloat2: SIMD2(Float(cover.up.dx), Float(-cover.up.dy))),
            SKUniform(name: "u_cover_half", float: Float(cover.half)),
        ])
        node.shader = shader
    }

    /// `EarCover.hides` on the GPU, in the texture's pixels.
    private static let earCoverSource = """
    void main() {
        vec4 colour = texture2D(u_texture, v_tex_coord);
        vec2 p = (v_tex_coord - u_cover_origin) * u_cover_size;
        float above = dot(p, u_cover_up);
        float along = abs(dot(p, vec2(u_cover_up.y, -u_cover_up.x)));
        float hide = clamp((above + 1.5) / 3.0, 0.0, 1.0) * clamp((u_cover_half - along + 1.5) / 3.0, 0.0, 1.0);
        gl_FragColor = colour * (1.0 - hide) * v_color_mix.a;
    }
    """

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
        poseNode.shader = nil
        if let outfit, outfit.slot == .body, let catArt, let look {
            layPoseGarment(outfit, pose: pose, catArt: catArt, look: look)
            return
        }
        guard let outfit, let kind = OutfitFit.kind(outfit), let catArt, let look,
              let view = OutfitFit.view(for: pose), let picture = outfit.sprites[view],
              let shape = OutfitShapes.shape(picture, art: art),
              let face = catArt.face(catArt.builder.pose(pose.rawValue, look: look).path),
              let fit = OutfitFit.place(kind, shape: shape, on: face, view: view, size: outfit.fit, tallEars: hasTallEars, coversEars: earsUnderHat) else { return }
        guard kind == .neck, OutfitFit.tucksNeckwear(pose) else {
            poseOutfit = put(picture, fit: fit, face: face, on: poseNode)
            if earsUnderHat {
                cover(poseNode, with: OutfitFit.earCover(fit, shape: shape, on: face, view: view), face: face)
            }
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

    /// Every part drawn from another picture of it instead of the look's (the movement renders: the white painting and
    /// each mask, for a film of the cat to be tinted like the puppet); nil, the look's.
    nonisolated(unsafe) static var paintOver: ((CatBuilder.Sprite) -> CGImage?)?

    /// A part's or pose's texture and its master size.
    private func sprite(part name: String, view: View) -> (SKTexture, CGSize) {
        if let catArt, let look, let over = Self.paintOver {
            let sprite = repainted(name, view: view) ?? catArt.builder.part(name, view: view.rawValue, look: look)
            if let image = over(sprite) {
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = .linear
                return (texture, catArt.paintedSize(sprite.path))
            }
        }
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

    /// A side head painted with its own ear (the long-haired slim body's) painted again with none, for swapped ears
    /// (Josh, 20 Oct: "show two sets of ears": the painted ear stayed beside the swapped ones); else nil.
    private func earlessHead(_ name: String, view: View) -> CatBuilder.Sprite? {
        guard name == "head", view == .side, let catArt, let look, look.ears != "own",
              Tuning.Puppet.sideHeadsWithEars.contains(look.body) else { return nil }
        let sprite = catArt.builder.part(name, view: view.rawValue, look: look)
        let path = sprite.path.replacingOccurrences(of: ".png", with: "_noears.png")
        return catArt.has(path) ? CatBuilder.Sprite(path: path, takesWhite: sprite.takesWhite) : nil
    }

    /// A part's newer painting, if it has one: a profile ear, a single leg, a head with no ears.
    private func repainted(_ name: String, view: View) -> CatBuilder.Sprite? {
        profileEar(name, view: view) ?? singleLeg(name, view: view) ?? earlessHead(name, view: view)
    }

    /// The head's painting in a view, as drawn (a head with no ears for swapped ones), for blinks and outfits.
    private func headSprite(_ view: View, catArt: CatArt, look: CatLook) -> CatBuilder.Sprite {
        repainted("head", view: view) ?? catArt.builder.part("head", view: view.rawValue, look: look)
    }

    /// Off only to compare with the old cupped ears (the movement renders).
    nonisolated(unsafe) static var profileEars = true

    /// How much larger or smaller than painted a swapped ear is drawn: as tall as the body's own ear in this view
    /// (the one it stands in for, profile or cupped), times its shape's share. The swap ears' masters are one set for
    /// every body and were painted larger than a body's own, so on the puppet they stood half as tall again as the
    /// same ears in the sitting paintings and the ears jumped in size as the cat sat down (Josh, 20 Oct: "The ears on
    /// the cats need to be looked at, they are very buggy").
    private func swappedEarScale(_ name: String, view: View, painted: CGSize) -> CGFloat {
        guard name.hasPrefix("ear_"), let catArt, let look, look.ears != "own",
              let share = Tuning.Puppet.swapEarLength[look.ears], painted.height > 0 else { return 1 }
        let own = "parts/cat_\(look.body)_\(view.rawValue)_\(name).png"
        let profile = own.replacingOccurrences(of: ".png", with: "_profile.png")
        let takesProfile = Self.profileEars && view == .side && Tuning.Puppet.profileEarBodies.contains(look.body) && catArt.has(profile)
        let ownHeight = catArt.paintedSize(takesProfile ? profile : own).height
        // A side head painted with its own ear has a smaller one than its separate (undrawn) ear parts.
        let body = Tuning.Puppet.swapEarBodyView["\(look.body)/\(view.rawValue)"] ?? 1
        return ownHeight > 0 ? CGFloat(share * body) * ownHeight / painted.height : 1
    }

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
            // pairs of ears. Swapped ears go on its painting with no ears (`earlessHead`).
            if view == .side, name.hasPrefix("ear_"), Tuning.Puppet.sideHeadsWithEars.contains(body), (look?.ears ?? "own") == "own" {
                continue
            }
            let (texture, painted) = sprite(part: name, view: view)
            let earScale = swappedEarScale(name, view: view, painted: painted)
            let width = painted.width * partScale * (name == "torso" ? CGFloat(stretch) : 1) * earScale
            let node = SKSpriteNode(texture: texture, size: CGSize(width: width, height: painted.height * partScale * earScale))
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

    /// Rigs each leg to bend (CatSkin) in the side and three-quarter views, and the torso, head and tail to bend
    /// and move with them. A near leg is drawn in front of the body with its top faded into the fur over it, so the
    /// body's lower edge never runs across the top of the leg (Josh, 19 Oct: the join between body and legs looked
    /// strange); a far leg stays behind the body.
    private func joint(_ view: View, nodes: [String: SKSpriteNode], root: SKNode) {
        guard view != .front, let torso = nodes["torso"] else {
            bodies[view] = shape(view, nodes: nodes, limbs: [:])
            return
        }
        let p = Tuning.Puppet.self
        var made: [String: Limb] = [:]
        let torsoRest = restAngles[view]?["torso"] ?? torso.zRotation
        let torsoImage = partImage("torso", view: view)
        for (name, node) in nodes where name.hasPrefix("leg_") {
            let hind = name.hasPrefix("leg_back"), near = name.hasSuffix("_near")
            guard let image = partImage(name, view: view), let found = CatLimb.joints(of: image, hind: hind) else { continue }
            let size = node.size
            let pivot = CGPoint(x: node.anchorPoint.x, y: 1 - node.anchorPoint.y)
            // Where the body's lower edge crosses the leg (a share of the leg's height from its top).
            var edge = CGFloat(p.legTuck)
            if let torsoImage {
                let top = CGPoint(x: node.position.x - node.anchorPoint.x * size.width, y: node.position.y + (1 - node.anchorPoint.y) * size.height)
                func across(_ x: CGFloat) -> CGFloat {
                    (top.x + x * size.width) / torso.size.width + torso.anchorPoint.x
                }
                if let under = CatLimb.underside(of: torsoImage, from: across(0.3), to: across(0.7)) {
                    let y = (1 - under - torso.anchorPoint.y) * torso.size.height
                    edge = max(0.06, min(0.45, (top.y - y) / size.height))
                }
            }
            if near {
                let whole = max(0.1, edge - CGFloat(p.fadeAboveEdge))
                if let faded = CatLimb.fadedTop(image, clear: max(0.04, whole - CGFloat(p.fadeLength)), whole: whole) {
                    let texture = SKTexture(cgImage: faded)
                    texture.filteringMode = .linear
                    node.texture = texture
                }
                // In front of the body, behind its garment and head.
                node.zPosition = CGFloat(p.nearLegZ)
            }
            let skin = Skin(size: size, anchor: node.anchorPoint, columns: 4, rows: 20)
            // From one point of the picture to another (fractions, origin top left), in the node's frame.
            func at(_ point: CGPoint) -> CGPoint {
                CGPoint(x: (point.x - pivot.x) * size.width, y: -(point.y - pivot.y) * size.height)
            }
            // The joint: a hind leg's hock where it has one; else where the leg leaves the body (the elbow).
            let jointFraction = found.hock ?? CGPoint(x: CatLimb.middle(of: image, at: edge) ?? pivot.x, y: edge)
            let jointRadius = found.hock != nil ? max(found.hockRadius * 0.9, 0.04) : CGFloat(p.elbowBlend)
            let endFraction = hind ? found.ankle : found.sole
            let painted = at(jointFraction), end = at(endFraction)
            // The joint as the bones would put it standing (bent the way the painting is, a front leg's elbow back):
            // turns are taken from there, so standing still is the painting.
            let a = hypot(painted.x, painted.y), b = hypot(end.x - painted.x, end.y - painted.y)
            let side = end.x * painted.y - end.y * painted.x
            let bend: CGFloat = found.hock != nil && abs(side) > a * b * 0.05 ? (side > 0 ? 1 : -1) : 1
            let joint = CatLimb.knee(hip: .zero, target: end, upper: a, lower: b, bend: bend)
            let weights = skin.points.indices.map { index -> SIMD3<Float> in
                let y = skin.fraction(index).y
                func ramp(_ centre: CGFloat, _ radius: CGFloat) -> CGFloat {
                    let t = max(0, min(1, (y - (centre - radius)) / (2 * radius)))
                    return t * t * (3 - 2 * t)
                }
                let below = ramp(jointFraction.y, jointRadius)
                let paw = hind ? ramp(found.ankle.y, max(found.ankleRadius * 0.9, 0.03)) : 0
                let lower = max(0, below - paw)
                return SIMD3(Float(1 - below), Float(lower), Float(paw))
            }
            made[name] = Limb(
                node: node,
                skin: skin,
                weights: weights,
                hind: hind,
                joint: joint,
                end: end,
                sole: at(found.sole),
                toe: at(found.toe),
                bend: bend,
                hip: node.position,
                rest: node.zRotation,
                level: torsoRest + node.zRotation,
                restSole: node.convert(at(found.sole), to: root),
                restToe: node.convert(at(found.toe), to: root),
                restAnkle: node.convert(end, to: root)
            )
        }
        limbs[view] = made
        bodies[view] = shape(view, nodes: nodes, limbs: made)
    }

    /// The view's torso, head and tail rigged to bend and move with the stride.
    private func shape(_ view: View, nodes: [String: SKSpriteNode], limbs: [String: Limb]) -> Body? {
        guard let torso = nodes["torso"] else { return nil }
        let skin = Skin(size: torso.size, anchor: torso.anchorPoint, columns: 12, rows: 6)
        let tailName = nodes["tail_up"] != nil ? "tail_up" : "tail"
        var chain: TailChain?, tailSkin: Skin?
        if let tail = nodes[tailName], let image = partImage(tailName, view: view) {
            let made = Skin(size: tail.size, anchor: tail.anchorPoint, columns: 14, rows: 18)
            chain = TailChain(
                image: image, root: CGPoint(x: tail.anchorPoint.x, y: 1 - tail.anchorPoint.y), bones: Tuning.Puppet.tailBones, skin: made
            )
            tailSkin = chain == nil ? nil : made
        }
        return Body(
            skin: skin,
            length: torso.size.width * 0.9,
            depth: torso.size.height,
            spine: torso.size.height * 0.1,
            shoulder: limbs["leg_front_near"]?.hip,
            haunch: limbs["leg_back_near"]?.hip,
            neck: nodes["head"]?.position,
            tailRoot: nodes[tailName]?.position,
            tail: chain,
            tailSkin: tailSkin
        )
    }

    /// Where a bending leg's paw is now (the middle of its sole), in the cat's parent's frame (for checking it stays
    /// put); nil when that leg does not bend in the view on show.
    func paw(_ name: String) -> CGPoint? {
        guard let limb = limbs[view]?[name], let parent else { return nil }
        return limb.node.convert(bent(limb, limb.sole), to: parent)
    }

    /// A point of a leg's picture (its node's frame at rest) where the leg's bend puts it: blended between its bones.
    private func bent(_ limb: Limb, _ point: CGPoint, weights: SIMD3<Float>? = nil) -> CGPoint {
        let w = weights ?? (limb.hind ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0))
        let j = limb.joint, e = limb.end
        func turn(_ v: CGPoint, _ angle: CGFloat) -> CGPoint {
            let c = cos(angle), s = sin(angle)
            return CGPoint(x: v.x * c - v.y * s, y: v.x * s + v.y * c)
        }
        let lower = turn(CGPoint(x: point.x - j.x, y: point.y - j.y), limb.lower)
        let onLower = CGPoint(x: j.x + lower.x, y: j.y + lower.y)
        var x = CGFloat(w.x) * point.x + CGFloat(w.y) * onLower.x
        var y = CGFloat(w.x) * point.y + CGFloat(w.y) * onLower.y
        if w.z > 0 {
            let ankle = turn(CGPoint(x: e.x - j.x, y: e.y - j.y), limb.lower)
            let paw = turn(CGPoint(x: point.x - e.x, y: point.y - e.y), limb.lower + limb.paw)
            x += CGFloat(w.z) * (j.x + ankle.x + paw.x)
            y += CGFloat(w.z) * (j.y + ankle.y + paw.y)
        }
        return CGPoint(x: x, y: y)
    }

    /// Draws a leg bent as it is now (no grid when it stands as painted).
    private func skinLeg(_ limb: Limb) {
        guard limb.lower != 0 || limb.paw != 0 else {
            limb.node.warpGeometry = nil
            return
        }
        let moved = limb.skin.points.indices.map { bent(limb, limb.skin.points[$0], weights: limb.weights[$0]) }
        limb.node.warpGeometry = limb.skin.warp(moved)
    }

    /// A part's picture in the cat's look (or the plain set's): a leg to cut at its joint, the torso to soften.
    private func partImage(_ name: String, view: View) -> CGImage? {
        if let catArt, let look, let over = Self.paintOver {
            return over(repainted(name, view: view) ?? catArt.builder.part(name, view: view.rawValue, look: look))
        }
        if let catArt, let look {
            return catArt.image(repainted(name, view: view) ?? catArt.builder.part(name, view: view.rawValue, look: look), look: look)
        }
        return art.image("cat/base/\(body)/cat_\(body)_\(view.rawValue)_\(name).png")
    }

    /// Where a leg is in its stride: where its ankle (or a front leg's sole) goes, in the puppet's frame; how far a
    /// hind paw turns off flat (anticlockwise, painted facing left: the heel up, the toes down); how high its hip or
    /// shoulder rides; and, in the air, the ankle's places at lift-off and landing with how far it has come (`swing`,
    /// 0 to 1).
    private struct Step {
        var ankle: CGPoint
        var angle: CGFloat
        var raise: CGFloat = 0
        var swing: (from: CGPoint, to: CGPoint, u: Double)?
    }

    /// Puts a leg where `step` says, its hip at `hip` (the torso's frame, the body bent). On the floor the leg bends at
    /// its joint to reach the paw's place: a hind leg at the hock, a front leg at the elbow where it leaves the body
    /// (its paw has no wrist: it turns with the leg, landing on its heel and leaving on its toes). Beyond its reach,
    /// it comes a little down out of the body. In the air a hind leg eases from how it left the floor to how it will
    /// land, its hock folding the paw forward under it; a front leg folds at the elbow, its shoulder riding up.
    private func place(_ name: String, _ step: Step, hip: CGPoint, torso: SKNode) {
        guard var limb = limbs[view]?[name] else { return }
        let p = Tuning.Puppet.self
        // Into the torso's frame, then the leg's at rest about its hip.
        let c = cos(torso.zRotation), s = sin(torso.zRotation)
        let rc = cos(limb.rest), rs = sin(limb.rest)
        func local(_ point: CGPoint) -> CGPoint {
            let v = CGPoint(x: point.x - torso.position.x, y: point.y - torso.position.y)
            let t = CGPoint(x: v.x * c + v.y * s - hip.x, y: -v.x * s + v.y * c - hip.y)
            return CGPoint(x: t.x * rc + t.y * rs, y: -t.x * rs + t.y * rc)
        }
        let j = limb.joint, e = limb.end
        let a = hypot(j.x, j.y), b = hypot(e.x - j.x, e.y - j.y)
        // The turns of the upper and lower bones for the end at `target` (the leg's rest frame).
        func turns(_ target: CGPoint) -> (upper: CGFloat, lower: CGFloat) {
            let knee = CatLimb.knee(hip: .zero, target: target, upper: a, lower: b, bend: limb.bend)
            let upper = atan2(knee.y, knee.x) - atan2(j.y, j.x)
            let lower = atan2(target.y - knee.y, target.x - knee.x) - atan2(e.y - j.y, e.x - j.x) - upper
            return (upper, atan2(sin(lower), cos(lower)))
        }
        var target = local(step.ankle)
        // Beyond its reach: down out of the body a little way towards it.
        let distance = hypot(target.x, target.y)
        let slide = max(0, min((a + b) * CGFloat(p.shoulderDrop), distance - (a + b) * 0.995))
        var at = CGPoint(x: hip.x, y: hip.y + step.raise)
        if slide > 0 {
            let along = CGPoint(x: target.x / distance * slide, y: target.y / distance * slide)
            target = CGPoint(x: target.x - along.x, y: target.y - along.y)
            at = CGPoint(x: at.x + along.x * rc - along.y * rs, y: at.y + along.x * rs + along.y * rc)
        }
        var bones = turns(target)
        if limb.hind, let swing = step.swing {
            let from = turns(local(swing.from)), to = turns(local(swing.to))
            let k = CGFloat(swing.u * swing.u * (3 - 2 * swing.u))
            func blend(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                x + atan2(sin(y - x), cos(y - x)) * k
            }
            let fold = CGFloat(p.hockFold) * .pi / 180 * CGFloat(sin(swing.u * .pi))
            bones = (blend(from.upper, to.upper), blend(from.lower, to.lower) - fold)
        }
        limb.node.position = at
        limb.node.zRotation = limb.rest + bones.upper
        limb.lower = bones.lower
        limb.paw = limb.hind ? limb.level + step.angle - torso.zRotation - limb.rest - bones.upper - bones.lower : 0
        limbs[view]?[name] = limb
        skinLeg(limb)
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
        // A front leg's paw turns with the leg (it has no wrist): it lands on its heel and leaves on its toes as the
        // leg swings over it.
        let roll = limb.hind ? CGFloat(p.hindPawRoll) * rad : 0
        let fold = limb.hind ? CGFloat(p.hindPawFold) * rad : 0
        let reach = limb.hind ? CGFloat(p.pawReach) * rad : 0
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
        filmHolder.xScale = facingRight ? -1 : 1
        showOnlyOne()
        placeShadow()
    }

    /// One drawing of the cat at a time: the painting while it rests in a pose, else the puppet in its view. Two at
    /// once, even fading, read as a second cat (a fade cut short left the puppet showing behind the painting).
    private func showOnlyOne() {
        let resting = pose != nil
        let filming = !resting && filmOnShow != nil
        poseNode.removeAction(forKey: "swap")
        poseNode.alpha = resting ? 1 : 0
        filmHolder.isHidden = !filming
        for (v, node) in puppets {
            node.alpha = 1
            node.isHidden = resting || filming || v != view
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
        let settle = SKAction.scaleX(to: flip, duration: duration)
        settle.timingMode = .easeOut
        for node in [new, filmHolder] {
            node.removeAction(forKey: "turn")
            node.xScale = flip * CGFloat(Tuning.Puppet.turnSquash)
            node.run(settle, withKey: "turn")
        }
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
        let filming = filmOnShow != nil
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
            // The puppet (or the film's last frame) stays on show through the dip; then the painting, and only it.
            if filming {
                filmHolder.isHidden = false
                puppets[view]?.isHidden = true
            }
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
        hideFilm()
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
        for (name, var limb) in limbs[view] ?? [:] {
            limb.lower = 0
            limb.paw = 0
            limb.node.warpGeometry = nil
            limbs[view]?[name] = limb
        }
        nodes["torso"]?.warpGeometry = nil
        for garment in nodes["torso"]?.children ?? [] where garment.name == "outfit" {
            (garment as? SKSpriteNode)?.warpGeometry = nil
        }
        nodes["tail_up"]?.warpGeometry = nil
        nodes["tail"]?.warpGeometry = nil
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
        carriage += ((cycle == nil ? 0 : 1) - carriage) * min(1, CGFloat(dt) * 5)
        live(dt)
        if let t = scratchTime {
            scratchTime = t + dt
            scratching(t + dt)
            return
        }
        guard var current = cycle, let nodes = parts[view], let rests = restAngles[view],
              let spec = rig.sets[body]?[view.rawValue] else { return }
        let p = Tuning.Puppet.self
        if let (key, film, frames) = film(for: current.gait) {
            // The film plays at its own pace, quicker or slower as the cat goes faster or slower than a filmed cat
            // walks (or gallops, slowed down) over the floor; at a standstill (the renders), as filmed.
            let filmed = current.gait == .run ? p.filmRunPace : p.filmWalkPace
            let pace = moveSpeed > 0 ? Double(moveSpeed / max(1, height)) / filmed : 1
            let hz = pace / max(0.1, film.seconds)
            current.phase = (current.phase + CGFloat(dt * hz)).truncatingRemainder(dividingBy: 1)
            cycle = current
            showFilm(key, film: film, frames: frames, phase: current.phase)
            return
        }
        hideFilm()
        let rad = CGFloat.pi / 180
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
        func set(_ name: String, _ angle: CGFloat) {
            nodes[name]?.zRotation = (rests[name] ?? 0) - angle
        }
        let offsets: [(String, CGFloat)] = switch current.gait {
        case .walk: [("leg_back_near", 0), ("leg_front_near", 0.25), ("leg_back_far", 0.5), ("leg_front_far", 0.75)]
        case .trot: [("leg_front_near", 0), ("leg_back_far", 0), ("leg_front_far", 0.5), ("leg_back_near", 0.5)]
        case .run: [("leg_front_near", 0), ("leg_front_far", 0.1), ("leg_back_near", 0.5), ("leg_back_far", 0.6)]
        }
        let t = phase * 2 * .pi
        // The body's beat over a stride: how it rises and falls, rocks and arches. A walk dips twice a stride, the
        // back rippling a little; a gallop gathers (the back arched, the hind legs under it) and stretches out.
        var bob: CGFloat, pitch: CGFloat = 0, flex: CGFloat, nod: CGFloat = 0
        switch current.gait {
        case .walk:
            bob = (0.5 - 0.5 * cos(2 * t)) * height * CGFloat(p.walkBob)
            flex = CGFloat(p.walkFlex) * rad * sin(2 * t + 0.8)
            nod = CGFloat(p.walkNod) * rad * sin(2 * t - 0.6)
        case .trot:
            bob = (0.5 - 0.5 * cos(2 * t)) * height * CGFloat((p.walkBob + p.runBob) / 2)
            flex = CGFloat(p.trotFlex) * rad * sin(2 * t + 0.8)
            nod = CGFloat(p.walkNod) * rad * 0.7 * sin(2 * t - 0.6)
        case .run:
            pitch = CGFloat(p.gallopPitch) * rad * sin(t)
            flex = CGFloat(p.runFlex) * rad * cos(t - CGFloat(p.runFlexPhase) * 2 * .pi)
            bob = max(0, sin(t)) * height * CGFloat(p.runBob)
        }
        bob *= reach
        pitch *= reach
        flex *= reach
        let root = puppets[view]?.children.first
        if let jointed = limbs[view], !jointed.isEmpty, let torso = nodes["torso"], let shape = bodies[view] {
            // Each paw on its own path: planted, it slides back under the body as fast as the cat goes forward (so it
            // stays put on the floor); lifted, it swings forward in an arc. The legs bend to reach (CatSkin).
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
            // The body a little lower while moving, the legs a little bent under it.
            root?.position.y = bob - low
            set("torso", pitch)
            let path = Path(swingShare: swingShare, sweep: sweep, lift: lift, way: forward(), drop: low - bob)
            var steps: [(String, Step)] = [], blade: CGFloat = 0
            for (name, offset) in offsets {
                guard let limb = jointed[name] else { continue }
                let f = Double((phase + offset).truncatingRemainder(dividingBy: 1))
                steps.append((name, stepping(limb, at: f, on: path)))
                if !limb.hind, f >= swingShare {
                    // A front leg taking the weight: the shoulder blade rides up over it (the near one's the most).
                    let v = (f - swingShare) / (1 - swingShare)
                    blade = max(blade, CGFloat(sin(v * .pi)) * (name.hasSuffix("_near") ? 1 : 0.6))
                }
            }
            var bend = Bend(flex: flex, blade: blade * CGFloat(p.bladeRise) * height * reach)
            for (name, step) in steps {
                guard let limb = limbs[view]?[name] else { continue }
                place(name, step, hip: deform(limb.hip, bend, shape), torso: torso)
            }
            // The near shoulder and haunch go with the legs under them (the fur round the top of the leg, not the hip).
            if let front = limbs[view]?["leg_front_near"] {
                bend.shoulderTurn = (front.node.zRotation - front.rest) * CGFloat(p.shoulderFollow)
                bend.shoulderLift = (front.node.position.y - deform(front.hip, bend, shape).y) * CGFloat(p.shoulderFollow)
            }
            if let back = limbs[view]?["leg_back_near"] {
                bend.haunchTurn = (back.node.zRotation - back.rest) * CGFloat(p.haunchFollow)
            }
            skinBody(shape, bend, nodes: nodes, rests: rests, bob: bob, pitch: pitch, nod: nod)
        } else if view == .front, let rest = restPositions[view] {
            root?.position.y = bob
            // Coming straight at you the body rolls a little from side to side as the weight goes from paw to paw.
            let roll = CGFloat(p.frontRoll) * rad * sin(t) * reach
            set("torso", roll)
            set("head", -roll * 0.8 - nod)
            // Legs are relative to the torso, which is scaled up from the parts' pixels; lift in its units.
            let lift = (nodes["leg_front_near"]?.size.height ?? 0) * CGFloat(p.frontLegLift) * reach
            for (name, offset) in offsets {
                nodes[name]?.position.y = (rest[name]?.y ?? 0) + max(0, legSwing(phase + offset)) * lift
            }
        } else {
            root?.position.y = bob
            let swing = CGFloat(spec.walk?.legSwing ?? 20) * CGFloat(swingScale) * rad * reach
            for (name, offset) in offsets {
                set(name, swing * legSwing(phase + offset))
            }
        }
        wagTail(current.gait, t: t, reach: reach)
    }

    /// A leg's swing through its stride, -1 back to 1 forward: forward quickly, back slowly with the foot down (the
    /// legs that do not bend: the front view's).
    private func legSwing(_ phase: CGFloat) -> CGFloat {
        let f = phase.truncatingRemainder(dividingBy: 1)
        if f < 0.38 {
            let k = f / 0.38
            return -1 + 2 * k * k * (3 - 2 * k)
        }
        return 1 - 2 * (f - 0.38) / 0.62
    }

    /// A point of the torso (its frame at rest) where the body's bend puts it: the spine arched about its middle,
    /// the near shoulder blade risen, the shoulder and haunch turned with the legs under them.
    private func deform(_ point: CGPoint, _ bend: Bend, _ shape: Body) -> CGPoint {
        func turned(_ p: CGPoint, about c: CGPoint, by angle: CGFloat) -> CGPoint {
            let cs = cos(angle), sn = sin(angle)
            return CGPoint(x: c.x + (p.x - c.x) * cs - (p.y - c.y) * sn, y: c.y + (p.x - c.x) * sn + (p.y - c.y) * cs)
        }
        func near(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGFloat {
            let dx = (point.x - c.x) / rx, dy = (point.y - c.y) / ry
            return exp(-(dx * dx + dy * dy))
        }
        var q = turned(point, about: CGPoint(x: 0, y: shape.spine), by: spineTurn(point.x, bend, shape))
        if let shoulder = shape.shoulder {
            let blade = CGPoint(x: shoulder.x + shape.length * 0.04, y: shape.spine + shape.depth * 0.32)
            q.y += bend.blade * near(blade, shape.length * 0.12, shape.depth * 0.4)
            let w = near(shoulder, shape.length * 0.15, shape.depth * 0.45)
            let moved = turned(point, about: CGPoint(x: shoulder.x, y: shoulder.y + shape.depth * 0.4), by: bend.shoulderTurn * w)
            q.x += moved.x - point.x
            q.y += moved.y - point.y + bend.shoulderLift * w
        }
        if let haunch = shape.haunch {
            let w = near(CGPoint(x: haunch.x, y: haunch.y + shape.depth * 0.12), shape.length * 0.17, shape.depth * 0.5)
            let moved = turned(point, about: CGPoint(x: haunch.x, y: haunch.y + shape.depth * 0.35), by: bend.haunchTurn * w)
            q.x += moved.x - point.x
            q.y += moved.y - point.y
        }
        return q
    }

    /// How far the spine's bend turns the body at `x` along it (the torso's frame; painted facing left, so the front
    /// is to the left): nothing at the middle, the most at the ends.
    private func spineTurn(_ x: CGFloat, _ bend: Bend, _ shape: Body) -> CGFloat {
        let u = x / max(1, shape.length / 2)
        let k = min(1, abs(u))
        return (u < 0 ? 1 : -1) * bend.flex * k * k * (3 - 2 * k)
    }

    /// The torso (and a garment on it) drawn bent; the head kept steadier than the body, carried a little low and
    /// forward on the move.
    private func skinBody(
        _ shape: Body, _ bend: Bend, nodes: [String: SKSpriteNode], rests: [String: CGFloat], bob: CGFloat, pitch: CGFloat, nod: CGFloat
    ) {
        let p = Tuning.Puppet.self
        if let torso = nodes["torso"] {
            torso.warpGeometry = shape.skin.warp(shape.skin.points.map { deform($0, bend, shape) })
            for case let garment as SKSpriteNode in torso.children where garment.name == "outfit" {
                let grid = Skin(size: garment.size, anchor: garment.anchorPoint, columns: 12, rows: 6)
                let at = garment.position
                garment.warpGeometry = grid.warp(grid.points.map {
                    let moved = deform(CGPoint(x: $0.x + at.x, y: $0.y + at.y), bend, shape)
                    return CGPoint(x: moved.x - at.x, y: moved.y - at.y)
                })
            }
        }
        if let head = nodes["head"], let neck = shape.neck {
            let at = deform(neck, bend, shape)
            head.position = CGPoint(x: at.x, y: at.y - bob * CGFloat(p.headSteady) - height * CGFloat(p.headCarry) * carriage)
            head.zRotation = (rests["head"] ?? 0) + spineTurn(neck.x, bend, shape) * 0.5 + pitch * CGFloat(p.headLevel)
                + nod + CGFloat(p.headCarryDegrees) * .pi / 180 * carriage
        }
        if let tailRoot = shape.tailRoot, let tail = nodes["tail_up"] ?? nodes["tail"] {
            tail.position = deform(tailRoot, bend, shape)
        }
    }

    /// The tail swaying along its length (CatSkin): a wave from the root to the tip, the tip a beat behind. Walking
    /// it is carried up and sways with the stride; at a run it streams out behind, uncurled; standing it sways slowly.
    private func wagTail(_ gait: Gait?, t: CGFloat, reach: CGFloat) {
        guard let shape = bodies[view], let chain = shape.tail, let skin = shape.tailSkin,
              let tail = parts[view]?["tail_up"] ?? parts[view]?["tail"] else { return }
        let p = Tuning.Puppet.self
        let rad = CGFloat.pi / 180
        let (base, sway, wave, beat, uncurl): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = switch gait {
        case .walk: (0, CGFloat(p.walkTailSway), CGFloat(p.walkTailWave), t - 1.1, 0)
        case .trot: (-CGFloat(p.trotTailBack), CGFloat(p.walkTailSway) * 1.2, CGFloat(p.walkTailWave) * 1.3, 2 * t - 1.1, 0.25)
        case .run: (-CGFloat(p.runTailBack), CGFloat(p.walkTailSway) * 0.6, CGFloat(p.walkTailWave), 2 * t - 1.1, CGFloat(p.runTailUncurl))
        case nil: (0, CGFloat(p.idleTailSway), CGFloat(p.idleTailWave), CGFloat(clock * 2 * .pi * p.idleTailHz), 0)
        }
        let k = gait == nil ? 1 : reach
        let lag = CGFloat(p.tailLag)
        var turns: [CGFloat] = [(base * k + sway * sin(beat)) * rad]
        let count = chain.joints.count - 1
        for joint in 1 ..< max(1, count) {
            let along = CGFloat(joint) / CGFloat(count)
            turns.append(wave * rad * along * sin(beat - lag * CGFloat(joint)) - uncurl * k * chain.curl[joint])
        }
        tail.warpGeometry = skin.warp(chain.bent(turns, skin: skin))
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

    // MARK: Films

    /// Whether this cat walks and runs as a film: a builder look not in a body garment (the films have none; the
    /// rebuilt puppet walks in one). Swapped ears and a bobtail go on the film where it can take them (`film(for:)`).
    private var filmsAllowed: Bool {
        guard Self.films, catArt != nil, look != nil else { return false }
        return outfit?.slot != .body
    }

    /// The film's own parts cut out of its frames for the look's: "ears" for swapped ears, "tail" for a bobtail.
    private func filmCuts(_ look: CatLook) -> [String] {
        (look.ears == "own" ? [] : ["ears"]) + (look.tail == "own" ? [] : ["tail"])
    }

    /// Tints the body's films into the look off the main thread, ready for the cat to move in: once the look has
    /// held for half a second (the builder changes it as a slider moves).
    private func prepareFilms() {
        filmLook += 1
        filmFrames = [:]
        hideFilm()
        guard Self.films, let catArt, let look else { return }
        let generation = filmLook
        let cuts = filmCuts(look)
        for (key, film) in filmsOfBody(catArt, look: look) {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard self?.filmLook == generation else { return }
                let images = await Task.detached(priority: .utility) {
                    film.frames.map { FilmImage(catArt.filmFrame($0, look: look, cutting: cuts)) }
                }.value
                guard let self, self.filmLook == generation else { return }
                self.keep(images.map(\.image), for: key, of: film)
            }
        }
    }

    /// The films' frames made now, on this thread (renders and tests).
    func loadFilmsNow() {
        guard Self.films, let catArt, let look else { return }
        for (key, film) in filmsOfBody(catArt, look: look) {
            keep(film.frames.map { catArt.filmFrame($0, look: look, cutting: filmCuts(look)) }, for: key, of: film)
        }
    }

    /// Another cat's film frames in the same look, tinted once for many cats (the contact sheets).
    func shareFilms(from other: CatNode) {
        filmFrames = other.filmFrames
    }

    /// Whether the film for a view and gait is ready to show (tests).
    func hasFilm(_ view: View, _ gait: Gait) -> Bool {
        filmFrames["\(view.rawValue)/\(gait == .run ? "run" : "walk")"] != nil
    }

    /// Whether a film is on show now.
    var isFilming: Bool {
        filmOnShow != nil && !filmHolder.isHidden
    }

    private func filmsOfBody(_ catArt: CatArt, look: CatLook) -> [(String, CatArt.Film)] {
        [View.side, .tqfront].flatMap { view in
            ["walk", "run"].compactMap { gait in
                catArt.film(body: look.body, view: view.rawValue, gait: gait).map { ("\(view.rawValue)/\(gait)", $0) }
            }
        }
    }

    private func keep(_ images: [CGImage?], for key: String, of film: CatArt.Film) {
        let textures = images.compactMap { $0.map { SKTexture(cgImage: $0) } }
        guard textures.count == film.frames.count, !textures.isEmpty else { return }
        for texture in textures {
            texture.filteringMode = .linear
        }
        filmFrames[key] = textures
    }

    /// The film for the gait in the view on show, if this cat has it ready (a trot is the walk, quicker).
    private func film(for gait: Gait) -> (String, CatArt.Film, [SKTexture])? {
        guard filmsAllowed, view != .front, let catArt, let look else { return nil }
        let name = gait == .run ? "run" : "walk"
        let key = "\(view.rawValue)/\(name)"
        guard let frames = filmFrames[key], let film = catArt.film(body: look.body, view: view.rawValue, gait: name) else {
            return nil
        }
        // Swapped ears or a bobtail need the film's own followed (else the puppet walks).
        let points = film.points ?? [:]
        if look.ears != "own", points["ear_near_base"] == nil, points["ear_far_base"] == nil {
            return nil
        }
        if look.tail != "own", points["tail_root"] == nil {
            return nil
        }
        return (key, film, frames)
    }

    /// The film's frame for how far through its stride the cat is, in place of the puppet: drawn the cat's height,
    /// its feet on the cat's origin.
    private func showFilm(_ key: String, film: CatArt.Film, frames: [SKTexture], phase: CGFloat) {
        if filmOnShow != key {
            filmOnShow = key
            filmFrame = -1
            let scale = height / CGFloat(film.height)
            filmNode.size = CGSize(width: film.size[0] * scale, height: film.size[1] * scale)
            filmNode.anchorPoint = CGPoint(x: film.feet[0] / film.size[0], y: 1 - film.feet[1] / film.size[1])
            layFilmPieces(film)
            showOnlyOne()
        }
        let index = min(frames.count - 1, max(0, Int(phase * CGFloat(frames.count))))
        guard index != filmFrame else { return }
        filmFrame = index
        filmNode.texture = frames[index]
        layFilmOutfit(film, frame: index)
        placeFilmPieces(film, frame: index)
    }

    /// The look's swapped ears and bobtail for the film on show: the puppet's own pieces in this view, drawn behind the
    /// frame (the head and rump cover where they join, as on the puppet), placed on the film's followed points.
    private func layFilmPieces(_ film: CatArt.Film) {
        for piece in filmPieces.values {
            piece.removeFromParent()
        }
        filmPieces = [:]
        guard let look, let nodes = parts[view], let points = film.points else { return }
        var wanted: [(String, String)] = []
        if look.ears != "own" {
            wanted += ["ear_near", "ear_far"].filter { points["\($0)_base"] != nil }.map { ($0, $0) }
        }
        if look.tail != "own", points["tail_root"] != nil {
            wanted.append(("tail", nodes["tail_up"] != nil ? "tail_up" : "tail"))
        }
        let behind = (rig.sets[body]?[view.rawValue]?.parts["tail_up"]?.z ?? 1) < 0
        for (key, part) in wanted {
            guard let node = nodes[part] else { continue }
            let piece = SKSpriteNode(texture: node.texture, size: node.size)
            piece.anchorPoint = node.anchorPoint
            piece.zPosition = key == "tail" && !behind ? 0.01 : -0.01
            piece.name = "piece"
            filmNode.addChild(piece)
            filmPieces[key] = piece
        }
    }

    /// Each swapped piece where the film's frame has the part it stands for: an ear from its base towards its tip, the
    /// bobtail at the tail's root, turned as the rump has turned since the start frame.
    private func placeFilmPieces(_ film: CatArt.Film, frame: Int) {
        guard !filmPieces.isEmpty, let points = film.points, let start = film.start else { return }
        let scale = height / CGFloat(film.height)
        func at(_ name: String) -> CGPoint? {
            guard let track = points[name], frame < track.count else { return nil }
            return CGPoint(x: (track[frame][0] - film.feet[0]) * scale, y: -(track[frame][1] - film.feet[1]) * scale)
        }
        func startAt(_ name: String) -> CGPoint? {
            start[name].map { CGPoint(x: ($0[0] - film.feet[0]) * scale, y: -($0[1] - film.feet[1]) * scale) }
        }
        for (key, piece) in filmPieces {
            if key.hasPrefix("ear_") {
                guard let base = at("\(key)_base"), let tip = at("\(key)_tip") else { continue }
                // The ear's own way up (from its anchor to the top of its picture), along base to tip.
                let up = atan2((1 - piece.anchorPoint.y) * piece.size.height, (0.5 - piece.anchorPoint.x) * piece.size.width)
                piece.position = base
                piece.zRotation = atan2(tip.y - base.y, tip.x - base.x) - up
                if let b = startAt("\(key)_base"), let t = startAt("\(key)_tip") {
                    let was = hypot(t.x - b.x, t.y - b.y), now = hypot(tip.x - base.x, tip.y - base.y)
                    piece.yScale = was > 1 ? max(0.75, min(1.25, now / was)) : 1
                }
            } else if let root = at("tail_root") {
                piece.position = root
                if let middle = at("torso_middle"), let rootStart = startAt("tail_root"), let middleStart = startAt("torso_middle") {
                    piece.zRotation = (restAngles[view]?["tail_up"] ?? 0)
                        + atan2(root.y - middle.y, root.x - middle.x) - atan2(rootStart.y - middleStart.y, rootStart.x - middleStart.x)
                }
            }
        }
    }

    /// Back to the puppet (still or moving).
    private func hideFilm() {
        guard filmOnShow != nil || !filmHolder.isHidden else { return }
        filmOnShow = nil
        filmFrame = -1
        filmOutfit?.removeFromParent()
        filmOutfit = nil
        for piece in filmPieces.values {
            piece.removeFromParent()
        }
        filmPieces = [:]
        filmHolder.isHidden = true
        if pose == nil {
            puppets[view]?.isHidden = false
        }
    }

    /// The face in a film's frame, for fitting outfits: its own, or where the cat blinks (its eyes shut, so no face
    /// is found and the head was measured as if from behind: a hat three times too big for a frame, Josh's "dont fit at
    /// all") the nearest frame's in the loop that shows its eyes.
    private func filmFace(_ film: CatArt.Film, frame index: Int) -> CatFace? {
        guard let catArt, !film.frames.isEmpty else { return nil }
        let count = film.frames.count, eyes = view == .side ? 1 : 2
        // Where the head is in a frame, from the points followed through the film (the ears' bases, else the body).
        func headAt(_ i: Int) -> CGPoint? {
            let points = film.points ?? [:]
            let tracks = ["ear_near_base", "ear_far_base"].compactMap { points[$0] }
            let used = tracks.isEmpty ? (points["torso_middle"].map { [$0] } ?? []) : tracks
            let at = used.compactMap { i < $0.count && $0[i].count == 2 ? CGPoint(x: $0[i][0], y: $0[i][1]) : nil }
            guard !at.isEmpty else { return nil }
            return CGPoint(x: at.map(\.x).reduce(0, +) / CGFloat(at.count), y: at.map(\.y).reduce(0, +) / CGFloat(at.count))
        }
        for step in 0 ... count / 2 {
            for i in Set([index - step, index + step]) {
                let j = (i % count + count) % count
                guard let face = catArt.face(film.frames[j]), face.eyes.count >= eyes else { continue }
                // Borrowed from another frame: moved as the head has moved between them (the points are in the
                // frames' master pixels, the face in the sprite's).
                guard j != index, let here = headAt(index), let there = headAt(j), film.size.count == 2, film.size[0] > 0 else {
                    return face
                }
                let k = face.size.width / CGFloat(film.size[0])
                return face.moved(by: CGVector(dx: (here.x - there.x) * k, dy: (here.y - there.y) * k))
            }
        }
        return catArt.face(film.frames[index])
    }

    /// A hat, glasses or neckwear on the film's frame, fitted to the face in it as on a resting pose.
    private func layFilmOutfit(_ film: CatArt.Film, frame index: Int) {
        filmOutfit?.removeFromParent()
        filmOutfit = nil
        filmNode.shader = nil
        guard let outfit, let kind = OutfitFit.kind(outfit), let picture = outfit.sprites[view.rawValue],
              let shape = OutfitShapes.shape(picture, art: art), let face = filmFace(film, frame: index),
              let fit = OutfitFit.place(kind, shape: shape, on: face, view: view.rawValue, size: outfit.fit, tallEars: hasTallEars, coversEars: earsUnderHat)
        else { return }
        filmOutfit = put(picture, fit: fit, face: face, on: filmNode)
        if earsUnderHat {
            cover(filmNode, with: OutfitFit.earCover(fit, shape: shape, on: face, view: view.rawValue), face: face)
        }
        for (key, piece) in filmPieces where key.hasPrefix("ear_") {
            piece.isHidden = earsUnderHat
        }
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
        filmNode.xScale = 1 + squashAmount * 0.5
        filmNode.yScale = 1 - squashAmount
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
        wagTail(nil, t: 0, reach: 1)
        if clock >= nextLook {
            headLookTarget = CGFloat(Double.random(in: -1 ... 1) * p.idleHeadTurn * .pi / 180)
            nextLook = clock + Double.random(in: 1.5 ... 4)
        }
        headLook += (headLookTarget - headLook) * min(1, CGFloat(dt) * 3)
        // Coming to a stop the head lifts back from its carriage on the move.
        nodes["head"]?.zRotation = (rests["head"] ?? 0) - headLook + CGFloat(p.headCarryDegrees) * .pi / 180 * carriage
        if let neck = bodies[view]?.neck {
            nodes["head"]?.position = CGPoint(x: neck.x, y: neck.y - height * CGFloat(p.headCarry) * carriage)
        }
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
            guard let shut = catArt.blinkTexture(headSprite(view, catArt: catArt, look: look), look: look) else { return }
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

    /// Whether the painting or film frame on show is hidden above a hat's rim (a hat the ears go under; tests).
    var poseCovered: Bool {
        poseNode.shader != nil
    }

    var filmCovered: Bool {
        filmNode.shader != nil
    }

    /// How many drawings of the cat are on show (any part see-through or not): always one.
    var drawingsOnShow: Int {
        let pictures: [SKNode] = [poseNode, filmHolder] + Array(puppets.values) + children.filter { $0 is SKSpriteNode && $0 !== poseNode }
        return pictures.filter { !$0.isHidden && $0.alpha > 0.01 }.count
    }

    /// The cat's own outline in its parent's units (the puppet or the painting on show, not its shadow).
    public var bodyFrame: CGRect {
        let shown: [SKNode] = pose != nil ? [poseNode] : isFilming ? [filmHolder] : (puppets[view].map { [$0] } ?? [])
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
