import HouseCatCore
import SpriteKit
#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// The three mini-games (SPEC "Mini-games", CONTENT.md §6), drawn with the player's own cat on the living room's
/// own floor and wall: the dot to pounce on, the mantel to clear, the sparkles to string together. HouseCatCore's
/// game models keep the score; this scene moves the pieces, passes the finger on and makes something of each beat
/// (a burst, the points floating up, a shake, the cat's reaction). The app shows the clock, the combo and the stars,
/// and plays the sounds.
@MainActor
public final class MiniGameScene: SKScene {
    public enum Game {
        case laser(LaserChase)
        case knock(KnockItOff)
        case string(StringChase)

        var elapsed: Double {
            switch self {
            case let .laser(game): game.elapsed
            case let .knock(game): game.elapsed
            case let .string(game): game.elapsed
            }
        }

        var duration: Double {
            switch self {
            case let .laser(game): game.duration
            case let .knock(game): game.duration
            case let .string(game): game.duration
            }
        }

        public var score: Double {
            switch self {
            case let .laser(game): game.score
            case let .knock(game): game.score
            case let .string(game): game.score
            }
        }

        var isOver: Bool {
            switch self {
            case let .laser(game): game.isOver
            case let .knock(game): game.isOver
            case let .string(game): game.isOver
            }
        }

        var combo: Combo {
            switch self {
            case let .laser(game): game.combo
            case let .knock(game): game.combo
            case let .string(game): game.combo
            }
        }

        var hasZoomies: Bool {
            switch self {
            case let .laser(game): game.hasZoomies
            case let .knock(game): game.hasZoomies
            case let .string(game): game.hasZoomies
            }
        }
    }

    /// What the app hears: the clock, the score and the combo as they change.
    public struct Progress: Equatable, Sendable {
        public var elapsed: Double
        public var duration: Double
        public var score: Double
        /// Hits in a row, and what the next is worth.
        public var combo = 0
        public var multiplier = 1
        public var bestCombo = 0
        public var zoomies = false
        public var golden = false

        public init(elapsed: Double, duration: Double, score: Double) {
            self.elapsed = elapsed
            self.duration = duration
            self.score = score
        }
    }

    public var onProgress: ((Progress) -> Void)?
    /// Each beat as it happens (for the sounds, the haptics and the cat's lines).
    public var onBeat: ((PlayBeat) -> Void)?
    public var onFinish: ((Double) -> Void)?
    /// Debug screenshot runs: the game plays itself (`MiniGameBot`, as the tests play it).
    public var autoplay = false
    public private(set) var game: Game

    private let art: ArtLibrary
    private let cat: CatNode
    /// The cat's place, lean and turn (the puppet keeps its own scale and poses inside it).
    private let holder = SKNode()
    private let stage = SKNode()
    private let fx = SKNode()
    private var running = false
    private var finished = false
    private var lastUpdate: TimeInterval?
    private var lastReport = -1.0
    private var finger: CGPoint?
    /// The cat's gait, kept so it changes only when it must.
    private var gait: Gait = .sitting
    private var stoppedFor = 0.0
    private var arena = CGRect.zero
    private var cell: CGFloat = 40
    private let floorName: String?
    private let wallName: String?
    private let objectNames: [String]
    private let catnipName: String
    /// Knock It Off: the shelf's top, its length for the things (0 to 1 along it), the cat's nose ahead of its middle.
    private var shelfTop: CGFloat = 0
    private var shelfFrom: CGFloat = 0
    private var shelfLength: CGFloat = 1
    private var noseOffset: CGFloat = 0
    private var shownOffset: CGFloat = 0
    private var walking = false
    /// Laser Pointer: the dot drawn golden.
    private var dotGolden = false

    private static let catUnits: CGFloat = 100
    /// Knock It Off: how deep the mantel's top is, in cells.
    private static let deckDepth: CGFloat = 0.42

    private enum Gait {
        /// Standing with its legs still (crouched, in the air, landed).
        case still
        case sitting, walking, running
    }

    /// `floor` and `wall` are the living room's tiles (art paths); `objects` the things on the shelf, `catnip` the
    /// catnip fish.
    public init(
        size: CGSize,
        game: Game,
        art: ArtLibrary,
        catArt: CatArt,
        rig: PuppetRig,
        look: CatLook,
        floor: String?,
        wall: String?,
        objects: [String],
        catnip: String
    ) {
        self.game = game
        self.art = art
        floorName = floor
        wallName = wall
        objectNames = objects
        catnipName = catnip
        // Drawn a fixed height and scaled to the floor's cells.
        cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: Self.catUnits)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.86, green: 0.74, blue: 0.6, alpha: 1)
        cat.name = "cat"
        holder.addChild(cat)
        build()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The clock starts (after the app's countdown).
    public func start() {
        running = true
        lastUpdate = nil
    }

    override public func didChangeSize(_: CGSize) {
        build()
    }

    // MARK: Building the room

    private func build() {
        // Also called from SKScene's own init (a size change), before this scene's init is done.
        guard size.width > 0, size.height > 0 else { return }
        if stage.parent == nil {
            addChild(stage)
        }
        stage.removeAllChildren()
        fx.removeAllChildren()
        holder.removeFromParent()
        stage.addChild(holder)
        stage.addChild(fx)
        fx.zPosition = 80
        let top = size.height * Tuning.MiniGames.hudShare
        if case .knock = game {
            buildShelf()
        } else {
            let available = CGRect(x: size.width * 0.06, y: size.height * 0.06, width: size.width * 0.88, height: size.height * 0.94 - top)
            cell = min(available.width / Tuning.MiniGames.arenaWidth, available.height / Tuning.MiniGames.arenaHeight)
            let width = cell * Tuning.MiniGames.arenaWidth, height = cell * Tuning.MiniGames.arenaHeight
            arena = CGRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height)
            // A little past the edges, so a shake never shows one.
            tile(floorName, in: CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40), tile: size.height * 0.42, z: -10)
            let rug = SKSpriteNode(texture: art.texture("furniture/living/furn_living_rug_R.png"))
            let rugWidth = arena.width * 1.08
            rug.size = CGSize(width: rugWidth, height: rugWidth * rug.texture!.size().height / max(1, rug.texture!.size().width))
            rug.position = CGPoint(x: arena.midX, y: arena.midY)
            rug.zPosition = -9
            stage.addChild(rug)
            cat.setScale(cell * Tuning.MiniGames.catCells / Self.catUnits)
            cat.show(.side, facingRight: cat.facingRight)
        }
        vignette()
        switch game {
        case let .laser(laser):
            stage.addChild(makeDot())
            if laser.catnip.showing(laser.elapsed) {
                showCatnip(at: point(laser.catnip.at))
            }
        case let .string(chase):
            for sparkle in chase.sparkles {
                addSparkle(sparkle)
            }
            for (name, colour, width) in [
                ("stringEdge", SKColor(red: 0.5, green: 0.1, blue: 0.14, alpha: 0.9), max(5, cell * 0.16)),
                ("string", SKColor(red: 0.92, green: 0.32, blue: 0.32, alpha: 1), max(3, cell * 0.1)),
            ] {
                let line = SKShapeNode()
                line.name = name
                line.strokeColor = colour
                line.lineWidth = width
                line.lineCap = .round
                line.lineJoin = .round
                line.zPosition = name == "string" ? 31 : 30
                stage.addChild(line)
            }
        case .knock:
            break
        }
        place()
    }

    /// The tile repeated over a rectangle (the floor, the wall).
    private func tile(_ path: String?, in rect: CGRect, tile size: CGFloat, z: CGFloat) {
        guard let path, art.has(path) else { return }
        let texture = art.texture(path)
        var y = rect.minY
        // Each tile overlaps the last by half a point (no seams); stop a point short so no extra row spills over.
        while y < rect.maxY - 1 {
            var x = rect.minX
            while x < rect.maxX - 1 {
                let node = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
                node.anchorPoint = .zero
                node.position = CGPoint(x: x, y: y)
                node.zPosition = z
                stage.addChild(node)
                x += size - 0.5
            }
            y += size - 0.5
        }
    }

    /// Soft dark corners, so the eye stays on the middle.
    private func vignette() {
        let w = 64, h = 64
        guard let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        let colours = [CGColor(red: 0.2, green: 0.1, blue: 0.08, alpha: 0), CGColor(red: 0.2, green: 0.1, blue: 0.08, alpha: 0.45)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray, locations: [0.5, 1])!
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: 32, y: 32),
            startRadius: 0,
            endCenter: CGPoint(x: 32, y: 32),
            endRadius: 46,
            options: .drawsAfterEndLocation
        )
        guard let image = context.makeImage() else { return }
        let node = SKSpriteNode(texture: SKTexture(cgImage: image), size: size)
        node.anchorPoint = .zero
        node.zPosition = 90
        stage.addChild(node)
    }

    /// The laser's dot: a glow with a hot core, drawn normally so it reads on a pale rug.
    private func makeDot() -> SKNode {
        let dot = SKShapeNode(circleOfRadius: cell * 0.34)
        dot.strokeColor = .clear
        let core = SKShapeNode(circleOfRadius: cell * 0.16)
        core.name = "core"
        core.lineWidth = 1.5
        dot.addChild(core)
        dot.name = "dot"
        dot.zPosition = 50
        paintDot(dot, golden: false)
        return dot
    }

    private func paintDot(_ dot: SKShapeNode, golden: Bool) {
        let core = dot.childNode(withName: "core") as? SKShapeNode
        if golden {
            dot.fillColor = SKColor(red: 1, green: 0.78, blue: 0.2, alpha: 0.42)
            core?.fillColor = SKColor(red: 1, green: 0.86, blue: 0.3, alpha: 1)
            core?.strokeColor = SKColor(red: 1, green: 0.98, blue: 0.82, alpha: 1)
        } else {
            dot.fillColor = SKColor(red: 1, green: 0.1, blue: 0.16, alpha: 0.3)
            core?.fillColor = SKColor(red: 1, green: 0.12, blue: 0.18, alpha: 1)
            core?.strokeColor = SKColor(red: 1, green: 0.75, blue: 0.75, alpha: 0.9)
        }
    }

    /// Knock It Off: the wall above, a mantel across it, the cat walking along the top.
    private func buildShelf() {
        tile(
            wallName,
            in: CGRect(x: -40, y: size.height * 0.28, width: size.width + 80, height: size.height * 0.72 + 40),
            tile: size.height * 0.36,
            z: -10
        )
        tile(floorName, in: CGRect(x: -40, y: -40, width: size.width + 80, height: size.height * 0.3 + 40), tile: size.height * 0.3, z: -10)
        shelfTop = size.height * 0.44
        let plankWidth = size.width * 0.9
        let plankX = (size.width - plankWidth) / 2
        cell = plankWidth / 14
        // The things stand in its middle stretch; the ends are left for the cat to turn on.
        shelfLength = plankWidth - cell * 3.4
        shelfFrom = plankX + cell * 1.7
        arena = CGRect(x: shelfFrom, y: shelfTop, width: shelfLength, height: cell * 2)
        let depth = cell * 0.62
        // Wood with the light on its top edge, a darker lip and a shadow on the wall under it.
        let shadow = SKShapeNode(rect: CGRect(x: plankX + cell * 0.2, y: shelfTop - depth - cell * 0.5, width: plankWidth - cell * 0.4, height: cell * 0.5), cornerRadius: cell * 0.2)
        shadow.fillColor = SKColor(red: 0.2, green: 0.1, blue: 0.08, alpha: 0.18)
        shadow.strokeColor = .clear
        shadow.zPosition = -3
        stage.addChild(shadow)
        let plank = SKSpriteNode(texture: woodTexture(), size: CGSize(width: plankWidth, height: depth))
        plank.anchorPoint = CGPoint(x: 0, y: 1)
        plank.position = CGPoint(x: plankX, y: shelfTop)
        plank.zPosition = -2
        stage.addChild(plank)
        // Its top, seen from a little above: the cat walks along the back of it, the things stand at the front.
        let deck = SKShapeNode(rect: CGRect(x: plankX, y: shelfTop, width: plankWidth, height: Self.deckDepth * cell), cornerRadius: cell * 0.06)
        deck.fillColor = SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1)
        deck.strokeColor = SKColor(red: 0.6, green: 0.4, blue: 0.24, alpha: 1)
        deck.lineWidth = 1.5
        deck.zPosition = -2
        stage.addChild(deck)
        for x in [plankX + cell * 1.2, plankX + plankWidth - cell * 1.2] {
            let bracket = SKShapeNode(rect: CGRect(x: x - cell * 0.18, y: shelfTop - depth - cell * 0.9, width: cell * 0.36, height: cell * 0.9), cornerRadius: cell * 0.08)
            bracket.fillColor = SKColor(red: 0.42, green: 0.26, blue: 0.15, alpha: 1)
            bracket.strokeColor = .clear
            bracket.zPosition = -2.5
            stage.addChild(bracket)
        }
        cat.setScale(cell * Tuning.MiniGames.catCells * 0.95 / Self.catUnits)
        cat.show(.side, facingRight: true)
        cat.zPosition = 0
        holder.zPosition = 4
        noseOffset = cat.bodyFrame.width * 0.36
        shownOffset = noseOffset
        if case let .knock(shelf) = game {
            for thing in shelf.things {
                addThing(thing, dropping: false)
            }
        }
    }

    /// A plank's face: warm oak, lighter along the top, with a little grain.
    private func woodTexture() -> SKTexture {
        let w = 256, h = 32
        guard let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return SKTexture() }
        let colours = [
            CGColor(red: 0.42, green: 0.25, blue: 0.14, alpha: 1), CGColor(red: 0.6, green: 0.38, blue: 0.22, alpha: 1),
            CGColor(red: 0.74, green: 0.5, blue: 0.3, alpha: 1), CGColor(red: 0.86, green: 0.64, blue: 0.42, alpha: 1),
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray, locations: [0, 0.55, 0.85, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        var grain = DaySeed(household: 3, day: GameDay(index: 0), purpose: "grain")
        context.setStrokeColor(CGColor(red: 0.32, green: 0.18, blue: 0.1, alpha: 0.22))
        for _ in 0 ..< 18 {
            let y = CGFloat(2 + grain.below(h - 8))
            context.setLineWidth(CGFloat(1 + grain.below(2)))
            context.move(to: CGPoint(x: 0, y: y))
            context.addCurve(
                to: CGPoint(x: CGFloat(w), y: y + CGFloat(grain.below(5)) - 2),
                control1: CGPoint(x: CGFloat(w) * 0.3, y: y + 2),
                control2: CGPoint(x: CGFloat(w) * 0.7, y: y - 2)
            )
            context.strokePath()
        }
        guard let image = context.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }

    private func picture(_ kind: KnockItOff.Kind) -> String {
        switch kind {
        case let .plain(index), let .golden(index):
            objectNames.isEmpty ? "fx/reactions/fx_reactions_heart.png" : objectNames[index % objectNames.count]
        case .catnip:
            catnipName
        }
    }

    /// A thing on the mantel, dropped on from above with a bounce (or already there).
    private func addThing(_ thing: KnockItOff.Thing, dropping: Bool) {
        let node = sprite(picture(thing.kind), side: cell * 1.15)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = CGPoint(x: shelfFrom + shelfLength * CGFloat(thing.at), y: shelfTop + cell * 0.04)
        node.name = "thing\(thing.id)"
        node.zPosition = 6
        switch thing.kind {
        case .golden: gild(node)
        case .catnip: glow(node, colour: SKColor(red: 0.5, green: 0.95, blue: 0.45, alpha: 1))
        case .plain: break
        }
        stage.addChild(node)
        guard dropping else { return }
        let rest = node.position
        let lift = cell * 0.1
        node.position.y += cell * 1.2
        node.alpha = 0
        let fall = SKAction.moveTo(y: rest.y, duration: 0.22)
        fall.timingMode = .easeIn
        node.run(.sequence([
            .group([fall, .fadeIn(withDuration: 0.12)]),
            .run { [weak self] in self?.puff(at: CGPoint(x: rest.x, y: rest.y + lift), count: 5) },
            .scaleX(to: 1.15, y: 0.85, duration: 0.06),
            .scale(to: 1, duration: 0.1),
        ]))
    }

    // MARK: Play

    override public func update(_ currentTime: TimeInterval) {
        // The game keeps real time when frames are slow (a busy device): the frame's time in steps of at most a
        // thirtieth of a second, a long pause cut to a quarter of one.
        let frame = min(0.25, max(0, currentTime - (lastUpdate ?? currentTime)))
        lastUpdate = currentTime
        cat.step(min(frame, 1.0 / 20))
        guard running, !finished else {
            place()
            return
        }
        let steps = max(1, Int((frame * 30).rounded(.up)))
        var beats: [PlayBeat] = []
        for _ in 0 ..< steps where !game.isOver {
            beats += advance(frame / Double(steps))
        }
        for beat in beats {
            show(beat)
            onBeat?(beat)
        }
        place()
        if game.elapsed - lastReport >= 0.1 || game.isOver || !beats.isEmpty {
            lastReport = game.elapsed
            onProgress?(progress)
        }
        if game.isOver {
            finished = true
            finger = nil
            cat.stopCycle()
            cat.moveSpeed = 0
            holder.zRotation = 0
            cat.shadowDrop = 0
            cat.settle(into: .sitThreeQuarterFront)
            onFinish?(game.score)
        }
    }

    /// The game on by `dt`: the finger (or the autoplay) passed on, new things drawn as they come; its beats.
    private func advance(_ dt: Double) -> [PlayBeat] {
        var beats: [PlayBeat] = []
        switch game {
        case var .laser(laser):
            let wasShowing = laser.catnip.showing(laser.elapsed)
            let dot = autoplay ? MiniGameBot.laser(laser) : finger.map(gamePoint)
            beats = laser.step(dt, dot: dot)
            game = .laser(laser)
            if laser.catnip.showing(laser.elapsed), !wasShowing {
                showCatnip(at: point(laser.catnip.at))
            } else if !laser.catnip.showing(laser.elapsed), wasShowing, !laser.catnip.taken {
                stage.childNode(withName: "catnip")?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            }
        case var .knock(shelf):
            let before = Set(shelf.things.map(\.id))
            beats = shelf.step(dt)
            if autoplay, MiniGameBot.knock(shelf) {
                let taps = shelf.tap()
                beats += taps
                game = .knock(shelf)
                swipe(taps)
            }
            game = .knock(shelf)
            for thing in shelf.things where !before.contains(thing.id) {
                addThing(thing, dropping: true)
            }
        case var .string(chase):
            if autoplay, let path = MiniGameBot.string(chase) {
                chase.draw(path)
            }
            let before = chase.sparkles
            beats = chase.step(dt)
            game = .string(chase)
            sparkles(before: before, now: chase, beats: beats)
        }
        return beats
    }

    private var progress: Progress {
        var p = Progress(elapsed: game.elapsed, duration: game.duration, score: game.score)
        p.combo = game.combo.count
        p.multiplier = game.combo.count > 0 ? game.combo.multiplier : 1
        p.bestCombo = game.combo.best
        p.zoomies = game.hasZoomies
        if case let .laser(laser) = game {
            p.golden = laser.isGolden
        }
        return p
    }

    // MARK: Placing the pieces

    private func point(_ p: GamePoint) -> CGPoint {
        CGPoint(x: arena.minX + CGFloat(p.x) * cell, y: arena.minY + CGFloat(p.y) * cell)
    }

    private func gamePoint(_ p: CGPoint) -> GamePoint {
        GamePoint(x: Double((p.x - arena.minX) / cell), y: Double((p.y - arena.minY) / cell))
    }

    /// Where a beat happened, on screen.
    private func screen(_ p: GamePoint) -> CGPoint {
        if case .knock = game {
            return CGPoint(x: shelfFrom + shelfLength * CGFloat(p.x), y: shelfTop + cell * 0.5)
        }
        return point(p)
    }

    /// Everything where the game says it is.
    private func place() {
        switch game {
        case let .laser(laser):
            placeLaser(laser)
        case let .knock(shelf):
            placeShelfCat(shelf)
        case let .string(chase):
            let speed = chase.string.isEmpty ? 0 : chase.currentSpeed
            let next = chase.string.first ?? chase.cat
            let gap = max(0.001, next.distance(to: chase.cat))
            let heading = GamePoint(x: (next.x - chase.cat.x) / gap * speed, y: (next.y - chase.cat.y) / gap * speed)
            move(to: chase.cat, velocity: heading)
            let path = CGMutablePath()
            if !chase.string.isEmpty {
                path.move(to: point(chase.cat))
                for p in chase.string {
                    path.addLine(to: point(p))
                }
            }
            for name in ["stringEdge", "string"] {
                (stage.childNode(withName: name) as? SKShapeNode)?.path = path
            }
            for sparkle in chase.sparkles {
                guard let node = stage.childNode(withName: "sparkle\(sparkle.id)") else { continue }
                // Blinks as it fades: its last third.
                let left = sparkle.left(at: chase.elapsed)
                let blink = left < 0.33 ? (sin(chase.elapsed * 22) > 0 ? 1.0 : 0.35) : 1.0
                node.alpha = CGFloat(min(1, left * 3 + 0.2) * blink)
            }
        }
    }

    private func placeLaser(_ laser: LaserChase) {
        if let dot = stage.childNode(withName: "dot") as? SKShapeNode {
            dot.position = point(laser.dot)
            dot.alpha = finger == nil && !autoplay ? 0.55 : 1
            if laser.isGolden != dotGolden {
                dotGolden = laser.isGolden
                paintDot(dot, golden: dotGolden)
                dot.removeAction(forKey: "pulse")
                if dotGolden {
                    dot.run(.repeatForever(.sequence([.scale(to: 1.35, duration: 0.25), .scale(to: 1, duration: 0.25)])), withKey: "pulse")
                } else {
                    dot.setScale(1)
                }
            }
            if dotGolden, Int(laser.elapsed * 30) % 3 == 0 {
                trail(at: dot.position, colour: SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
            }
        }
        if laser.hasZoomies, Int(laser.elapsed * 30) % 2 == 0 {
            trail(at: CGPoint(x: holder.position.x, y: holder.position.y + cell * 0.4), colour: SKColor(red: 0.55, green: 1, blue: 0.5, alpha: 1))
        }
        switch laser.phase {
        case .chasing:
            holder.zRotation = 0
            cat.shadowDrop = 0
            move(to: laser.cat, velocity: laser.velocity)
        case .crouching:
            // Down low, the back end wiggling, eyes on the dot.
            holder.position = point(laser.cat)
            holder.zRotation = CGFloat(sin(laser.phaseTime * 70)) * 0.03
            face(laser.dot.x - laser.cat.x)
        case .leaping:
            let u = CGFloat(min(1, laser.phaseTime / Tuning.MiniGames.leapSeconds))
            let height = cell * 0.9 * 4 * u * (1 - u)
            let ground = point(laser.cat)
            holder.position = CGPoint(x: ground.x, y: ground.y + height)
            cat.shadowDrop = height / max(cat.yScale, 0.001)
            // Nose up rising, down falling.
            let lean = (0.5 - u) * 0.5
            holder.zRotation = cat.facingRight ? lean : -lean
            holder.zPosition = 10 - CGFloat(laser.cat.y) * 0.1
        case .landed:
            holder.zRotation = 0
            cat.shadowDrop = 0
            holder.position = point(laser.cat)
        }
    }

    /// Knock It Off: the cat along the mantel, its nose where the game's paw is, turning at the ends.
    private func placeShelfCat(_ shelf: KnockItOff) {
        let right = shelf.direction > 0
        if right != cat.facingRight {
            turnAround(right)
        }
        // The nose leads; through a turn its middle slides across.
        let target = right ? noseOffset : -noseOffset
        shownOffset += (target - shownOffset) * 0.25
        let x = shelfFrom + shelfLength * CGFloat(shelf.paw) - shownOffset
        holder.position = CGPoint(x: x, y: shelfTop + Self.deckDepth * cell * 0.8)
        let moving = running && !finished && shelf.resting == 0
        if moving != walking {
            walking = moving
            if moving {
                cat.walk()
            } else {
                cat.stopCycle()
            }
        }
        cat.moveSpeed = moving ? CGFloat(shelf.pace) * shelfLength / max(cat.xScale, 0.001) : 0
        cat.moveDirection = CGVector(dx: right ? 1 : -1, dy: 0)
        if shelf.hasZoomies, Int(shelf.elapsed * 30) % 2 == 0 {
            trail(at: CGPoint(x: x + shownOffset, y: shelfTop + cell * 0.5), colour: SKColor(red: 0.55, green: 1, blue: 0.5, alpha: 1))
        }
    }

    /// A turn on the spot: squashed across for a moment as it comes round.
    private func turnAround(_ right: Bool) {
        cat.show(.side, facingRight: right)
        holder.removeAction(forKey: "turn")
        holder.xScale = 0.3
        let back = SKAction.scaleX(to: 1, duration: 0.16)
        back.timingMode = .easeOut
        holder.run(back, withKey: "turn")
    }

    private func face(_ dx: Double) {
        guard abs(dx) > 0.2 else { return }
        let right = dx > 0
        if right != cat.facingRight {
            cat.show(.side, facingRight: right)
        }
    }

    /// The cat to its place on the floor, walking, running or sitting by how fast it goes.
    private func move(to p: GamePoint, velocity: GamePoint) {
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        holder.position = point(p)
        holder.zPosition = 10 - CGFloat(p.y) * 0.1
        if speed > 0.3 {
            stoppedFor = 0
            let right = velocity.x >= 0
            if gait == .sitting {
                cat.rise(to: .side, facingRight: right)
            } else if right != cat.facingRight, abs(velocity.x) > 0.25 {
                cat.show(.side, facingRight: right)
            }
            let wanted: Gait = speed > 2 ? .running : .walking
            if wanted != gait {
                gait = wanted
                wanted == .running ? cat.run() : cat.walk()
            }
            cat.moveSpeed = CGFloat(speed) * cell / max(cat.xScale, 0.001)
        } else if gait != .sitting {
            stoppedFor += 1.0 / 60
            if stoppedFor > 0.35 {
                gait = .sitting
                cat.stopCycle()
                cat.moveSpeed = 0
                cat.settle(into: .sitThreeQuarterFront)
            }
        }
    }

    // MARK: Beats

    /// Each beat drawn: the burst and the points for a hit, a puff for a miss, the cat's reaction.
    private func show(_ beat: PlayBeat) {
        switch beat {
        case let .scored(hit):
            let at = screen(hit.at)
            let gold = SKColor(red: 1, green: 0.82, blue: 0.25, alpha: 1)
            let colour = hit.golden ? gold : hit.zoomies ? SKColor(red: 0.55, green: 1, blue: 0.5, alpha: 1) : SKColor.white
            burst(at: at, colour: colour, count: 8 + min(hit.points, 24), speed: cell * (hit.golden ? 4.5 : 3))
            floatText("+\(hit.points)", at: CGPoint(x: at.x, y: at.y + cell * 0.6), colour: hit.golden ? gold : .white, size: cell * (0.62 + min(0.5, CGFloat(hit.points) * 0.02)))
            if hit.perfect {
                floatText("Perfect!", at: CGPoint(x: at.x, y: at.y + cell * 1.3), colour: SKColor(red: 1, green: 0.93, blue: 0.75, alpha: 1), size: cell * 0.38)
            }
            if hit.golden {
                shake(cell * 0.18)
                react("exclaim")
            } else if hit.points >= 8 {
                shake(cell * 0.1)
            } else {
                shake(cell * 0.04)
            }
            if hit.combo > 0, hit.combo % 6 == 0 {
                react("heart")
            }
            if case .knock = game {
                knockOff(at: hit.at)
            } else if case .laser = game {
                cat.squash(CGFloat(Tuning.Puppet.squash) * 1.6)
            }
        case let .missed(at, lost):
            let spot = screen(at)
            puff(at: spot, count: 7)
            if lost {
                react("question")
            }
            if case .laser = game {
                cat.squash(CGFloat(Tuning.Puppet.squash) * 1.2)
                floatText("Whoosh", at: CGPoint(x: spot.x, y: spot.y + cell * 0.7), colour: SKColor(white: 1, alpha: 0.85), size: cell * 0.32)
            }
        case .comboLapsed:
            break
        case let .zoomies(at):
            let spot = screen(at)
            leaves(at: spot)
            banner("Zoomies!", colour: SKColor(red: 0.55, green: 1, blue: 0.5, alpha: 1))
            react("notes")
            shake(cell * 0.12)
            if case .laser = game {
                stage.childNode(withName: "catnip")?.run(.sequence([.group([.scale(to: 1.6, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
            }
        case .zoomiesOver:
            break
        case .crouched:
            cat.stopCycle()
            cat.moveSpeed = 0
            gait = .still
            cat.squash(CGFloat(Tuning.Puppet.squash) * 2.2)
        case let .sprang(to):
            if let laser = laserGame {
                face(to.x - laser.cat.x)
            }
        case .goldenAppeared:
            banner("Golden dot!", colour: SKColor(red: 1, green: 0.82, blue: 0.25, alpha: 1))
            if let dot = stage.childNode(withName: "dot") {
                burst(at: dot.position, colour: SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), count: 18, speed: cell * 3)
            }
        }
    }

    private var laserGame: LaserChase? {
        if case let .laser(laser) = game { laser } else { nil }
    }

    /// Knock It Off: the swipe a tap makes (a streak of the paw in front of the nose, the cat lunging into it).
    private func swipe(_ beats: [PlayBeat]) {
        guard !beats.isEmpty else { return }
        let right = cat.facingRight
        let nose = CGPoint(x: holder.position.x + shownOffset, y: shelfTop + cell * 0.55)
        let arc = SKShapeNode()
        let path = CGMutablePath()
        let dir: CGFloat = right ? 1 : -1
        path.addArc(center: CGPoint(x: nose.x - dir * cell * 0.1, y: nose.y), radius: cell * 0.55, startAngle: right ? 1.3 : .pi - 1.3, endAngle: right ? -0.6 : .pi + 0.6, clockwise: right)
        arc.path = path
        arc.strokeColor = SKColor(white: 1, alpha: 0.85)
        arc.lineWidth = cell * 0.09
        arc.lineCap = .round
        arc.zPosition = 7
        fx.addChild(arc)
        arc.run(.sequence([.group([.fadeOut(withDuration: 0.18), .scale(to: 1.1, duration: 0.18)]), .removeFromParent()]))
        cat.squash(CGFloat(Tuning.Puppet.squash) * 1.4)
        cat.removeAction(forKey: "lunge")
        cat.run(.sequence([.moveBy(x: dir * cell * 0.18, y: 0, duration: 0.05), .moveTo(x: 0, duration: 0.12)]), withKey: "lunge")
    }

    /// Knock It Off: the thing at `at` goes over the edge, tumbling to the floor, bouncing once and fading.
    private func knockOff(at: GamePoint) {
        let x = shelfFrom + shelfLength * CGFloat(at.x)
        guard let node = stage.children.first(where: { ($0.name?.hasPrefix("thing") ?? false) && abs($0.position.x - x) < 1 }) else { return }
        node.name = "falling"
        node.removeAllActions()
        let dir: CGFloat = cat.facingRight ? 1 : -1
        let floor = size.height * CGFloat.random(in: 0.08 ... 0.18)
        let spin = CGFloat.random(in: 2.5 ... 4.5) * -dir
        let up = SKAction.moveBy(x: dir * cell * 0.4, y: cell * 0.5, duration: 0.12)
        up.timingMode = .easeOut
        let down = SKAction.moveTo(y: floor, duration: 0.42)
        down.timingMode = .easeIn
        node.zPosition = 60
        node.run(.sequence([
            .group([up, .rotate(byAngle: spin * 0.2, duration: 0.12)]),
            .group([down, .moveBy(x: dir * cell * 1.1, y: 0, duration: 0.42), .rotate(byAngle: spin, duration: 0.42), .scale(to: 1.25, duration: 0.42)]),
            .run { [weak self] in self?.puff(at: CGPoint(x: node.position.x, y: floor), count: 6) },
            .group([.moveBy(x: dir * cell * 0.3, y: cell * 0.3, duration: 0.12), .rotate(byAngle: spin * 0.15, duration: 0.12)]),
            .moveTo(y: floor, duration: 0.12),
            .wait(forDuration: 0.6),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
    }

    /// String Chase: sparkles that came pop in; those collected burst (the beat draws that), those that faded go.
    private func sparkles(before: [StringChase.Sparkle], now chase: StringChase, beats: [PlayBeat]) {
        let live = Set(chase.sparkles.map(\.id))
        for sparkle in before where !live.contains(sparkle.id) {
            guard let node = stage.childNode(withName: "sparkle\(sparkle.id)") else { continue }
            node.name = nil
            let taken = chase.cat.distance(to: sparkle.at) <= Tuning.MiniGames.sparkleReach + 0.05
            node.removeAllActions()
            if taken {
                node.run(.sequence([.group([.scale(to: 2.2, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
            } else {
                node.run(.sequence([.group([.scale(to: 0.3, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
            }
        }
        let known = Set(before.map(\.id))
        for sparkle in chase.sparkles where !known.contains(sparkle.id) {
            addSparkle(sparkle)
        }
    }

    private func addSparkle(_ sparkle: StringChase.Sparkle) {
        let node: SKSpriteNode
        switch sparkle.kind {
        case .plain:
            node = sprite("fx/reactions/fx_reactions_sparkle.png", side: cell * 0.95)
        case .golden:
            node = sprite("fx/reactions/fx_reactions_sparkle.png", side: cell * 1.3)
            gild(node)
        case .catnip:
            node = sprite(catnipName, side: cell * 1.1)
            glow(node, colour: SKColor(red: 0.5, green: 0.95, blue: 0.45, alpha: 1))
        }
        node.position = point(sparkle.at)
        node.name = "sparkle\(sparkle.id)"
        node.zPosition = 40
        node.setScale(0.1)
        let pop = SKAction.sequence([.scale(to: 1.2, duration: 0.14), .scale(to: 1, duration: 0.1)])
        let breathe = SKAction.repeatForever(.sequence([.scale(to: 1.12, duration: 0.5), .scale(to: 0.92, duration: 0.5)]))
        node.run(.sequence([pop, breathe]))
        stage.addChild(node)
    }

    /// Laser Pointer: the catnip fish lying on the rug, glowing and rocking a little.
    private func showCatnip(at spot: CGPoint) {
        stage.childNode(withName: "catnip")?.removeFromParent()
        let node = sprite(catnipName, side: cell * 1.2)
        node.name = "catnip"
        node.position = spot
        node.zPosition = 35
        glow(node, colour: SKColor(red: 0.5, green: 0.95, blue: 0.45, alpha: 1))
        node.setScale(0.1)
        node.run(.sequence([
            .scale(to: 1, duration: 0.2),
            .repeatForever(.sequence([.rotate(toAngle: 0.12, duration: 0.4), .rotate(toAngle: -0.12, duration: 0.4)])),
        ]))
        stage.addChild(node)
    }

    // MARK: Juice

    /// A picture fitted into a square of `side`.
    private func sprite(_ path: String, side: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: art.texture(path))
        let texture = node.texture?.size() ?? CGSize(width: 1, height: 1)
        node.size = texture.width > texture.height
            ? CGSize(width: side, height: side * texture.height / max(texture.width, 1))
            : CGSize(width: side * texture.width / max(texture.height, 1), height: side)
        return node
    }

    /// Golden: warmed towards gold, a glow behind and a glint now and then.
    private func gild(_ node: SKSpriteNode) {
        node.color = SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        node.colorBlendFactor = 0.55
        glow(node, colour: SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
        node.run(.repeatForever(.sequence([
            .wait(forDuration: 0.45),
            .run { [weak self, weak node] in
                guard let self, let node, let parent = node.parent else { return }
                let spot = parent.convert(node.position, to: self.fx)
                self.burst(at: CGPoint(x: spot.x + CGFloat.random(in: -0.4 ... 0.4) * node.size.width, y: spot.y + node.size.height * 0.5), colour: SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1), count: 2, speed: self.cell * 0.6)
            },
        ])), withKey: "glint")
    }

    /// A soft glow of `colour` behind a sprite, breathing.
    private func glow(_ node: SKSpriteNode, colour: SKColor) {
        let halo = SKSpriteNode(texture: Self.softDot, size: CGSize(width: node.size.width * 1.9, height: node.size.width * 1.9))
        halo.color = colour
        halo.colorBlendFactor = 1
        halo.alpha = 0.55
        halo.blendMode = .add
        halo.zPosition = -0.5
        halo.position = CGPoint(x: 0, y: node.anchorPoint.y > 0 ? node.size.height * 0.5 : 0)
        halo.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.6), .fadeAlpha(to: 0.6, duration: 0.6)])))
        node.addChild(halo)
    }

    /// A round soft dot, white, for glows and particles.
    private static let softDot: SKTexture = {
        let w = 64
        guard let context = CGContext(
            data: nil, width: w, height: w, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return SKTexture() }
        let colours = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        return context.makeImage().map { SKTexture(cgImage: $0) } ?? SKTexture()
    }()

    /// A one-off burst of particles flying out from a point.
    private func burst(at spot: CGPoint, colour: SKColor, count: Int, speed: CGFloat) {
        let e = SKEmitterNode()
        e.particleTexture = art.has("fx/reactions/fx_reactions_sparkle.png") && count > 4
            ? art.texture("fx/reactions/fx_reactions_sparkle.png") : Self.softDot
        e.numParticlesToEmit = count
        e.particleBirthRate = 600
        e.particleLifetime = 0.55
        e.particleLifetimeRange = 0.25
        e.emissionAngleRange = .pi * 2
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.6
        e.yAcceleration = -speed * 1.5
        e.particleAlpha = 1
        e.particleAlphaSpeed = -1.8
        e.particleScale = cell * 0.32 / 128
        e.particleScaleRange = cell * 0.18 / 128
        e.particleScaleSpeed = -cell * 0.3 / 128
        e.particleRotationRange = .pi
        e.particleRotationSpeed = 3
        e.particleColor = colour
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .alpha
        e.position = spot
        e.zPosition = 2
        fx.addChild(e)
        e.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
    }

    /// A small trail of glowing dots behind something moving (the golden dot, a cat with the zoomies).
    private func trail(at spot: CGPoint, colour: SKColor) {
        let dot = SKSpriteNode(texture: Self.softDot, size: CGSize(width: cell * 0.36, height: cell * 0.36))
        dot.color = colour
        dot.colorBlendFactor = 1
        dot.blendMode = .add
        dot.position = CGPoint(x: spot.x + CGFloat.random(in: -0.15 ... 0.15) * cell, y: spot.y + CGFloat.random(in: -0.15 ... 0.15) * cell)
        dot.zPosition = 1
        fx.addChild(dot)
        dot.run(.sequence([.group([.fadeOut(withDuration: 0.45), .scale(to: 0.2, duration: 0.45)]), .removeFromParent()]))
    }

    /// A puff of dust (a landing, a swipe at nothing, something hitting the floor).
    private func puff(at spot: CGPoint, count: Int) {
        for _ in 0 ..< count {
            let dot = SKSpriteNode(texture: Self.softDot, size: CGSize(width: cell * 0.4, height: cell * 0.4))
            dot.color = SKColor(red: 0.96, green: 0.92, blue: 0.85, alpha: 1)
            dot.colorBlendFactor = 1
            dot.alpha = 0.7
            dot.position = spot
            dot.zPosition = 1
            fx.addChild(dot)
            let angle = CGFloat.random(in: 0.2 ... .pi - 0.2)
            let reach = cell * CGFloat.random(in: 0.4 ... 0.9)
            let out = SKAction.moveBy(x: cos(angle) * reach, y: sin(angle) * reach * 0.5, duration: 0.35)
            out.timingMode = .easeOut
            dot.run(.sequence([.group([out, .fadeOut(withDuration: 0.35), .scale(to: 1.8, duration: 0.35)]), .removeFromParent()]))
        }
    }

    /// The catnip's leaves flying up (the painted leaf, tinted green).
    private func leaves(at spot: CGPoint) {
        let path = "world/weather/leaf.png"
        for i in 0 ..< 10 {
            let leaf = art.has(path) ? sprite(path, side: cell * 0.45) : SKSpriteNode(texture: Self.softDot, size: CGSize(width: cell * 0.3, height: cell * 0.3))
            leaf.color = SKColor(red: 0.35, green: 0.75, blue: 0.3, alpha: 1)
            leaf.colorBlendFactor = 0.7
            leaf.position = spot
            leaf.zPosition = 3
            fx.addChild(leaf)
            let angle = CGFloat(i) / 10 * .pi * 2
            let reach = cell * CGFloat.random(in: 1 ... 1.8)
            let out = SKAction.moveBy(x: cos(angle) * reach, y: sin(angle) * reach + cell * 0.6, duration: 0.7)
            out.timingMode = .easeOut
            leaf.run(.sequence([.group([out, .rotate(byAngle: CGFloat.random(in: -4 ... 4), duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
        }
    }

    /// The whole room jolts and settles.
    private func shake(_ amount: CGFloat) {
        stage.removeAction(forKey: "shake")
        stage.position = .zero
        var steps: [SKAction] = []
        var a = amount
        for _ in 0 ..< 5 {
            steps.append(.moveTo(x: CGFloat.random(in: -a ... a), duration: 0.025))
            steps.append(.moveTo(y: CGFloat.random(in: -a ... a), duration: 0.025))
            a *= 0.65
        }
        steps.append(.move(to: .zero, duration: 0.04))
        stage.run(.sequence(steps), withKey: "shake")
    }

    /// A reaction icon (heart, exclaim, notes, question) pops up over the cat and floats away.
    private func react(_ icon: String) {
        let path = "fx/reactions/fx_reactions_\(icon).png"
        guard art.has(path) else { return }
        let node = sprite(path, side: cell * 0.8)
        // The cat's frame is in the holder's space.
        let top = cat.bodyFrame.maxY
        node.position = CGPoint(x: holder.position.x, y: holder.position.y + (top.isFinite ? top : cell * 2) + cell * 0.2)
        node.zPosition = 5
        node.setScale(0.3)
        fx.addChild(node)
        let up = SKAction.moveBy(x: 0, y: cell * 0.9, duration: 0.9)
        up.timingMode = .easeOut
        node.run(.sequence([
            .scale(to: 1.15, duration: 0.14),
            .scale(to: 1, duration: 0.08),
            .group([up, .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent(),
        ]))
    }

    /// Points or a word floating up from where they were won.
    private func floatText(_ text: String, at spot: CGPoint, colour: SKColor, size points: CGFloat) {
        let label = SKLabelNode()
        label.attributedText = Self.lettering(text, size: points, colour: colour)
        label.position = spot
        label.verticalAlignmentMode = .center
        label.zPosition = 10
        label.setScale(0.4)
        fx.addChild(label)
        let up = SKAction.moveBy(x: 0, y: cell * 0.9, duration: 0.8)
        up.timingMode = .easeOut
        label.run(.sequence([
            .scale(to: 1.15, duration: 0.12),
            .scale(to: 1, duration: 0.08),
            .group([up, .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.35)])]),
            .removeFromParent(),
        ]))
    }

    /// A word across the top of the room (golden dot, zoomies).
    private func banner(_ text: String, colour: SKColor) {
        fx.childNode(withName: "banner")?.removeFromParent()
        let label = SKLabelNode()
        label.name = "banner"
        label.attributedText = Self.lettering(text, size: min(size.height * 0.09, 64), colour: colour)
        label.position = CGPoint(x: size.width / 2, y: size.height * (1 - Tuning.MiniGames.hudShare) - size.height * 0.08)
        label.verticalAlignmentMode = .center
        label.zPosition = 20
        label.setScale(0.2)
        fx.addChild(label)
        label.run(.sequence([
            .scale(to: 1.12, duration: 0.16),
            .scale(to: 1, duration: 0.1),
            .wait(forDuration: 0.9),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: size.height * 0.03, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// Rounded heavy lettering with a dark outline, so it reads on the rug and the wallpaper.
    private static func lettering(_ text: String, size: CGFloat, colour: SKColor) -> NSAttributedString {
        #if canImport(UIKit)
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        #else
            let base = NSFont.systemFont(ofSize: size, weight: .heavy)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        #endif
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: colour,
            .strokeColor: SKColor(red: 0.22, green: 0.1, blue: 0.07, alpha: 1),
            .strokeWidth: -5,
        ])
    }

    #if canImport(UIKit)
        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            switch game {
            case .laser:
                finger = location
            case var .knock(shelf):
                guard running, !finished else { return }
                let beats = shelf.tap()
                game = .knock(shelf)
                swipe(beats)
                for beat in beats {
                    show(beat)
                    onBeat?(beat)
                }
                onProgress?(progress)
            case var .string(chase):
                guard running, !finished else { return }
                chase.draw([gamePoint(location)])
                game = .string(chase)
            }
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            switch game {
            case .laser:
                finger = location
            case var .string(chase):
                guard running, !finished else { return }
                if let last = chase.string.last, last.distance(to: gamePoint(location)) < 0.2 {
                    return
                }
                chase.extend(gamePoint(location))
                game = .string(chase)
            case .knock:
                break
            }
        }

        override public func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
            if case .laser = game {
                finger = nil
            }
        }
    #endif
}
