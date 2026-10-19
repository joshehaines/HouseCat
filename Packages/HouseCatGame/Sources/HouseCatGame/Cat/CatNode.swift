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
    /// Each view's puppet's width standing (for its shadow).
    private var puppetWidths: [View: CGFloat] = [:]

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
            let (texture, painted) = sprite(part: name, view: view)
            let width = painted.width * partScale * (name == "torso" ? CGFloat(stretch) : 1)
            let node = SKSpriteNode(texture: texture, size: CGSize(width: width, height: painted.height * partScale))
            node.anchorPoint = CGPoint(x: part.pivot[0], y: 1 - part.pivot[1])
            node.name = name
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


    // MARK: Showing

    /// Shows one view of the puppet, facing left or right (the side view is painted facing left).
    public func show(_ view: View, facingRight: Bool) {
        restoreEyes()
        self.view = view
        self.facingRight = facingRight
        for (v, node) in puppets {
            node.removeAction(forKey: "fade")
            node.shouldEnableEffects = false
            if pose == nil {
                node.alpha = 1
            }
            node.isHidden = v != view
            node.xScale = facingRight ? -1 : 1
        }
        poseNode.xScale = facingRight ? -1 : 1
        placeShadow()
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

    private static let overlap = Tuning.Puppet.fadeOverlap

    /// Fades a puppet as one flat picture, then goes back to drawing its parts directly.
    private func fade(
        _ node: SKEffectNode?,
        to alpha: CGFloat,
        duration: TimeInterval,
        after delay: TimeInterval = 0,
        then done: (() -> Void)? = nil
    ) {
        guard let node else { return }
        node.removeAction(forKey: "fade")
        node.shouldEnableEffects = true
        node.run(.sequence([
            .wait(forDuration: delay),
            .fadeAlpha(to: alpha, duration: duration),
            .run {
                node.shouldEnableEffects = false
                done?()
            },
        ]), withKey: "fade")
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

    /// Settles into a painted resting pose: from moving, the puppet sits down a little and the painting takes over;
    /// from another painting (a glance, a stretch), the old one fades out over the new.
    public func settle(into pose: CatPose, duration: TimeInterval = Tuning.Puppet.settleSeconds) {
        guard let (texture, painted) = poseSprite(pose) else {
            stopCycle()
            return
        }
        restoreEyes()
        let was = self.pose
        stopCycle()
        if let was, was != pose, duration > 0, let old = poseNode.copy() as? SKSpriteNode {
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
        if was == nil {
            let dip = duration > 0 ? Tuning.Puppet.sitDownSeconds : 0
            if duration > 0 {
                squash(CGFloat(Tuning.Puppet.sitDownDip))
            }
            poseNode.run(.sequence([.wait(forDuration: dip), .fadeIn(withDuration: duration * Self.overlap)]))
            fade(puppets[view], to: 0, duration: duration * Self.overlap, after: dip + duration * (1 - Self.overlap))
        } else {
            poseNode.alpha = 1
        }
        placeShadow()
    }

    /// Cross-fades from a resting pose back to the puppet, ready to move: it comes up from a crouch.
    public func rise(to view: View, facingRight: Bool, duration: TimeInterval = Tuning.Puppet.riseSeconds) {
        let was = pose
        show(view, facingRight: facingRight)
        let puppet = puppets[view]
        puppet?.alpha = was == nil ? 1 : 0
        fade(puppet, to: 1, duration: duration * Self.overlap)
        if was != nil, duration > 0 {
            squash(CGFloat(Tuning.Puppet.sitDownDip))
        }
        poseNode.run(.sequence([.wait(forDuration: duration * (1 - Self.overlap)), .fadeOut(withDuration: duration * Self.overlap)]))
        pose = nil
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
        puppets[view]?.children.first?.position.y = 0
    }

    /// Crouches (or squashes on landing) by a share of the height; it eases back by itself.
    public func squash(_ amount: CGFloat) {
        squashAmount = amount
    }

    /// Advances the stride and the cat's life at rest; called each frame by the scene.
    public func step(_ dt: TimeInterval) {
        clock += dt
        live(dt)
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
        if view == .front, let rest = restPositions[view] {
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
            poseNode.yScale = 1 + rise
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
        guard pose == nil, cycle == nil, let nodes = parts[view], let rests = restAngles[view] else { return }
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

    /// The cat's own outline in its parent's units (the puppet or the painting on show, not its shadow).
    public var bodyFrame: CGRect {
        let shown: [SKNode] = (pose != nil ? [poseNode] : []) + (puppets[view].map { [$0] } ?? [])
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
