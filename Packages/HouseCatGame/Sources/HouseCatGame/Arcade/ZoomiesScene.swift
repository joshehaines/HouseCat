import HouseCatCore
import SpriteKit

/// Zoomies (the Games menu's runner), drawn: the player's own cat galloping side on along three lanes through the
/// hall, the kitchen, the garden and the street (`arcade/run/bg_*`, each made to repeat), the house's things in its
/// way (`arcade/run/thing_*`), biscuits, toy mice, catnip and boxes to collect. `ZoomiesRun` (HouseCatCore) keeps
/// the course, the cat's lane, jump and slide, and what it bumps; this scene draws it and turns the finger into the
/// run's inputs (swipe up or down for a lane, tap to jump, hold to slide). The app shows the score and the end card.
@MainActor
public final class ZoomiesScene: SKScene {
    public struct Progress: Equatable, Sendable {
        public var score = 0
        public var biscuits = 0
        public var mice = 0
        public var metres = 0
        /// Catnip left, 0 to 1.
        public var catnip = 0.0
        public var shield = false

        public init(score: Int = 0, biscuits: Int = 0, mice: Int = 0, metres: Int = 0, catnip: Double = 0, shield: Bool = false) {
            self.score = score
            self.biscuits = biscuits
            self.mice = mice
            self.metres = metres
            self.catnip = catnip
            self.shield = shield
        }
    }

    public var onProgress: ((Progress) -> Void)?
    /// Each beat as it happens (sounds, haptics).
    public var onBeat: ((ZoomiesBeat) -> Void)?
    /// The run is over (the cat has tumbled and sat up).
    public var onFinish: ((ZoomiesRun) -> Void)?
    /// Debug runs and tests: the run plays itself (`ZoomiesBot`).
    public var autoplay = false
    public private(set) var run: ZoomiesRun

    private let art: ArtLibrary
    private let cat: CatNode
    /// The cat's place: across it stays put, up and down it follows the lane and the jump.
    private let holder = SKNode()
    private let stage = SKNode()
    private let items = SKNode()
    private var backdrops: [SKSpriteNode] = []
    private var backdropWidth: CGFloat = 1
    private var scrolled: CGFloat = 0
    private var shownZone = 0
    private var nodes: [Int: SKNode] = [:]
    private var running = false
    private var finished = false
    private var lastUpdate: TimeInterval?
    private var lastReport = -1.0
    private var touchStart: (point: CGPoint, time: TimeInterval)?
    private var swiped = false
    private var sliding = false
    private var shownLane: CGFloat = 1
    private var squashY: CGFloat = 1
    private static let catUnits: CGFloat = 100
    /// The backdrops in run order (hall, kitchen, garden, street) and the things each part of the home puts out.
    static let zones = ["hall", "kitchen", "garden", "street"]
    static let things: [String: [ZoomiesThing: [String]]] = [
        "hall": [.low: ["books", "boots"], .high: ["table"], .block: ["basket"]],
        "kitchen": [.low: ["recycling", "boots"], .high: ["table"], .block: ["basket", "bin"]],
        "garden": [.low: ["can", "pot"], .high: ["washing"], .block: ["bin", "bicycle"]],
        "street": [.low: ["recycling", "pot"], .high: ["bench"], .block: ["bicycle", "bin"]],
    ]

    public init(size: CGSize, seed: DaySeed, art: ArtLibrary, catArt: CatArt, rig: PuppetRig, look: CatLook,
                outfit: OutfitsFile.Outfit? = nil)
    {
        run = ZoomiesRun(seed: seed)
        self.art = art
        cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: Self.catUnits)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.96, green: 0.86, blue: 0.7, alpha: 1)
        cat.wear(outfit)
        cat.show(.side, facingRight: true)
        cat.run()
        holder.addChild(cat)
        build()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The run starts (after the app's count).
    public func start() {
        running = true
        lastUpdate = nil
    }

    public func pause(_ paused: Bool) {
        running = !paused && !finished
        lastUpdate = nil
    }

    override public func didChangeSize(_: CGSize) {
        build()
    }

    // MARK: Layout

    /// Points per metre along the run: `Tuning.Arcade.Zoomies.metresAcross` fill the width.
    private var ppm: CGFloat {
        size.width / CGFloat(Tuning.Arcade.Zoomies.metresAcross)
    }

    /// Where the cat's feet are across.
    private var catX: CGFloat {
        size.width * CGFloat(Tuning.Arcade.Zoomies.catAcross)
    }

    /// A lane's floor line (0 at the back) and how big things in it are drawn.
    private func laneY(_ lane: CGFloat) -> CGFloat {
        let z = Tuning.Arcade.Zoomies.self
        return size.height * CGFloat(z.backLaneY + (z.frontLaneY - z.backLaneY) * Double(lane) / Double(z.lanes - 1))
    }

    private func laneScale(_ lane: CGFloat) -> CGFloat {
        let z = Tuning.Arcade.Zoomies.self
        return CGFloat(z.backLaneScale + (1 - z.backLaneScale) * Double(lane) / Double(z.lanes - 1))
    }

    private func build() {
        guard size.width > 0, size.height > 0 else { return }
        if stage.parent == nil {
            addChild(stage)
            stage.addChild(items)
            stage.addChild(holder)
        }
        for node in backdrops {
            node.removeFromParent()
        }
        backdrops = []
        let path = "arcade/run/bg_\(Self.zones[shownZone % Self.zones.count]).jpg"
        let painted = art.paintedSize(path)
        let height = size.height
        backdropWidth = painted.height > 0 ? height * painted.width / painted.height : size.width
        // Enough copies side by side to cover the width as they slide.
        let count = Int(ceil(size.width / backdropWidth)) + 1
        for n in 0 ..< count {
            let node = SKSpriteNode(texture: art.texture(path), size: CGSize(width: backdropWidth, height: height))
            node.anchorPoint = .zero
            node.position = CGPoint(x: CGFloat(n) * backdropWidth, y: 0)
            node.zPosition = -100
            stage.addChild(node)
            backdrops.append(node)
        }
        for (_, node) in nodes {
            node.removeFromParent()
        }
        nodes = [:]
        placeCat(dt: 0)
        placeItems()
    }

    /// The backdrops for a part of the home (a flash covers the change).
    private func changeZone(to zone: Int) {
        shownZone = zone
        let flash = SKSpriteNode(color: .white, size: size)
        flash.anchorPoint = .zero
        flash.zPosition = 500
        flash.alpha = 0
        addChild(flash)
        flash.run(.sequence([
            .fadeAlpha(to: 0.85, duration: 0.12),
            .run { [weak self] in
                guard let self else { return }
                let path = "arcade/run/bg_\(Self.zones[zone % Self.zones.count]).jpg"
                for node in backdrops {
                    node.texture = art.texture(path)
                }
            },
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    // MARK: The cat

    private func placeCat(dt: TimeInterval) {
        let z = Tuning.Arcade.Zoomies.self
        // The lane eases across as the run moves the cat between lanes.
        let target = CGFloat(run.laneProgress >= 1 ? Double(run.lane) : Double(run.fromLane) + (Double(run.lane - run.fromLane)) * run.laneProgress)
        shownLane = target
        let scale = laneScale(shownLane)
        let catHeight = size.height * CGFloat(z.catShare) * scale
        cat.setScale(catHeight / Self.catUnits)
        let lift = CGFloat(run.height / z.jumpHeight) * size.height * CGFloat(z.jumpShare) * scale
        holder.position = CGPoint(x: catX, y: laneY(shownLane) + lift)
        cat.shadowDrop = lift / cat.xScale
        // Sliding: low and long.
        let want: CGFloat = run.isSliding ? CGFloat(z.slideSquash) : 1
        squashY += (want - squashY) * min(1, CGFloat(dt) * 18)
        holder.yScale = squashY
        holder.xScale = 1 + (1 - squashY) * 0.35
        holder.zPosition = 10 + shownLane * 20 + 10
        cat.moveSpeed = finished ? 0 : CGFloat(run.speed) * ppm / cat.xScale
    }

    // MARK: Things on the course

    private func node(for item: ZoomiesItem) -> SKNode {
        if let node = nodes[item.id] {
            return node
        }
        let zone = Self.zones[(Int(item.at / Tuning.Arcade.Zoomies.zoneLength)) % Self.zones.count]
        let z = Tuning.Arcade.Zoomies.self
        let node: SKSpriteNode
        let scale = laneScale(CGFloat(item.lane))
        switch item.thing {
        case .low, .high, .block:
            let names = Self.things[zone]?[item.thing] ?? ["basket"]
            let path = "arcade/run/thing_\(names[item.id % names.count]).png"
            let painted = art.paintedSize(path)
            let share: Double = switch item.thing {
            case .low: z.lowShare
            case .high: z.highShare
            default: z.blockShare
            }
            let height = size.height * CGFloat(share) * scale
            node = SKSpriteNode(texture: art.texture(path), size: CGSize(width: height * painted.width / max(1, painted.height), height: height))
            node.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        case .biscuit, .mouse, .catnip, .box:
            let name: String = switch item.thing {
            case .biscuit: "biscuit"
            case .mouse: "mouse"
            case .catnip: "catnip"
            default: "box"
            }
            let path = "arcade/ui/icon_game_\(name).png"
            let painted = art.paintedSize(path)
            let height = size.height * CGFloat(item.thing == .biscuit ? z.biscuitShare : z.pickupShare) * scale
            node = SKSpriteNode(texture: art.texture(path), size: CGSize(width: height * painted.width / max(1, painted.height), height: height))
            node.anchorPoint = CGPoint(x: 0.5, y: item.thing == .mouse ? 0.05 : -0.6)
            if item.thing != .mouse {
                node.run(.repeatForever(.sequence([
                    .moveBy(x: 0, y: height * 0.12, duration: 0.45),
                    .moveBy(x: 0, y: -height * 0.12, duration: 0.45),
                ])))
            }
        }
        node.zPosition = 10 + CGFloat(item.lane) * 20 + (item.thing.isObstacle ? 5 : 8)
        node.position.y = laneY(CGFloat(item.lane))
        items.addChild(node)
        nodes[item.id] = node
        return node
    }

    private func placeItems() {
        var live = Set<Int>()
        for item in run.items {
            let x = catX + CGFloat(item.at + item.thing.length / 2 - run.distance) * ppm
            guard x < size.width + 200 else { continue }
            live.insert(item.id)
            let node = node(for: item)
            node.position.x = x
        }
        for (id, node) in nodes where !live.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
    }

    // MARK: The loop

    override public func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 20, lastUpdate.map { currentTime - $0 } ?? 0)
        lastUpdate = currentTime
        cat.step(dt)
        guard running, !finished else {
            placeCat(dt: dt)
            return
        }
        if autoplay {
            for input in ZoomiesBot.act(on: run) {
                run.input(input)
            }
        }
        let before = run.distance
        for beat in run.step(dt) {
            handle(beat)
        }
        scrolled += CGFloat(run.distance - before) * ppm
        for (n, node) in backdrops.enumerated() {
            var x = CGFloat(n) * backdropWidth - scrolled.truncatingRemainder(dividingBy: backdropWidth)
            if x < -backdropWidth { x += CGFloat(backdrops.count) * backdropWidth }
            node.position.x = x
        }
        placeCat(dt: dt)
        placeItems()
        if run.elapsed - lastReport >= 0.1 || run.over {
            lastReport = run.elapsed
            onProgress?(Progress(score: run.score, biscuits: run.biscuits, mice: run.mice, metres: Int(run.distance),
                                 catnip: run.magnet / Tuning.Arcade.Zoomies.magnetSeconds, shield: run.shield))
        }
    }

    private func handle(_ beat: ZoomiesBeat) {
        onBeat?(beat)
        switch beat {
        case let .collected(item):
            guard let node = nodes[item.id] else { return }
            nodes[item.id] = nil
            node.removeAllActions()
            let target = CGPoint(x: holder.position.x, y: holder.position.y + size.height * 0.12)
            node.run(.sequence([
                .group([.move(to: target, duration: 0.14), .scale(to: 0.4, duration: 0.14), .fadeAlpha(to: 0.6, duration: 0.14)]),
                .removeFromParent(),
            ]), withKey: "collect")
            if item.thing == .mouse || item.thing == .catnip || item.thing == .box {
                cat.squash(0.12)
            }
        case let .shieldUsed(item):
            nodes[item.id]?.run(.sequence([.group([.scale(to: 1.3, duration: 0.15), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
            nodes[item.id] = nil
            cat.squash(0.2)
        case .bumped:
            tumble()
        case let .zone(zone):
            changeZone(to: zone)
        }
    }

    /// Bumped: the cat flips, lands on its feet and sits up, then the run is over.
    private func tumble() {
        finished = true
        cat.stopCycle()
        let up = size.height * 0.16
        cat.run(.sequence([
            .group([
                .sequence([.moveBy(x: 0, y: up, duration: 0.22), .moveBy(x: 0, y: -up, duration: 0.24)]),
                .rotate(byAngle: .pi * 2, duration: 0.46),
            ]),
            .run { [weak self] in
                guard let self else { return }
                cat.zRotation = 0
                cat.squash(0.25)
                cat.settle(into: .sitSide)
            },
            .wait(forDuration: 0.8),
            .run { [weak self] in
                guard let self else { return }
                onFinish?(run)
            },
        ]))
    }

    // MARK: The finger

    #if os(iOS)
        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            touchStart = (touch.location(in: self), touch.timestamp)
            swiped = false
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first, let start = touchStart, !swiped else { return }
            let point = touch.location(in: self)
            let dy = point.y - start.point.y
            if abs(dy) > Tuning.Arcade.Zoomies.swipePoints {
                swiped = true
                if sliding {
                    sliding = false
                    run.input(.slideEnd)
                }
                // Up the screen is towards the back lane.
                run.input(dy > 0 ? .up : .down)
            }
        }

        override public func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first, let start = touchStart else { return }
            touchStart = nil
            if sliding {
                sliding = false
                run.input(.slideEnd)
            } else if !swiped, touch.timestamp - start.time < Tuning.Arcade.Zoomies.holdSeconds {
                run.input(.jump)
            }
        }

        override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchesEnded(touches, with: event)
        }
    #endif

    /// A finger held still past `holdSeconds` starts a slide (checked each frame by the app's timer-free loop).
    override public func didFinishUpdate() {
        guard let start = touchStart, !swiped, !sliding, running, !finished else { return }
        if (lastUpdate ?? 0) - start.time >= Tuning.Arcade.Zoomies.holdSeconds {
            sliding = true
            run.input(.slideStart)
        }
    }
}
