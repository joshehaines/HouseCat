import HouseCatCore
import SpriteKit

/// The three mini-games (SPEC "Mini-games", CONTENT.md §6), drawn with the player's own cat on the living room's
/// own floor: the dot to chase, the shelf to clear, the string to follow. HouseCatCore's game models keep the
/// score; this scene only moves the pieces and passes the finger on. The app shows the clock and the stars.
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
    }

    /// What the app hears: the clock and the score as they change, a moment worth a sound, the end.
    public struct Progress: Equatable, Sendable {
        public var elapsed: Double
        public var duration: Double
        public var score: Double

        public init(elapsed: Double, duration: Double, score: Double) {
            self.elapsed = elapsed
            self.duration = duration
            self.score = score
        }
    }

    public enum Moment: Sendable {
        case hit
        case miss
        case sparkle
    }

    public var onProgress: ((Progress) -> Void)?
    public var onMoment: ((Moment) -> Void)?
    public var onFinish: ((Double) -> Void)?
    /// Debug screenshot runs: the game plays itself (the dot in a loop, taps on time, a string through the sparkles).
    public var autoplay = false
    public private(set) var game: Game

    private let art: ArtLibrary
    private let cat: CatNode
    private let stage = SKNode()
    private var running = false
    private var finished = false
    private var lastUpdate: TimeInterval?
    private var lastReport = -1.0
    private var lastAutoTap: TimeInterval = 0
    private var finger: CGPoint?
    /// The cat's gait, kept so it changes only when it must.
    private var gait: Gait = .sitting
    private var facingRight = true
    private var stoppedFor = 0.0
    private var arena = CGRect.zero
    private var cell: CGFloat = 40
    private let floorName: String?
    private let wallName: String?
    private let objectNames: [String]

    private static let catUnits: CGFloat = 100

    private enum Gait {
        case sitting, walking, running
    }

    /// `floor` and `wall` are the living room's tiles (art paths); `objects` the five things on the shelf.
    public init(
        size: CGSize,
        game: Game,
        art: ArtLibrary,
        catArt: CatArt,
        rig: PuppetRig,
        look: CatLook,
        floor: String?,
        wall: String?,
        objects: [String]
    ) {
        self.game = game
        self.art = art
        floorName = floor
        wallName = wall
        objectNames = objects
        // Drawn a fixed height and scaled to the floor's cells.
        cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: Self.catUnits)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.86, green: 0.74, blue: 0.6, alpha: 1)
        cat.name = "cat"
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
        cat.removeFromParent()
        stage.addChild(cat)
        let top = size.height * Tuning.MiniGames.hudShare
        if case .knock = game {
            buildShelf()
        } else {
            let available = CGRect(x: size.width * 0.06, y: size.height * 0.06, width: size.width * 0.88, height: size.height * 0.94 - top)
            cell = min(available.width / Tuning.MiniGames.arenaWidth, available.height / Tuning.MiniGames.arenaHeight)
            let width = cell * Tuning.MiniGames.arenaWidth, height = cell * Tuning.MiniGames.arenaHeight
            arena = CGRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height)
            tile(floorName, in: CGRect(origin: .zero, size: size), tile: size.height * 0.42, z: -10)
            let rug = SKSpriteNode(texture: art.texture("furniture/living/furn_living_rug_R.png"))
            let rugWidth = arena.width * 1.08
            rug.size = CGSize(width: rugWidth, height: rugWidth * rug.texture!.size().height / max(1, rug.texture!.size().width))
            rug.position = CGPoint(x: arena.midX, y: arena.midY)
            rug.zPosition = -9
            stage.addChild(rug)
            cat.setScale(cell * Tuning.MiniGames.catCells / Self.catUnits)
            cat.show(.side, facingRight: facingRight)
        }
        vignette()
        switch game {
        case let .laser(laser):
            // A red glow with a hot core, drawn normally so it reads on a pale rug.
            let dot = SKShapeNode(circleOfRadius: cell * 0.34)
            dot.fillColor = SKColor(red: 1, green: 0.1, blue: 0.16, alpha: 0.3)
            dot.strokeColor = .clear
            let core = SKShapeNode(circleOfRadius: cell * 0.16)
            core.fillColor = SKColor(red: 1, green: 0.12, blue: 0.18, alpha: 1)
            core.strokeColor = SKColor(red: 1, green: 0.75, blue: 0.75, alpha: 0.9)
            core.lineWidth = 1.5
            dot.addChild(core)
            dot.name = "dot"
            dot.zPosition = 50
            dot.position = point(laser.dot)
            stage.addChild(dot)
        case let .string(chase):
            for (index, sparkle) in chase.sparkles.enumerated() where !chase.collected[index] {
                let node = SKSpriteNode(texture: art.texture("fx/reactions/fx_reactions_sparkle.png"))
                node.size = CGSize(width: cell * 0.9, height: cell * 0.9)
                node.position = point(sparkle)
                node.name = "sparkle\(index)"
                node.zPosition = 40
                node.run(.repeatForever(.sequence([
                    .group([.scale(to: 1.15, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)]),
                    .group([.scale(to: 0.9, duration: 0.6), .fadeAlpha(to: 0.75, duration: 0.6)]),
                ])))
                stage.addChild(node)
            }
            let line = SKShapeNode()
            line.name = "string"
            line.strokeColor = SKColor(red: 0.85, green: 0.22, blue: 0.24, alpha: 1)
            line.lineWidth = max(3, cell * 0.08)
            line.lineCap = .round
            line.lineJoin = .round
            line.zPosition = 30
            stage.addChild(line)
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

    /// Knock It Off: the wall above, a shelf across it with its five things, the cat at the end, its paw.
    private func buildShelf() {
        tile(
            wallName,
            in: CGRect(x: 0, y: size.height * 0.28, width: size.width, height: size.height * 0.72),
            tile: size.height * 0.36,
            z: -10
        )
        tile(floorName, in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.3), tile: size.height * 0.3, z: -10)
        let shelfY = size.height * 0.42
        let shelfWidth = size.width * 0.62
        let shelfX = size.width * 0.12
        arena = CGRect(x: shelfX, y: shelfY, width: shelfWidth, height: size.height * 0.2)
        cell = shelfWidth / 12
        let plank = SKShapeNode(
            rect: CGRect(x: shelfX - cell * 0.4, y: shelfY - cell * 0.5, width: shelfWidth + cell * 2.6, height: cell * 0.5),
            cornerRadius: cell * 0.08
        )
        plank.fillColor = SKColor(red: 0.62, green: 0.4, blue: 0.24, alpha: 1)
        plank.strokeColor = SKColor(red: 0.4, green: 0.24, blue: 0.14, alpha: 1)
        plank.lineWidth = 2
        plank.zPosition = -2
        stage.addChild(plank)
        let lip = SKShapeNode(
            rect: CGRect(x: shelfX - cell * 0.4, y: shelfY - cell * 0.62, width: shelfWidth + cell * 2.6, height: cell * 0.14),
            cornerRadius: cell * 0.05
        )
        lip.fillColor = SKColor(red: 0.42, green: 0.26, blue: 0.15, alpha: 1)
        lip.strokeColor = .clear
        lip.zPosition = -2
        stage.addChild(lip)
        if case let .knock(shelf) = game {
            for (index, object) in shelf.objects.enumerated() where object.there {
                let path = objectNames.isEmpty ? "fx/reactions/fx_reactions_heart.png" : objectNames[index % objectNames.count]
                let node = SKSpriteNode(texture: art.texture(path))
                let side = cell * 1.25
                let texture = node.texture!.size()
                node.size = texture.width > texture.height
                    ? CGSize(width: side, height: side * texture.height / texture.width)
                    : CGSize(width: side * texture.width / texture.height, height: side)
                node.anchorPoint = CGPoint(x: 0.5, y: 0)
                node.position = CGPoint(x: shelfX + shelfWidth * object.at, y: shelfY)
                node.name = "object\(index)"
                node.zPosition = 5
                stage.addChild(node)
            }
        }
        // The cat sits on the end of the shelf, facing along it; its paw sweeps above the things.
        cat.setScale(cell * Tuning.MiniGames.catCells * 1.2 / Self.catUnits)
        cat.position = CGPoint(x: shelfX + shelfWidth + cell * 1.3, y: shelfY)
        cat.show(.side, facingRight: false)
        cat.settle(into: .sitSide, duration: 0)
        cat.zPosition = 4
        // The game moves the holder; the paw bobs inside it.
        let holder = SKNode()
        holder.name = "paw"
        holder.zPosition = 20
        let paw = SKSpriteNode(texture: art.texture("fx/reactions/fx_reactions_paw.png"))
        paw.size = CGSize(width: cell * 1.1, height: cell * 1.1)
        paw.run(.repeatForever(.sequence([.moveBy(x: 0, y: cell * 0.12, duration: 0.25), .moveBy(x: 0, y: -cell * 0.12, duration: 0.25)])))
        holder.addChild(paw)
        stage.addChild(holder)
    }

    private func point(_ p: GamePoint) -> CGPoint {
        CGPoint(x: arena.minX + CGFloat(p.x) * cell, y: arena.minY + CGFloat(p.y) * cell)
    }

    private func gamePoint(_ p: CGPoint) -> GamePoint {
        GamePoint(x: Double((p.x - arena.minX) / cell), y: Double((p.y - arena.minY) / cell))
    }

    // MARK: Play

    override public func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 20, currentTime - (lastUpdate ?? currentTime))
        lastUpdate = currentTime
        cat.step(dt)
        guard running, !finished else { return }
        if autoplay {
            play(at: currentTime)
        }
        switch game {
        case var .laser(laser):
            laser.step(dt, dot: finger.map(gamePoint))
            game = .laser(laser)
        case var .knock(shelf):
            shelf.step(dt)
            game = .knock(shelf)
        case var .string(chase):
            let before = chase.collected
            chase.step(dt)
            game = .string(chase)
            for index in chase.collected.indices where chase.collected[index] && !before[index] {
                collect(index)
            }
        }
        place()
        if game.elapsed - lastReport >= 0.1 || game.isOver {
            lastReport = game.elapsed
            onProgress?(Progress(elapsed: game.elapsed, duration: game.duration, score: game.score))
        }
        if game.isOver {
            finished = true
            cat.stopCycle()
            cat.settle(into: .sitThreeQuarterFront)
            onFinish?(game.score)
        }
    }

    /// The game playing itself, as the tests play it.
    private func play(at time: TimeInterval) {
        switch game {
        case .laser:
            let t = game.elapsed
            finger = point(GamePoint(x: 6 + 3 * cos(t * 0.7), y: 3 + 1.6 * sin(t * 0.7)))
        case var .knock(shelf):
            // A hit about every second and a half, as a person would.
            guard time - lastAutoTap > 1.5 else { return }
            if shelf.objects.contains(where: { $0.there && abs($0.at - shelf.paw) < Tuning.MiniGames.pawReach / 2 }),
               let index = shelf.tap()
            {
                lastAutoTap = time
                knock(index)
                onMoment?(.hit)
                game = .knock(shelf)
            }
        case var .string(chase):
            guard chase.string.isEmpty, chase.gathered < chase.sparkles.count else { return }
            let next = chase.sparkles.indices.filter { !chase.collected[$0] }
                .min { chase.sparkles[$0].distance(to: chase.cat) < chase.sparkles[$1].distance(to: chase.cat) }
            if let next {
                chase.draw([chase.sparkles[next]])
                game = .string(chase)
            }
        }
    }

    /// Everything where the game says it is.
    private func place() {
        switch game {
        case let .laser(laser):
            stage.childNode(withName: "dot")?.position = point(laser.dot)
            stage.childNode(withName: "dot")?.alpha = finger == nil ? 0.55 : 1
            move(to: laser.cat, velocity: laser.velocity)
        case let .knock(shelf):
            stage.childNode(withName: "paw")?.position = CGPoint(
                x: arena.minX + arena.width * CGFloat(shelf.paw),
                y: arena.minY + cell * 1.9
            )
        case let .string(chase):
            let speed = chase.string.isEmpty ? 0 : chase.speed
            let next = chase.string.first ?? chase.cat
            let heading = GamePoint(x: (next.x - chase.cat.x) * speed, y: (next.y - chase.cat.y) * speed)
            move(to: chase.cat, velocity: heading)
            if let line = stage.childNode(withName: "string") as? SKShapeNode {
                let path = CGMutablePath()
                if !chase.string.isEmpty {
                    path.move(to: point(chase.cat))
                    for p in chase.string {
                        path.addLine(to: point(p))
                    }
                }
                line.path = path
            }
        }
    }

    /// The cat to its place on the floor, walking, running or sitting by how fast it goes.
    private func move(to p: GamePoint, velocity: GamePoint) {
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        cat.position = point(p)
        cat.zPosition = 10 - CGFloat(p.y) * 0.1
        if speed > 0.3 {
            stoppedFor = 0
            let right = velocity.x >= 0
            if gait == .sitting {
                cat.rise(to: .side, facingRight: right)
                facingRight = right
            } else if right != facingRight, abs(velocity.x) > 0.25 {
                facingRight = right
                cat.show(.side, facingRight: right)
            }
            let wanted: Gait = speed > 2 ? .running : .walking
            if wanted != gait {
                gait = wanted
                wanted == .running ? cat.run() : cat.walk()
            }
        } else if gait != .sitting {
            stoppedFor += 1.0 / 60
            if stoppedFor > 0.35 {
                gait = .sitting
                cat.stopCycle()
                cat.settle(into: .sitThreeQuarterFront)
            }
        }
    }

    private func collect(_ index: Int) {
        guard let node = stage.childNode(withName: "sparkle\(index)") else { return }
        node.removeAllActions()
        node.run(.sequence([.group([.scale(to: 2, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        onMoment?(.sparkle)
    }

    private func knock(_ index: Int) {
        guard let node = stage.childNode(withName: "object\(index)") else { return }
        let floor = size.height * 0.12
        node.run(.sequence([
            .group([.moveBy(x: -cell * 0.6, y: cell * 0.35, duration: 0.12), .rotate(byAngle: 0.5, duration: 0.12)]),
            .group([.moveTo(y: floor, duration: 0.45), .rotate(byAngle: 2.2, duration: 0.45)]),
            .group([.moveBy(x: -cell * 0.2, y: cell * 0.2, duration: 0.1), .rotate(byAngle: 0.3, duration: 0.1)]),
            .moveTo(y: floor, duration: 0.1),
        ]))
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
                if let index = shelf.tap() {
                    knock(index)
                    onMoment?(.hit)
                } else {
                    onMoment?(.miss)
                    stage.childNode(withName: "paw")?.run(.sequence([
                        .moveBy(x: 6, y: 0, duration: 0.05),
                        .moveBy(x: -12, y: 0, duration: 0.1),
                        .moveBy(x: 6, y: 0, duration: 0.05),
                    ]))
                }
                game = .knock(shelf)
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
