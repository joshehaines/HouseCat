import HouseCatCore
import SpriteKit

/// The cat creator's set (Josh, 19 Oct: "a design wardrobe kind of creation"): the painted dressing room
/// (assets/ui/creator/creator_room.jpg), an open wardrobe behind a round podium, with the cat standing on the
/// podium in the look being made. The room is zoomed so the cat is a good size in the stage, the part of the
/// view the creator's controls leave open, with the podium in the middle of it.
///
/// The cat turns as on a turntable (drag across it, or `turn(by:)`), sits or stands and comes closer for the
/// part being changed (`present`), and reacts to each change with a little bounce and sparkles; a preset or a
/// random look gets a whole twirl. The outfit catalogue dresses it in what is being tried on (`dress`).
@MainActor
public final class DressingRoomScene: SKScene {
    /// Where the cat faces, round the podium; the paintings face left, so the right-hand angles are mirrored.
    public enum Angle: Int, CaseIterable, Sendable {
        case front, threeQuarterLeft, sideLeft, back, sideRight, threeQuarterRight

        var view: CatNode.View {
            switch self {
            case .front, .back: .front
            case .threeQuarterLeft, .threeQuarterRight: .tqfront
            case .sideLeft, .sideRight: .side
            }
        }

        var facingRight: Bool {
            self == .sideRight || self == .threeQuarterRight
        }

        var sittingPose: CatPose {
            switch self {
            case .front: .sitFront
            case .back: .sitBack
            case .threeQuarterLeft, .threeQuarterRight: .sitThreeQuarterFront
            case .sideLeft, .sideRight: .sitSide
            }
        }
    }

    /// How the cat is shown for the part being changed.
    public struct Presentation: Equatable, Sendable {
        public var standing: Bool
        public var angle: Angle
        /// Close on the face (eyes, nose).
        public var face: Bool

        public init(standing: Bool = false, angle: Angle = .threeQuarterLeft, face: Bool = false) {
            self.standing = standing
            self.angle = angle
            self.face = face
        }
    }

    public private(set) var cat: CatNode?
    private let art: ArtLibrary
    private let catArt: CatArt
    let stage = SKNode()
    let room: SKSpriteNode
    private let podiumGlow = SKShapeNode(ellipseOf: CGSize(width: 1, height: 1))
    private var presentation = Presentation()
    public private(set) var angle: Angle = .threeQuarterLeft
    /// The part of the view (SwiftUI's points, from the top left) the controls leave open for the cat.
    private var openRect: CGRect?
    private var lastUpdate: TimeInterval?
    private var nextBlink = 4.0
    private var dragStart: CGPoint?
    private var dragTurned = 0
    private var twirling = false

    public init(size: CGSize, art: ArtLibrary, catArt: CatArt, rig: PuppetRig, look: CatLook) {
        self.art = art
        self.catArt = catArt
        room = SKSpriteNode(texture: art.texture(Tuning.Builder.roomPainting))
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.95, green: 0.84, blue: 0.7, alpha: 1)
        addChild(stage)
        let painted = Self.paintedSize(art)
        room.anchorPoint = .zero
        room.size = painted
        room.zPosition = -10
        stage.addChild(room)
        // A warm pool of light on the podium's top, under the cat.
        podiumGlow.fillColor = SKColor(red: 1, green: 0.88, blue: 0.62, alpha: 0.28)
        podiumGlow.strokeColor = .clear
        podiumGlow.glowWidth = 0
        podiumGlow.zPosition = -1
        podiumGlow.blendMode = .add
        podiumGlow.position = Self.podiumPoint(painted)
        podiumGlow.setScale(1)
        podiumGlow.path = CGPath(ellipseIn: CGRect(
            x: -Tuning.Builder.podiumWidth * 0.36, y: -Tuning.Builder.podiumWidth * 0.06,
            width: Tuning.Builder.podiumWidth * 0.72, height: Tuning.Builder.podiumWidth * 0.12
        ), transform: nil)
        stage.addChild(podiumGlow)
        podiumGlow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.6, duration: 1.8),
            .fadeAlpha(to: 1, duration: 1.8),
        ])))
        let cat = CatNode(
            art: art,
            rig: rig,
            catArt: catArt,
            look: look,
            isKitten: look.age.isKitten,
            height: CGFloat(Tuning.Builder.podiumWidth * Tuning.Builder.catOnPodium)
        )
        cat.position = Self.podiumPoint(painted)
        cat.zPosition = 1
        stage.addChild(cat)
        cat.show(angle.view, facingRight: angle.facingRight)
        cat.settle(into: angle.sittingPose, duration: 0)
        self.cat = cat
        layoutStage(animated: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func paintedSize(_ art: ArtLibrary) -> CGSize {
        let size = art.paintedSize(Tuning.Builder.roomPainting)
        return size == .zero ? CGSize(width: 2688, height: 1520) : size
    }

    /// The podium's top in the painting, from its bottom left.
    private static func podiumPoint(_ painted: CGSize) -> CGPoint {
        CGPoint(x: Tuning.Builder.podiumTop[0], y: painted.height - Tuning.Builder.podiumTop[1])
    }

    // MARK: The stage

    /// The part of the view the controls leave open, in SwiftUI's points from the view's top left.
    public func setOpenRect(_ rect: CGRect) {
        guard rect != openRect else { return }
        let first = openRect == nil
        openRect = rect
        layoutStage(animated: !first)
    }

    override public func didChangeSize(_: CGSize) {
        layoutStage(animated: false)
    }

    /// Zooms and moves the room so the cat is `catInStage` of the open part's height (in a tall, narrow part, at most
    /// `catInStageWidth` of its width), standing on the podium in its middle (or, close on the face, the head in
    /// its middle), never showing past the painting's edges.
    func layoutStage(animated: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let painted = room.size
        let open = openRect.map { CGRect(x: $0.minX, y: size.height - $0.maxY, width: $0.width, height: $0.height) }
            ?? CGRect(origin: .zero, size: size)
        let catHeight = CGFloat(Tuning.Builder.podiumWidth * Tuning.Builder.catOnPodium)
        let cover = max(size.width / painted.width, size.height / painted.height)
        let wanted = min(open.height * CGFloat(Tuning.Builder.catInStage), open.width * CGFloat(Tuning.Builder.catInStageWidth))
        var scale = max(cover, wanted / catHeight)
        let podium = Self.podiumPoint(painted)
        var focus = podium
        var target = CGPoint(x: open.midX, y: open.minY + open.height * CGFloat(Tuning.Builder.podiumInStage))
        if presentation.face, cat != nil {
            // The head, brought to the middle of the open part.
            focus = headPoint()
            scale *= CGFloat(Tuning.Builder.faceZoom)
            target = CGPoint(x: open.midX, y: open.midY)
        }
        var origin = CGPoint(x: target.x - focus.x * scale, y: target.y - focus.y * scale)
        origin.x = min(0, max(size.width - painted.width * scale, origin.x))
        origin.y = min(0, max(size.height - painted.height * scale, origin.y))
        stage.removeAction(forKey: "frame")
        if animated {
            let move = SKAction.group([.move(to: origin, duration: 0.45), .scale(to: scale, duration: 0.45)])
            move.timingMode = .easeInEaseOut
            stage.run(move, withKey: "frame")
        } else {
            stage.position = origin
            stage.setScale(scale)
        }
    }

    // MARK: The cat

    /// Draws the cat in a new look, with a little bounce and sparkles.
    public func show(_ look: CatLook, react: Bool = true) {
        guard let cat, cat.look != look else { return }
        let grew = cat.look?.age.isKitten != look.age.isKitten
        cat.apply(look: look, isKitten: look.age.isKitten)
        if presentation.face || grew {
            layoutStage(animated: true)
        }
        if react {
            bounce()
        }
    }

    /// Sits or stands the cat, turns it and comes closer for the part being changed.
    public func present(_ next: Presentation) {
        guard next != presentation else { return }
        let refocus = next.face != presentation.face
        let sitsDown = presentation.standing && !next.standing
        presentation = next
        face(next.angle, standing: next.standing)
        if refocus {
            // Once the new pose is on show, so the head is measured where it now is.
            let wait = sitsDown ? Tuning.Puppet.sitDownSeconds + 0.05 : 0.05
            run(.sequence([.wait(forDuration: wait), .run { [weak self] in self?.layoutStage(animated: true) }]), withKey: "refocus")
        }
    }

    /// Turns the cat round the podium by whole steps (positive turns it to its left, as if dragged right).
    public func turn(by steps: Int) {
        guard steps != 0, !twirling else { return }
        var next = angle
        for _ in 0 ..< abs(steps) {
            next = step(from: next, by: steps > 0 ? 1 : -1, standing: presentation.standing)
        }
        face(next, standing: presentation.standing)
    }

    /// One full turn on the podium, then back to how it stood (a preset, a surprise look).
    public func twirl() {
        guard let cat, !twirling else { return }
        twirling = true
        let start = angle
        let count = presentation.standing ? 5 : Angle.allCases.count
        var actions: [SKAction] = []
        var at = start
        for _ in 0 ..< count {
            at = step(from: at, by: 1, standing: presentation.standing)
            let next = at
            actions.append(.run { [weak self] in self?.face(next, standing: self?.presentation.standing ?? false, quick: true) })
            actions.append(.wait(forDuration: Tuning.Builder.twirlStepSeconds))
        }
        actions.append(.run { [weak self] in
            guard let self else { return }
            twirling = false
            face(start, standing: presentation.standing)
            sparkle(count: 6)
        })
        cat.run(.sequence(actions), withKey: "twirl")
    }

    /// Puts an outfit on the cat (nil takes it off), with a bounce and sparkles: the outfit catalogue's trying on.
    public func dress(_ outfit: OutfitsFile.Outfit?, react: Bool = true) {
        guard let cat else { return }
        cat.wear(outfit)
        if react {
            bounce(sparkles: 4)
        }
    }

    /// A tap on the cat: it bobs and a heart rises.
    public func pet() {
        bounce(sparkles: 0)
        rise("fx/reactions/fx_reactions_heart.png", from: headPoint(), size: 0.16)
        cat?.blink(slow: true)
    }

    private func step(from angle: Angle, by delta: Int, standing: Bool) -> Angle {
        let all = Angle.allCases
        var index = angle.rawValue
        repeat {
            index = (index + delta + all.count) % all.count
        } while !available(all[index], standing: standing)
        return all[index]
    }

    /// Whether the cat can be shown so: standing has no back view; sitting needs the painted pose.
    private func available(_ angle: Angle, standing: Bool) -> Bool {
        if standing {
            return angle != .back
        }
        guard let look = cat?.look else { return true }
        return catArt.has(catArt.builder.pose(angle.sittingPose.rawValue, look: look).path)
    }

    private func face(_ next: Angle, standing: Bool, quick: Bool = false) {
        guard let cat else { return }
        let target = available(next, standing: standing) ? next : .threeQuarterLeft
        angle = target
        if standing {
            if cat.pose != nil {
                cat.rise(to: target.view, facingRight: target.facingRight, duration: quick ? 0 : Tuning.Puppet.riseSeconds)
            } else {
                cat.turn(to: target.view, facingRight: target.facingRight, duration: quick ? 0.05 : Tuning.Puppet.turnSeconds)
            }
        } else {
            let sitting = cat.pose != nil
            cat.show(target.view, facingRight: target.facingRight)
            cat.settle(into: target.sittingPose, duration: quick || sitting ? 0.12 : Tuning.Puppet.settleSeconds)
        }
    }

    private func bounce(sparkles: Int = 3) {
        cat?.squash(CGFloat(Tuning.Builder.reactSquash))
        sparkle(count: sparkles)
    }

    /// The middle of the cat's head, in the stage: `faceFromTop` down the cat as drawn.
    private func headPoint() -> CGPoint {
        let frame = drawnFrame()
        return CGPoint(x: frame.midX, y: frame.maxY - frame.height * CGFloat(Tuning.Builder.faceFromTop))
    }

    /// The cat as it is drawn now, in the stage: only the pictures on show (the puppet keeps a view for each way
    /// it can face, hidden, and a painting for its resting pose, see-through while it stands).
    func drawnFrame() -> CGRect {
        guard let cat else { return .zero }
        var frame = CGRect.null
        func visit(_ node: SKNode) {
            guard !node.isHidden, node.alpha > 0.05 else { return }
            if let sprite = node as? SKSpriteNode, sprite.texture != nil, let parent = sprite.parent {
                let box = sprite.frame
                for corner in [
                    CGPoint(x: box.minX, y: box.minY),
                    CGPoint(x: box.maxX, y: box.maxY),
                    CGPoint(x: box.minX, y: box.maxY),
                    CGPoint(x: box.maxX, y: box.minY),
                ] {
                    let point = stage.convert(corner, from: parent)
                    frame = frame.union(CGRect(origin: point, size: .zero))
                }
            }
            node.children.forEach(visit)
        }
        visit(cat)
        return frame.isNull ? cat.calculateAccumulatedFrame() : frame
    }

    /// Sparkles that pop around the cat and fade.
    private func sparkle(count: Int) {
        guard cat != nil, count > 0 else { return }
        let frame = drawnFrame()
        for i in 0 ..< count {
            let x = frame.minX + frame.width * CGFloat.random(in: -0.1 ... 1.1)
            let y = frame.minY + frame.height * CGFloat.random(in: 0.2 ... 1.0)
            run(.sequence([
                .wait(forDuration: Double(i) * 0.06),
                .run { [weak self] in self?.rise("fx/reactions/fx_reactions_sparkle.png", from: CGPoint(x: x, y: y), size: 0.1) },
            ]))
        }
    }

    /// A reaction picture that grows, floats up and fades, `size` a share of the podium's width.
    private func rise(_ path: String, from point: CGPoint, size share: Double) {
        guard art.has(path) else { return }
        let node = SKSpriteNode(texture: art.texture(path))
        let width = CGFloat(Tuning.Builder.podiumWidth * share)
        node.size = CGSize(width: width, height: width * node.size.height / max(1, node.size.width))
        node.position = point
        node.zPosition = 5
        node.setScale(0.3)
        node.alpha = 0
        stage.addChild(node)
        let up = SKAction.moveBy(x: 0, y: width * 0.9, duration: 0.9)
        up.timingMode = .easeOut
        node.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.25), up]),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    // MARK: Touches: drag across to turn the cat, tap it to make a fuss of it

    #if canImport(UIKit)
        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            dragStart = touches.first?.location(in: self)
            dragTurned = 0
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let start = dragStart, let point = touches.first?.location(in: self) else { return }
            let steps = Int((point.x - start.x) / CGFloat(Tuning.Builder.turnDragPoints))
            if steps != dragTurned {
                turn(by: steps - dragTurned)
                dragTurned = steps
            }
        }

        override public func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            defer { dragStart = nil }
            guard dragTurned == 0, let point = touches.first?.location(in: self), cat != nil else { return }
            let frame = drawnFrame()
            if frame.insetBy(dx: -frame.width * 0.15, dy: -frame.height * 0.1).contains(stage.convert(point, from: self)) {
                pet()
            }
        }

        override public func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
            dragStart = nil
        }
    #endif

    override public func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(0.1, currentTime - $0) } ?? 0
        lastUpdate = currentTime
        cat?.step(dt)
        nextBlink -= dt
        if nextBlink <= 0 {
            nextBlink = Double.random(in: Tuning.Builder.slowBlinkSeconds)
            // Never a long one while the eyes are being chosen.
            cat?.blink(slow: !presentation.face)
        }
    }
}
