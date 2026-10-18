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
    private var cycle: (kind: Cycle, phase: CGFloat)?
    /// The outfit the cat wears (OutfitFit: hats, glasses, neckwear), on each view's head and on the pose on show.
    public private(set) var outfit: OutfitsFile.Outfit?
    private var outfitNodes: [SKNode] = []
    private var poseOutfit: SKNode?

    private enum Cycle {
        case walk
        case run
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

    /// Puts an outfit on (nil takes it off). Body garments are not drawn: they are painted for a standing cat.
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

    /// The outfit on the resting pose on show (its own view's picture; a curl is seen from the side).
    private func layPoseOutfit(_ pose: CatPose) {
        poseOutfit?.removeFromParent()
        poseOutfit = nil
        guard let outfit, let kind = OutfitFit.kind(outfit), let catArt, let look,
              let view = OutfitFit.view(for: pose), let picture = outfit.sprites[view],
              let shape = OutfitShapes.shape(picture, art: art),
              let face = catArt.face(catArt.builder.pose(pose.rawValue, look: look).path),
              let fit = OutfitFit.place(kind, shape: shape, on: face, view: view, size: outfit.fit, tallEars: hasTallEars) else { return }
        poseOutfit = put(picture, fit: fit, face: face, on: poseNode)
    }

    /// An outfit picture on a sprite, where the fit says, in the sprite's own frame (it follows its turns and flips).
    private func put(_ picture: String, fit: OutfitFit.Placement, face: CatFace, on parent: SKSpriteNode) -> SKNode {
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
        parent.addChild(node)
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
    }

    /// Turns the moving puppet to another view with a quick cross-fade (front to side
    /// as it reaches the camera); a change of facing alone flips at once.
    public func turn(to newView: View, facingRight: Bool, duration: TimeInterval = Tuning.Puppet.turnSeconds) {
        guard newView != view, pose == nil, let old = puppets[view], let new = puppets[newView] else {
            show(newView, facingRight: facingRight)
            return
        }
        let oldView = view
        stopCycle()
        view = newView
        self.facingRight = facingRight
        new.isHidden = false
        new.xScale = facingRight ? -1 : 1
        new.alpha = 0
        new.zPosition = 0.02 // over the old one while it fades
        poseNode.xScale = new.xScale
        fade(new, to: 1, duration: duration * Self.overlap)
        fade(old, to: 0, duration: duration * Self.overlap, after: duration * (1 - Self.overlap)) { [weak self] in
            old.isHidden = true
            old.alpha = 1
            new.zPosition = 0
            self?.resetPose(oldView)
        }
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

    /// The painted resting pose's texture and master size, if the set has it.
    private func poseSprite(_ pose: CatPose) -> (SKTexture, CGSize)? {
        if let catArt, let look {
            let sprite = catArt.builder.pose(pose.rawValue, look: look)
            guard catArt.has(sprite.path) else { return nil }
            return (catArt.texture(sprite, look: look), catArt.paintedSize(sprite.path))
        }
        let path = "cat/poses/plain/cat_\(body)_\(pose.rawValue).png"
        guard art.has(path) else { return nil }
        return (art.texture(path), art.paintedSize(path))
    }

    /// Cross-fades from the puppet into a painted resting pose (the hand-over the arrival rests on).
    public func settle(into pose: CatPose, duration: TimeInterval = Tuning.Puppet.settleSeconds) {
        stopCycle()
        guard let (texture, painted) = poseSprite(pose) else { return }
        let s = wholeScale(view)
        let stretch = look.flatMap { catArt?.builder.torsoStretch($0) } ?? 1
        poseNode.texture = texture
        poseNode.size = CGSize(width: painted.width * s * CGFloat(stretch), height: painted.height * s)
        self.pose = pose
        layPoseOutfit(pose)
        poseNode.removeAllActions()
        poseNode.run(.fadeIn(withDuration: duration * Self.overlap))
        fade(puppets[view], to: 0, duration: duration * Self.overlap, after: duration * (1 - Self.overlap))
    }

    /// Cross-fades from a resting pose back to the puppet, ready to move.
    public func rise(to view: View, facingRight: Bool, duration: TimeInterval = Tuning.Puppet.riseSeconds) {
        show(view, facingRight: facingRight)
        let puppet = puppets[view]
        puppet?.alpha = pose == nil ? 1 : 0
        fade(puppet, to: 1, duration: duration * Self.overlap)
        poseNode.run(.sequence([.wait(forDuration: duration * (1 - Self.overlap)), .fadeOut(withDuration: duration * Self.overlap)]))
        pose = nil
    }

    // MARK: Moving

    /// Starts the walk cycle (legs swing in pairs, the body bobs, the tail sways).
    public func walk() {
        cycle = (.walk, cycle?.phase ?? 0)
    }

    /// Starts the run cycle: faster, bigger strides and bob.
    public func run() {
        cycle = (.run, cycle?.phase ?? 0)
    }

    public func stopCycle() {
        cycle = nil
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

    /// Advances the cycle; called each frame by the scene.
    public func step(_ dt: TimeInterval) {
        guard var current = cycle, let nodes = parts[view], let rests = restAngles[view],
              let spec = rig.sets[body]?[view.rawValue] else { return }
        let strides = CGFloat(current.kind == .run ? Tuning.Puppet.runHz : Tuning.Puppet.walkHz)
        current.phase = (current.phase + CGFloat(dt) * strides).truncatingRemainder(dividingBy: 1)
        cycle = current
        let t = current.phase * 2 * .pi
        let swing = CGFloat(spec.walk?.legSwing ?? 20) * CGFloat(current.kind == .run ? Tuning.Puppet.runSwing : 1) * .pi / 180
        let s = sin(t)
        func set(_ name: String, _ angle: CGFloat) {
            nodes[name]?.zRotation = (rests[name] ?? 0) - angle
        }
        set("leg_front_near", swing * s)
        set("leg_back_far", swing * s)
        set("leg_front_far", -swing * s)
        set("leg_back_near", -swing * s)
        set("tail_up", CGFloat(spec.walk?.tailSway ?? 6) * .pi / 180 * sin(t + 1.2))
        set("head", CGFloat(spec.walk?.headBob ?? 2) * .pi / 180 * sin(2 * t))
        // The body bobs twice a stride; in the front view the legs cannot swing, so they lift instead.
        let bob = abs(sin(t)) * height * CGFloat(current.kind == .run ? Tuning.Puppet.runBob : Tuning.Puppet.walkBob)
        puppets[view]?.children.first?.position.y = bob
        if view == .front, let rest = restPositions[view] {
            // Legs are relative to the torso, which is scaled up from the parts' pixels; lift in its units.
            let lift = (nodes["leg_front_near"]?.size.height ?? 0) * CGFloat(Tuning.Puppet.frontLegLift)
            for (name, phase) in [("leg_front_near", s), ("leg_front_far", -s), ("leg_back_near", -s), ("leg_back_far", s)] {
                nodes[name]?.position.y = (rest[name]?.y ?? 0) + max(0, phase) * lift
            }
        }
    }
}
