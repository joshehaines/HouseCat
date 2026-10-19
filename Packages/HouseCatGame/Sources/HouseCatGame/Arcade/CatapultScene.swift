import HouseCatCore
import SpriteKit

/// Catapult (the Games menu's pounce game), drawn: the level's place painted behind (`arcade/pounce/place_<biome>`),
/// its ledges, the towers of household things and the toy mice, and the player's own cat crouched on its cushion on
/// the cat tree. Drag back from the cat to aim (dots show the start of the arc), let go and it pounces, curled into
/// a ball (its own sleeping painting) until it lands on its feet. `CatapultGame` (HouseCatCore) runs the physics;
/// this scene draws each body where the game has it and frames the level.
@MainActor
public final class CatapultScene: SKScene {
    public struct Progress: Equatable, Sendable {
        public var knocked = 0
        public var mice = 0
        public var pouncesLeft = 0
        public var flying = false

        public init(knocked: Int = 0, mice: Int = 0, pouncesLeft: Int = 0, flying: Bool = false) {
            self.knocked = knocked
            self.mice = mice
            self.pouncesLeft = pouncesLeft
            self.flying = flying
        }
    }

    public var onProgress: ((Progress) -> Void)?
    public var onBeat: ((CatapultBeat) -> Void)?
    /// The level is over: won (with its stars) or out of pounces.
    public var onFinish: ((CatapultGame) -> Void)?
    /// Debug runs and tests: the level plays its own solution.
    public var autoplay = false
    public private(set) var game: CatapultGame

    private let art: ArtLibrary
    private let cat: CatNode
    private let ball: SKSpriteNode
    private let world = SKNode()
    private let dots = SKNode()
    private var bodies: [Int: SKNode] = [:]
    /// Points per metre and where the world's origin is on screen.
    private var ppm: CGFloat = 50
    private var origin = CGPoint.zero
    private var aim: (angle: Double, power: Double)?
    private var lastUpdate: TimeInterval?
    private var finished = false
    private var autoplayShot = 0
    private var autoplayWait = 0.0
    private static let catUnits: CGFloat = 100

    public init(size: CGSize, level: CatapultLevel, art: ArtLibrary, catArt: CatArt, rig: PuppetRig, look: CatLook,
                outfit: OutfitsFile.Outfit? = nil)
    {
        game = CatapultGame(level: level)
        self.art = art
        cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: Self.catUnits)
        // In the air the cat is curled into a ball: its own sleeping painting, turning.
        let curl = catArt.builder.pose(CatPose.sleepCurl.rawValue, look: look)
        ball = SKSpriteNode(texture: catArt.has(curl.path) ? catArt.texture(curl, look: look) : nil)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.7, green: 0.85, blue: 0.95, alpha: 1)
        cat.wear(outfit)
        cat.show(.side, facingRight: true)
        build()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func didChangeSize(_: CGSize) {
        build()
    }

    // MARK: Layout

    /// The world from just left of the cat tree to past the furthest thing, and from the ground to above the highest,
    /// fitted to the screen with room for the controls along the top.
    private func frame() {
        let c = Tuning.Arcade.Catapult.self
        let level = game.level
        let right = max(
            level.pieces.map { $0.x + $0.half.x }.max() ?? 10,
            level.ledges.map { $0.x + $0.width / 2 }.max() ?? 10,
            level.mice.map(\.x).max() ?? 10
        ) + c.frameMargin
        let top = max(level.pieces.map(\.top).max() ?? 2, level.ledges.map { $0.y + $0.height }.max() ?? 2, c.launch.y + 2) + c.frameHeadroom
        let left = c.frameLeft
        let usable = CGSize(width: size.width, height: size.height * CGFloat(1 - c.frameTopShare - c.frameGroundShare))
        ppm = min(usable.width / CGFloat(right - left), usable.height / CGFloat(top))
        origin = CGPoint(x: -CGFloat(left) * ppm, y: size.height * CGFloat(c.frameGroundShare))
    }

    private func point(_ v: Vec2) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(v.x) * ppm, y: origin.y + CGFloat(v.y) * ppm)
    }

    private func build() {
        guard size.width > 0, size.height > 0 else { return }
        removeAllChildren()
        world.removeAllChildren()
        bodies = [:]
        frame()
        // The place: its ground line at the world's ground.
        let path = "arcade/pounce/place_\(game.level.place.rawValue).jpg"
        let painted = art.paintedSize(path)
        let backdrop = SKSpriteNode(texture: art.texture(path))
        let groundShare = Tuning.Arcade.Catapult.paintingGround
        let height = max(size.height, (size.width * painted.height / max(1, painted.width)))
        backdrop.size = CGSize(width: height * painted.width / max(1, painted.height), height: height)
        backdrop.anchorPoint = CGPoint(x: 0.5, y: CGFloat(groundShare))
        backdrop.position = CGPoint(x: size.width / 2, y: origin.y)
        backdrop.zPosition = -100
        if backdrop.position.y - backdrop.size.height * CGFloat(groundShare) > 0 {
            backdrop.anchorPoint.y = 0
            backdrop.position.y = 0
        }
        addChild(backdrop)
        addChild(world)
        world.addChild(dots)
        dots.zPosition = 40
        // The cat tree under the cushion the cat pounces from.
        let tree = SKSpriteNode(texture: art.texture("arcade/pounce/piece_tree.png"))
        let treeHeight = CGFloat(Tuning.Arcade.Catapult.launch.y - Tuning.Arcade.Catapult.catRadius) * ppm
        let treePainted = art.paintedSize("arcade/pounce/piece_tree.png")
        tree.size = CGSize(width: treeHeight * treePainted.width / max(1, treePainted.height), height: treeHeight)
        tree.anchorPoint = CGPoint(x: 0.5, y: 0)
        tree.position = point(Vec2(Tuning.Arcade.Catapult.launch.x, 0))
        tree.zPosition = 5
        world.addChild(tree)
        cat.setScale(CGFloat(Tuning.Arcade.Catapult.catRadius * 2.6) * ppm / Self.catUnits)
        cat.position = point(Vec2(Tuning.Arcade.Catapult.launch.x, Tuning.Arcade.Catapult.launch.y - Tuning.Arcade.Catapult.catRadius))
        cat.zPosition = 30
        cat.removeFromParent()
        world.addChild(cat)
        ball.size = CGSize(width: CGFloat(Tuning.Arcade.Catapult.catRadius * 2.3) * ppm,
                           height: CGFloat(Tuning.Arcade.Catapult.catRadius * 2.3) * ppm * (ball.texture.map { $0.size().height / max(1, $0.size().width) } ?? 1))
        ball.zPosition = 31
        ball.isHidden = true
        ball.removeFromParent()
        world.addChild(ball)
        placeBodies()
    }

    private func sprite(for body: PounceBody) -> SKNode {
        if let node = bodies[body.id] {
            return node
        }
        let node: SKNode
        switch body.role {
        case "ground", "cat":
            node = SKNode()
        case "ledge":
            let path = "arcade/pounce/ledge_\(game.level.place.rawValue).png"
            let sprite = SKSpriteNode(texture: art.texture(path))
            if case let .box(h) = body.shape {
                sprite.size = CGSize(width: CGFloat(h.x * 2) * ppm, height: CGFloat(h.y * 2) * ppm)
            }
            // Stretched from its middle so its top edge and ends keep their shape.
            sprite.centerRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
            node = sprite
        case "mouse":
            node = picture("arcade/pounce/piece_mouse.png", body: body, fill: 1.25)
        default:
            let name: String = switch body.role {
            case "book": ["book_red", "book_blue", "book_green"][body.id % 3]
            case "short": "plank"
            default: body.role
            }
            node = picture("arcade/pounce/piece_\(name).png", body: body, fill: 1.06)
        }
        node.zPosition = body.role == "mouse" ? 22 : 20
        world.addChild(node)
        bodies[body.id] = node
        return node
    }

    /// A piece's painting stretched over its body (a little larger, as the paintings have soft edges).
    private func picture(_ path: String, body: PounceBody, fill: CGFloat) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: art.texture(path))
        switch body.shape {
        case let .box(h):
            sprite.size = CGSize(width: CGFloat(h.x * 2) * ppm * fill, height: CGFloat(h.y * 2) * ppm * fill)
        case let .ball(r):
            sprite.size = CGSize(width: CGFloat(r * 2) * ppm * fill, height: CGFloat(r * 2) * ppm * fill)
        }
        return sprite
    }

    private func placeBodies() {
        var live = Set<Int>()
        for body in game.world.bodies {
            live.insert(body.id)
            let node = sprite(for: body)
            node.position = point(body.position)
            node.zRotation = CGFloat(body.rotation)
        }
        for (id, node) in bodies where !live.contains(id) {
            node.removeFromParent()
            bodies[id] = nil
        }
        if let id = game.catID, let body = game.world.body(id) {
            ball.isHidden = false
            ball.position = point(body.position)
            ball.zRotation = CGFloat(body.rotation)
        }
    }

    // MARK: The loop

    override public func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 20, lastUpdate.map { currentTime - $0 } ?? 0)
        lastUpdate = currentTime
        cat.step(dt)
        if autoplay, !game.flying, !game.over {
            autoplayWait += dt
            if autoplayWait > 0.8 {
                autoplayWait = 0
                let solution = game.level.solution
                let shot = solution.isEmpty ? CatapultLevel.Shot(angle: 30, power: 0.7) : solution[min(autoplayShot, solution.count - 1)]
                autoplayShot += 1
                pounce(angle: shot.angle, power: shot.power)
            }
        }
        for beat in game.step(dt) {
            handle(beat)
        }
        placeBodies()
        onProgress?(Progress(knocked: game.knocked.count, mice: game.level.mice.count, pouncesLeft: game.pouncesLeft, flying: game.flying))
    }

    private func handle(_ beat: CatapultBeat) {
        onBeat?(beat)
        switch beat {
        case let .knocked(index, caught):
            // The toy mouse hops and scurries off the way it fell (or squeaks up out from under the cat's paws).
            let id = game.mouseIDs[index]
            guard let node = bodies.removeValue(forKey: id) else { return }
            let away: CGFloat = node.position.x > size.width / 2 ? 1 : -1
            node.run(.sequence([
                .group([
                    .sequence([.moveBy(x: 0, y: ppm * (caught ? 0.8 : 0.4), duration: 0.18),
                               .moveBy(x: away * size.width * 0.6, y: -ppm * 0.4, duration: 0.7)]),
                    .rotate(toAngle: 0, duration: 0.1),
                    .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)]),
                ]),
                .removeFromParent(),
            ]))
        case .settled:
            // The cat trots back to its cushion.
            ball.isHidden = true
            cat.isHidden = false
            cat.alpha = 0
            cat.run(.fadeIn(withDuration: 0.25))
        case .won, .lost:
            guard !finished else { return }
            finished = true
            run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in
                guard let self else { return }
                onFinish?(game)
            }]))
        }
    }

    // MARK: Aiming

    /// Pounces now (the finger's release, or the debug autoplay).
    public func pounce(angle: Double, power: Double) {
        guard game.pounce(angle: angle, power: power) else { return }
        dots.removeAllChildren()
        cat.isHidden = true
        ball.isHidden = false
        ball.position = point(Tuning.Arcade.Catapult.launch)
    }

    /// The dots along the first part of the arc for a pull.
    private func showAim(angle: Double, power: Double) {
        dots.removeAllChildren()
        let c = Tuning.Arcade.Catapult.self
        for n in 1 ... c.aimDots {
            let t = Double(n) * c.aimDotSeconds
            let p = point(CatapultGame.arc(angle: angle, power: power, at: t))
            let dot = SKShapeNode(circleOfRadius: max(2.5, ppm * 0.045 * CGFloat(1 - Double(n) / Double(c.aimDots + 2))))
            dot.fillColor = SKColor(white: 1, alpha: 0.9)
            dot.strokeColor = SKColor(red: 0.24, green: 0.18, blue: 0.22, alpha: 0.4)
            dot.position = p
            dots.addChild(dot)
        }
        // The cat wiggles down, readier the harder the pull.
        cat.squash(CGFloat(0.08 + 0.18 * power))
    }

    /// The pull from the cat to the finger: the pounce goes the other way, the harder the further back.
    private func aim(from finger: CGPoint) -> (angle: Double, power: Double) {
        let launch = point(Tuning.Arcade.Catapult.launch)
        let dx = Double(launch.x - finger.x), dy = Double(launch.y - finger.y)
        let reach = Double(Tuning.Arcade.Catapult.pullMetres) * Double(ppm)
        let power = min(1, (dx * dx + dy * dy).squareRoot() / reach)
        let angle = atan2(dy, max(0.001, dx)) * 180 / .pi
        return (min(max(angle, Tuning.Arcade.Catapult.lowestAngle), Tuning.Arcade.Catapult.highestAngle), power)
    }

    #if os(iOS)
        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard !game.flying, !game.over, let touch = touches.first else { return }
            aim = aim(from: touch.location(in: self))
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard aim != nil, let touch = touches.first else { return }
            let next = aim(from: touch.location(in: self))
            aim = next
            showAim(angle: next.angle, power: next.power)
        }

        override public func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
            guard let shot = aim else { return }
            aim = nil
            if shot.power >= Tuning.Arcade.Catapult.leastPull {
                pounce(angle: shot.angle, power: shot.power)
            } else {
                dots.removeAllChildren()
            }
        }

        override public func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
            aim = nil
            dots.removeAllChildren()
        }
    #endif
}
