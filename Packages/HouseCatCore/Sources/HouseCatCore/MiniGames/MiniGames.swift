import Foundation

/// A point on a mini-game's floor, in cells (the arena is `Tuning.MiniGames.arenaWidth` by `arenaHeight`,
/// origin bottom left).
public struct GamePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: GamePoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }

    /// The point `length` cells from here towards `target` (or the target, if nearer).
    public func moved(towards target: GamePoint, by length: Double) -> GamePoint {
        let gap = distance(to: target)
        guard gap > length, gap > 0 else { return target }
        return GamePoint(x: x + (target.x - x) / gap * length, y: y + (target.y - y) / gap * length)
    }

    /// Kept inside the arena.
    public var clamped: GamePoint {
        GamePoint(x: min(max(x, 0), Tuning.MiniGames.arenaWidth), y: min(max(y, 0), Tuning.MiniGames.arenaHeight))
    }
}

/// The mini-games' shared rules (SPEC "Mini-games", CONTENT.md §6): stars from the score against the game's
/// thresholds, five plays a day (the reducer pays them: `miniGamePlayed`), and the cat's speed by personality,
/// which changes how a game feels but never its thresholds.
public enum MiniGameRules {
    public static func stars(score: Double, thresholds: [Int]) -> Int {
        thresholds.filter { score >= Double($0) }.count
    }

    /// Plays left today (the state resolved through today).
    public static func playsLeft(_ state: HouseholdState) -> Int {
        max(0, Tuning.MiniGames.playsPerDay - (state.today?.plays ?? 0))
    }

    /// How fast the cat chases, in cells a second.
    public static func chaseSpeed(_ personality: Personality) -> Double {
        Tuning.MiniGames.chaseSpeed[personality.rawValue] ?? 3.2
    }

    /// The line after a game: a win with any star, otherwise the gentle loss (never an upset cat).
    public static func endLine(stars: Int) -> String {
        stars > 0 ? "play.win" : "play.lose"
    }
}

/// Laser Pointer (CONTENT.md: drag the dot, the cat chases it; each second within one cell of the dot scores,
/// 30 s). The cat steers with some weight to it, and a dot left still is soon ignored, as a cat would.
public struct LaserChase: Equatable, Sendable {
    public private(set) var cat: GamePoint
    public private(set) var velocity = GamePoint(x: 0, y: 0)
    public private(set) var dot: GamePoint
    public private(set) var elapsed = 0.0
    public private(set) var score = 0.0
    /// How long the dot has been still.
    public private(set) var stillFor = 0.0
    public let duration: Double
    public let speed: Double

    public init(duration: Double, personality: Personality) {
        self.duration = duration
        speed = MiniGameRules.chaseSpeed(personality)
        cat = GamePoint(x: Tuning.MiniGames.arenaWidth * 0.3, y: Tuning.MiniGames.arenaHeight * 0.4)
        dot = GamePoint(x: Tuning.MiniGames.arenaWidth * 0.6, y: Tuning.MiniGames.arenaHeight * 0.5)
    }

    public var isOver: Bool {
        elapsed >= duration
    }

    /// Whether the cat is after the dot (a still dot bores it).
    public var interested: Bool {
        stillFor < Tuning.MiniGames.laserBoredSeconds
    }

    /// Within a cell of the dot: scoring now.
    public var onTheDot: Bool {
        interested && cat.distance(to: dot) <= 1
    }

    /// Moves the dot (the finger) and the cat on by `dt` seconds.
    public mutating func step(_ dt: Double, dot newDot: GamePoint? = nil) {
        guard !isOver else { return }
        let dt = min(dt, duration - elapsed)
        if let newDot {
            // Moving if it goes faster than a crawl.
            let moved = newDot.clamped.distance(to: dot)
            stillFor = moved / max(dt, 0.001) > Tuning.MiniGames.laserMovingSpeed ? 0 : stillFor + dt
            dot = newDot.clamped
        } else {
            stillFor += dt
        }
        // Steer towards the dot with a little inertia: it takes a moment to turn and a fast zigzag loses it.
        var target = GamePoint(x: 0, y: 0)
        if interested {
            let gap = cat.distance(to: dot)
            if gap > 0.15 {
                target = GamePoint(x: (dot.x - cat.x) / gap * speed, y: (dot.y - cat.y) / gap * speed)
            }
        }
        let grip = min(1, Tuning.MiniGames.laserGrip * dt)
        velocity = GamePoint(x: velocity.x + (target.x - velocity.x) * grip, y: velocity.y + (target.y - velocity.y) * grip)
        cat = GamePoint(x: cat.x + velocity.x * dt, y: cat.y + velocity.y * dt).clamped
        if onTheDot {
            score += dt
        }
        elapsed += dt
    }
}

/// Knock It Off (CONTENT.md: five objects on a shelf, tap when the cat's paw is over one, hits chain, 20 s).
/// The paw sweeps the shelf back and forth, a little faster after each hit; a miss breaks the chain and the
/// cat stops to look at you for a moment.
public struct KnockItOff: Equatable, Sendable {
    public struct Object: Equatable, Sendable {
        /// Its place along the shelf, 0 to 1.
        public var at: Double
        public var there: Bool
    }

    public private(set) var objects: [Object]
    /// The paw along the shelf, 0 to 1.
    public private(set) var paw = 0.0
    public private(set) var elapsed = 0.0
    public private(set) var chain = 0
    public private(set) var bestChain = 0
    /// After a miss the paw rests this long.
    public private(set) var resting = 0.0
    private var direction = 1.0
    private var sweep: Double
    public let duration: Double

    public init(duration: Double, personality: Personality) {
        self.duration = duration
        let count = Tuning.MiniGames.shelfObjects
        objects = (0 ..< count).map { Object(at: (Double($0) + 0.5) / Double(count), there: true) }
        // The chase speed sets how fast the paw sweeps (a gremlin swipes, a loaf bats).
        sweep = MiniGameRules.chaseSpeed(personality) / Tuning.MiniGames.pawSweepCells
    }

    public var knocked: Int {
        objects.filter { !$0.there }.count
    }

    public var isOver: Bool {
        elapsed >= duration || knocked == objects.count
    }

    public var score: Double {
        Double(knocked)
    }

    public mutating func step(_ dt: Double) {
        guard !isOver else { return }
        let dt = min(dt, duration - elapsed)
        elapsed += dt
        // A rest after a miss uses up the start of the step; the paw moves for what is left.
        let rest = min(resting, dt)
        resting -= rest
        let moving = dt - rest
        guard moving > 0 else { return }
        paw += direction * sweep * moving
        if paw >= 1 {
            paw = 2 - paw
            direction = -1
        } else if paw <= 0 {
            paw = -paw
            direction = 1
        }
    }

    /// A tap: the object under the paw goes over the edge, or the chain breaks. Returns the object knocked.
    @discardableResult
    public mutating func tap() -> Int? {
        guard !isOver, resting == 0 else { return nil }
        if let index = objects.firstIndex(where: { $0.there && abs($0.at - paw) <= Tuning.MiniGames.pawReach }) {
            objects[index].there = false
            chain += 1
            bestChain = max(bestChain, chain)
            sweep *= Tuning.MiniGames.pawSpeedUp
            return index
        }
        chain = 0
        resting = Tuning.MiniGames.missRestSeconds
        return nil
    }
}

/// String Chase (CONTENT.md: draw a path with one finger, the cat follows the string and collects the five
/// sparkles along it, 30 s). A new string starts from wherever the finger goes down; the cat runs to it first.
public struct StringChase: Equatable, Sendable {
    public private(set) var sparkles: [GamePoint]
    public private(set) var collected: [Bool]
    public private(set) var cat: GamePoint
    public private(set) var string: [GamePoint] = []
    public private(set) var elapsed = 0.0
    public let duration: Double
    public let speed: Double

    /// The sparkles are laid out by the day's seed, so a replay of the same play is the same game.
    public init(duration: Double, personality: Personality, seed: inout DaySeed) {
        self.duration = duration
        speed = MiniGameRules.chaseSpeed(personality)
        let w = Tuning.MiniGames.arenaWidth, h = Tuning.MiniGames.arenaHeight
        cat = GamePoint(x: w / 2, y: h * 0.2)
        var points: [GamePoint] = []
        while points.count < Tuning.MiniGames.sparkles {
            let point = GamePoint(
                x: 1 + Double(seed.below(1000)) / 1000 * (w - 2),
                y: 1 + Double(seed.below(1000)) / 1000 * (h - 2)
            )
            if points.allSatisfy({ $0.distance(to: point) > 2 }), point.distance(to: cat) > 2 {
                points.append(point)
            }
        }
        sparkles = points
        collected = points.map { _ in false }
    }

    public var gathered: Int {
        collected.filter(\.self).count
    }

    public var isOver: Bool {
        elapsed >= duration || gathered == sparkles.count
    }

    public var score: Double {
        Double(gathered)
    }

    /// A new string (the finger's path, oldest point first).
    public mutating func draw(_ path: [GamePoint]) {
        string = path.map(\.clamped)
    }

    /// The finger keeps drawing: the string grows at its end.
    public mutating func extend(_ point: GamePoint) {
        string.append(point.clamped)
    }

    public mutating func step(_ dt: Double) {
        guard !isOver else { return }
        let dt = min(dt, duration - elapsed)
        elapsed += dt
        var budget = speed * dt
        // Along the string from its start, dropping each point the cat reaches.
        while budget > 0, let next = string.first {
            let gap = cat.distance(to: next)
            if gap <= budget {
                cat = next
                budget -= gap
                string.removeFirst()
            } else {
                cat = cat.moved(towards: next, by: budget)
                budget = 0
            }
            collect()
        }
        collect()
    }

    private mutating func collect() {
        for index in sparkles.indices where !collected[index] && cat.distance(to: sparkles[index]) <= Tuning.MiniGames.sparkleReach {
            collected[index] = true
        }
    }
}

/// The nap (SPEC "Care": a 20-minute wind-down timer as a Live Activity; complete it for XP). The reducer pays
/// `napCompleted` once a day; waking the cat early pays nothing.
public enum NapRules {
    public static func end(of start: Date) -> Date {
        start.addingTimeInterval(Tuning.Nap.minutes * 60)
    }

    public static func isComplete(startedAt start: Date, at date: Date) -> Bool {
        date >= end(of: start)
    }

    /// Whether today's nap would still pay (the state resolved through today).
    public static func pays(_ state: HouseholdState) -> Bool {
        state.today?.napped == false
    }
}
