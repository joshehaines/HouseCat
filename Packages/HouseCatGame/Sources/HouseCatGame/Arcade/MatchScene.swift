import HouseCatCore
import SpriteKit

/// Purrfect Match's board, drawn (the app puts the level's goals, moves and the cat beside it): the painted pieces
/// (`arcade/match/match_<kind>`) on a paper tray, dust under them, parcels and wool tangles over them. Drag a piece
/// onto a neighbour (or tap one, then the other) to swap; `MatchGame` (HouseCatCore) says what that does, wave by
/// wave, and the scene plays each wave out: the clears and blasts, the specials made, the falls and the new pieces
/// dropping in.
@MainActor
public final class MatchScene: SKScene {
    public struct Progress: Equatable, Sendable {
        public var score = 0
        public var movesLeft = 0
        public var remaining: [MatchGoal: Int] = [:]
        public var stars = 0
        public var over = false
        public var won = false

        public init(score: Int = 0, movesLeft: Int = 0, remaining: [MatchGoal: Int] = [:], stars: Int = 0, over: Bool = false,
                    won: Bool = false)
        {
            self.score = score
            self.movesLeft = movesLeft
            self.remaining = remaining
            self.stars = stars
            self.over = over
            self.won = won
        }
    }

    public enum Moment: Equatable, Sendable {
        case swapped, refused, cleared(count: Int, cascade: Int), made(MatchSpecial), fired(MatchSpecial), shuffled
    }

    public var onProgress: ((Progress) -> Void)?
    public var onMoment: ((Moment) -> Void)?
    public var onFinish: ((MatchGame) -> Void)?
    /// Debug runs and tests: the board plays itself (`MatchBot`'s choice each move).
    public var autoplay = false
    public private(set) var game: MatchGame

    private let art: ArtLibrary
    private let board = SKNode()
    private var pieces: [MatchPoint: SKNode] = [:]
    private var under: [MatchPoint: SKNode] = [:]
    private var over: [MatchPoint: SKNode] = [:]
    private var cell: CGFloat = 40
    private var origin = CGPoint.zero
    private var busy = false
    private var selected: MatchPoint?
    private var touchStart: (point: CGPoint, cell: MatchPoint)?
    private var finished = false
    private var shuffles = 0
    private var botSeed: DaySeed

    public init(size: CGSize, level: MatchLevel, seed: DaySeed, art: ArtLibrary) {
        game = MatchGame(level: level, seed: seed)
        botSeed = DaySeed(household: 1, day: GameDay(index: level.id), purpose: "match.autoplay")
        self.art = art
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
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

    private func position(_ p: MatchPoint) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(p.x) + 0.5) * cell, y: origin.y + (CGFloat(game.height - 1 - p.y) + 0.5) * cell)
    }

    private func cellAt(_ point: CGPoint) -> MatchPoint? {
        let x = Int(floor((point.x - origin.x) / cell))
        let row = Int(floor((point.y - origin.y) / cell))
        let p = MatchPoint(x, game.height - 1 - row)
        return game.isCell(p) ? p : nil
    }

    private func build() {
        guard size.width > 0, size.height > 0 else { return }
        removeAllChildren()
        board.removeAllChildren()
        pieces = [:]
        under = [:]
        over = [:]
        let pad = CGFloat(Tuning.Arcade.Match.boardPadding)
        cell = min((size.width - 2 * pad) / CGFloat(game.width), (size.height - 2 * pad) / CGFloat(game.height))
        origin = CGPoint(x: (size.width - cell * CGFloat(game.width)) / 2, y: (size.height - cell * CGFloat(game.height)) / 2)
        addChild(board)
        // The tray: the board's cells in two creams, inside a soft frame.
        let frame = SKShapeNode(rect: CGRect(x: origin.x - pad * 0.6, y: origin.y - pad * 0.6, width: cell * CGFloat(game.width) + pad * 1.2,
                                             height: cell * CGFloat(game.height) + pad * 1.2), cornerRadius: cell * 0.35)
        frame.fillColor = SKColor(red: 0.42, green: 0.3, blue: 0.24, alpha: 0.3)
        frame.strokeColor = SKColor(red: 1, green: 0.96, blue: 0.84, alpha: 0.75)
        frame.lineWidth = 2.5
        frame.zPosition = -10
        board.addChild(frame)
        for y in 0 ..< game.height {
            for x in 0 ..< game.width {
                let p = MatchPoint(x, y)
                guard game.isCell(p) else { continue }
                let tile = SKShapeNode(rectOf: CGSize(width: cell, height: cell))
                tile.fillColor = (x + y) % 2 == 0 ? SKColor(red: 1, green: 0.98, blue: 0.93, alpha: 0.72)
                    : SKColor(red: 1, green: 0.96, blue: 0.88, alpha: 0.52)
                tile.strokeColor = .clear
                tile.position = position(p)
                tile.zPosition = -5
                board.addChild(tile)
            }
        }
        refreshAll()
        report()
    }

    // MARK: Pictures

    private func picture(_ path: String, fill: CGFloat) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: art.texture(path))
        let painted = art.paintedSize(path)
        let side = cell * fill
        let scale = side / max(1, max(painted.width, painted.height))
        sprite.size = CGSize(width: painted.width * scale, height: painted.height * scale)
        return sprite
    }

    /// A piece as drawn: its painting, a special's mark on it.
    private func node(for piece: MatchPiece) -> SKNode {
        let holder = SKNode()
        switch piece.special {
        case .laser:
            holder.addChild(picture("arcade/match/match_laser.png", fill: 0.92))
        case .box:
            let box = picture("arcade/match/match_box.png", fill: 0.9)
            holder.addChild(box)
            if let kind = piece.kind {
                let badge = picture("arcade/match/match_\(kind.name).png", fill: 0.42)
                badge.position = CGPoint(x: cell * 0.22, y: -cell * 0.2)
                badge.zPosition = 1
                holder.addChild(badge)
            }
        default:
            if let kind = piece.kind {
                holder.addChild(picture("arcade/match/match_\(kind.name).png", fill: 0.84))
            }
            if piece.special == .swipeRow || piece.special == .swipeColumn {
                // Claw marks across the piece, the way the swipe will go.
                for n in -1 ... 1 {
                    let mark = SKShapeNode(rectOf: CGSize(width: cell * 0.72, height: max(2, cell * 0.06)), cornerRadius: cell * 0.03)
                    mark.fillColor = SKColor(white: 1, alpha: 0.92)
                    mark.strokeColor = SKColor(red: 0.3, green: 0.2, blue: 0.3, alpha: 0.35)
                    mark.position = piece.special == .swipeRow ? CGPoint(x: 0, y: CGFloat(n) * cell * 0.16) : CGPoint(x: CGFloat(n) * cell * 0.16, y: 0)
                    if piece.special == .swipeColumn { mark.zRotation = .pi / 2 }
                    mark.zPosition = 2
                    holder.addChild(mark)
                }
                holder.run(.repeatForever(.sequence([.scale(to: 1.06, duration: 0.5), .scale(to: 1, duration: 0.5)])))
            }
        }
        return holder
    }

    /// Everything drawn again from the game (after a level starts, a shuffle, or if a wave's pictures drift).
    private func refreshAll() {
        for node in Array(pieces.values) + Array(under.values) + Array(over.values) {
            node.removeFromParent()
        }
        pieces = [:]
        under = [:]
        over = [:]
        for y in 0 ..< game.height {
            for x in 0 ..< game.width {
                let p = MatchPoint(x, y)
                guard game.isCell(p) else { continue }
                refreshCover(p)
                if let piece = game.piece(at: p) {
                    let node = node(for: piece)
                    node.position = position(p)
                    node.zPosition = 10
                    board.addChild(node)
                    pieces[p] = node
                }
            }
        }
    }

    /// The dust under a cell and the parcel or tangle over it, as the game has them now.
    private func refreshCover(_ p: MatchPoint) {
        under[p]?.removeFromParent()
        under[p] = nil
        over[p]?.removeFromParent()
        over[p] = nil
        let dust = game.dust(at: p)
        if dust > 0 {
            let node = picture("arcade/match/match_dust.png", fill: 1.08)
            node.alpha = dust > 1 ? 1 : 0.75
            if dust > 1 { node.setScale(1.12) }
            node.position = position(p)
            node.zPosition = 2
            board.addChild(node)
            under[p] = node
        }
        let parcel = game.parcel(at: p)
        if parcel > 0 {
            let node = picture("arcade/match/match_parcel\(parcel > 1 ? 2 : 1).png", fill: 0.92)
            node.position = position(p)
            node.zPosition = 12
            board.addChild(node)
            over[p] = node
        } else if game.isTangled(p) {
            let node = picture("arcade/match/match_tangle.png", fill: 1.0)
            node.position = position(p)
            node.zPosition = 14
            board.addChild(node)
            over[p] = node
        }
    }

    /// Tells the app where the level stands (the scene does after every move; call it once the callbacks are set).
    public func report() {
        var remaining: [MatchGoal: Int] = [:]
        for goal in game.goals {
            remaining[goal] = game.remaining(goal)
        }
        onProgress?(Progress(score: game.score, movesLeft: game.movesLeft, remaining: remaining, stars: game.stars, over: game.isOver,
                             won: game.goalsMet))
    }

    // MARK: Moves

    /// Tries a swap: refused ones wobble back; a move plays out wave by wave.
    public func trySwap(_ a: MatchPoint, _ b: MatchPoint) {
        guard !busy, !finished, MatchGame.neighbours(a, b), let na = pieces[a], let nb = pieces[b] else { return }
        selected = nil
        busy = true
        let t = Tuning.Arcade.Match.swapSeconds
        guard game.canSwap(a, b) else {
            onMoment?(.refused)
            na.run(.sequence([.move(to: position(b), duration: t), .move(to: position(a), duration: t)]))
            nb.run(.sequence([.move(to: position(a), duration: t), .move(to: position(b), duration: t), .run { [weak self] in self?.busy = false }]))
            return
        }
        onMoment?(.swapped)
        na.run(.move(to: position(b), duration: t))
        nb.run(.move(to: position(a), duration: t))
        pieces[a] = nb
        pieces[b] = na
        let waves = game.swap(a, b)
        run(.sequence([.wait(forDuration: t), .run { [weak self] in self?.play(waves, from: 0) }]))
    }

    private func play(_ waves: [MatchWave], from index: Int) {
        guard index < waves.count else {
            settleDone()
            return
        }
        let wave = waves[index]
        let m = Tuning.Arcade.Match.self
        // Blasts first, so the cleared pieces go as the sweep reaches them.
        for (p, special) in wave.fired {
            blast(special, at: p)
            onMoment?(.fired(special))
        }
        for (p, _) in wave.cleared {
            guard let node = pieces.removeValue(forKey: p) else { continue }
            node.removeAllActions()
            node.run(.sequence([.group([.scale(to: 1.25, duration: m.popSeconds * 0.4), .fadeAlpha(to: 0.9, duration: m.popSeconds * 0.4)]),
                                .group([.scale(to: 0.1, duration: m.popSeconds * 0.6), .fadeOut(withDuration: m.popSeconds * 0.6)]),
                                .removeFromParent()]))
            sparkle(at: position(p))
        }
        onMoment?(.cleared(count: wave.cleared.count, cascade: wave.cascade))
        for (p, piece) in wave.made {
            let node = node(for: piece)
            node.position = position(p)
            node.zPosition = 10
            node.setScale(0.2)
            node.run(.scale(to: 1, duration: m.popSeconds))
            board.addChild(node)
            pieces[p]?.removeFromParent()
            pieces[p] = node
            if let special = piece.special { onMoment?(.made(special)) }
        }
        for p in wave.dustCleared.union(wave.parcelsHit).union(wave.tanglesCleared) {
            refreshCover(p)
        }
        // The falls and the new pieces, once the clears have gone.
        run(.sequence([.wait(forDuration: m.popSeconds), .run { [weak self] in
            guard let self else { return }
            var moving: [(SKNode, MatchPoint, MatchPoint)] = []
            for fall in wave.falls {
                if let node = pieces.removeValue(forKey: fall.from) {
                    moving.append((node, fall.from, fall.to))
                }
            }
            var longest = 0.0
            for (node, from, to) in moving {
                pieces[to] = node
                let rows = Double(abs(to.y - from.y)) + Double(abs(to.x - from.x))
                let time = m.fallSeconds * max(1, rows).squareRoot()
                longest = max(longest, time)
                node.run(.move(to: position(to), duration: time))
            }
            // New pieces drop in from above their column, the lowest first.
            var dropIn: [Int: Int] = [:]
            for (p, piece) in wave.spawned.sorted(by: { $0.key.y > $1.key.y }) {
                let node = node(for: piece)
                let above = (dropIn[p.x] ?? 0) + 1
                dropIn[p.x] = above
                // The top of the run of open cells it is in (the board's top, or just under a parcel, tangle or gap).
                var top = p.y
                while top > 0, game.isCell(MatchPoint(p.x, top - 1)), game.parcel(at: MatchPoint(p.x, top - 1)) == 0,
                      !game.isTangled(MatchPoint(p.x, top - 1)) {
                    top -= 1
                }
                let start = position(MatchPoint(p.x, top - above))
                node.position = start
                node.zPosition = 10
                node.alpha = 0
                board.addChild(node)
                pieces[p] = node
                let rows = Double(p.y - (top - above))
                let time = m.fallSeconds * max(1, rows).squareRoot()
                longest = max(longest, time)
                node.run(.group([.move(to: position(p), duration: time), .fadeIn(withDuration: time * 0.4)]))
            }
            run(.sequence([.wait(forDuration: longest + 0.02), .run { [weak self] in self?.play(waves, from: index + 1) }]))
        }]))
    }

    private func settleDone() {
        if game.shuffles != shuffles {
            shuffles = game.shuffles
            onMoment?(.shuffled)
            refreshAll()
            for node in pieces.values {
                node.setScale(0.1)
                node.run(.scale(to: 1, duration: 0.3))
            }
        } else {
            // Anything drawn that is not what the game has is redrawn (a safety net; it should never happen).
            var drift = false
            for y in 0 ..< game.height {
                for x in 0 ..< game.width {
                    let p = MatchPoint(x, y)
                    if (pieces[p] == nil) != (game.piece(at: p) == nil) { drift = true }
                }
            }
            if drift { refreshAll() }
        }
        busy = false
        report()
        if game.isOver, !finished {
            finished = true
            run(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
                guard let self else { return }
                onFinish?(game)
            }]))
        }
    }

    // MARK: Effects

    private func sparkle(at point: CGPoint) {
        for n in 0 ..< 4 {
            let dot = SKShapeNode(circleOfRadius: max(2, cell * 0.06))
            dot.fillColor = SKColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
            dot.strokeColor = .clear
            dot.position = point
            dot.zPosition = 30
            board.addChild(dot)
            let angle = CGFloat(n) * .pi / 2 + .pi / 4
            dot.run(.sequence([.group([.moveBy(x: cos(angle) * cell * 0.5, y: sin(angle) * cell * 0.5, duration: 0.25),
                                        .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
        }
    }

    private func blast(_ special: MatchSpecial, at p: MatchPoint) {
        let centre = position(p)
        let width = cell * CGFloat(game.width), height = cell * CGFloat(game.height)
        let glow = SKColor(red: 1, green: 0.97, blue: 0.85, alpha: 0.95)
        switch special {
        case .swipeRow, .swipeColumn:
            let bar = SKShapeNode(rectOf: special == .swipeRow ? CGSize(width: width, height: cell * 0.5) : CGSize(width: cell * 0.5, height: height),
                                  cornerRadius: cell * 0.25)
            bar.fillColor = glow
            bar.strokeColor = .clear
            bar.position = special == .swipeRow ? CGPoint(x: origin.x + width / 2, y: centre.y) : CGPoint(x: centre.x, y: origin.y + height / 2)
            bar.zPosition = 40
            bar.alpha = 0
            board.addChild(bar)
            bar.run(.sequence([.fadeAlpha(to: 0.9, duration: 0.06), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        case .box:
            let ring = SKShapeNode(circleOfRadius: cell * 0.5)
            ring.strokeColor = glow
            ring.lineWidth = cell * 0.18
            ring.fillColor = .clear
            ring.position = centre
            ring.zPosition = 40
            board.addChild(ring)
            ring.run(.sequence([.group([.scale(to: 3.2, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        case .laser:
            let flash = SKShapeNode(circleOfRadius: cell * 0.6)
            flash.fillColor = SKColor(red: 1, green: 0.2, blue: 0.25, alpha: 0.7)
            flash.strokeColor = .clear
            flash.position = centre
            flash.zPosition = 40
            board.addChild(flash)
            flash.run(.sequence([.group([.scale(to: 6, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
    }

    // MARK: The loop and the finger

    private var autoplayWait = 0.0
    private var lastUpdate: TimeInterval?

    override public func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 20, lastUpdate.map { currentTime - $0 } ?? 0)
        lastUpdate = currentTime
        guard autoplay, !busy, !finished, !game.isOver else { return }
        autoplayWait += dt
        guard autoplayWait > 0.6 else { return }
        autoplayWait = 0
        if let move = MatchBot.choose(game, seed: &botSeed) {
            trySwap(move.0, move.1)
        }
    }

    #if os(iOS)
        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first, let p = cellAt(touch.location(in: self)) else { return }
            touchStart = (touch.location(in: self), p)
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first, let start = touchStart else { return }
            let d = CGPoint(x: touch.location(in: self).x - start.point.x, y: touch.location(in: self).y - start.point.y)
            guard max(abs(d.x), abs(d.y)) > cell * 0.35 else { return }
            touchStart = nil
            let target = abs(d.x) > abs(d.y) ? MatchPoint(start.cell.x + (d.x > 0 ? 1 : -1), start.cell.y)
                : MatchPoint(start.cell.x, start.cell.y + (d.y > 0 ? -1 : 1))
            trySwap(start.cell, target)
        }

        override public func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
            guard let start = touchStart else { return }
            touchStart = nil
            // A tap picks a piece; a tap on its neighbour swaps them.
            if let chosen = selected, MatchGame.neighbours(chosen, start.cell) {
                trySwap(chosen, start.cell)
            } else {
                selected = start.cell
                pieces[start.cell]?.run(.sequence([.scale(to: 1.15, duration: 0.08), .scale(to: 1, duration: 0.12)]))
            }
        }
    #endif
}
